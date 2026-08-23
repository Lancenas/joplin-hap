// Bidirectional synchroniser for Joplin Server. Implements a compact version of
// laurent22/joplin's Synchronizer that exercises the same primitives:
//   1. update_remote  – push items that have changed locally
//   2. delete_remote  – push local deletions
//   3. delta          – pull the remote change set, apply locally
//
// The cursor is opaque to us; the server returns it with each delta response
// and we persist it in the settings table under "sync.cursor".
//
// ArkTS notes: object literals need a declared type and cannot use computed or
// quoted keys, and destructuring declarations are rejected — hence the classes
// and the explicit index access below.
import { JoplinApi, HeaderMap, QueryMap, apiFilePath, DELTA_PATH, TEXT_MIME } from './JoplinApi';
import {
  DeserializedItem, PropRecord, recordToFolder, recordToNote, recordToTag,
  serializeFolder, serializeNote, serializeNoteTag, serializeTag, unserializeItem
} from './ItemSerializer';
import { folderRepo, noteRepo, noteTagRepo, settingsRepo, tagRepo } from '../services/Repositories';
import { Folder, Note, NoteTag, Tag } from '../models/Entities';
import { ItemType, SyncTarget } from '../utils/Constants';
import { Row, exec, queryAll, queryOne } from '../db/Query';

export enum SyncPhase {
  Idle = 'idle',
  UpdateRemote = 'update_remote',
  DeleteRemote = 'delete_remote',
  Delta = 'delta',
  Done = 'done',
  Error = 'error',
}

export class SyncProgress {
  phase: SyncPhase;
  message: string;
  pushed: number;
  pulled: number;
  deleted: number;
  total: number;
  done: number;

  constructor(phase: SyncPhase, message: string, pushed: number = 0, pulled: number = 0,
              deleted: number = 0, total: number = 0, done: number = 0) {
    this.phase = phase;
    this.message = message;
    this.pushed = pushed;
    this.pulled = pulled;
    this.deleted = deleted;
    this.total = total;
    this.done = done;
  }
}

export class SyncResult {
  ok: boolean = true;
  pushed: number = 0;
  pulled: number = 0;
  deleted: number = 0;
  error: string = '';
  durationMs: number = 0;
}

interface DeltaItem {
  id: string;
  type_: number;
  path?: string;
  updated_time?: number;
  isDeleted?: boolean;
}

interface DeltaResponse {
  items?: DeltaItem[];
  cursor?: string;
  has_more?: boolean;
}

class BatchDeleteRequest {
  items: string[];

  constructor(items: string[]) {
    this.items = items;
  }
}

// Joplin appends a type-dependent extension to the remote item path.
function extForType(itemType: number): string {
  if (itemType === ItemType.Note) {
    return '.md';
  }
  if (itemType === ItemType.Resource) {
    return '.resource';
  }
  return '';
}

function parseDelta(s: string): DeltaResponse {
  const empty: DeltaResponse = {};
  if (!s) {
    return empty;
  }
  try {
    return JSON.parse(s) as DeltaResponse;
  } catch (err) {
    return empty;
  }
}

function textHeaders(): HeaderMap {
  const h: HeaderMap = {};
  h['Content-Type'] = TEXT_MIME;
  return h;
}

export class Synchronizer {
  api: JoplinApi;
  report: (p: SyncProgress) => void;
  baseUrl: string;
  username: string;
  password: string;

  constructor(baseUrl: string, username: string, password: string) {
    this.baseUrl = baseUrl;
    this.username = username;
    this.password = password;
    this.api = new JoplinApi(baseUrl);
    this.api.username = username;
    this.api.password = password;
    this.report = (p: SyncProgress) => {};
  }

  onProgress(fn: (p: SyncProgress) => void): void {
    this.report = fn;
  }

  async run(): Promise<SyncResult> {
    const start: number = Date.now();
    const result: SyncResult = new SyncResult();
    this.report(new SyncProgress(SyncPhase.Idle, 'Connecting…'));

    try {
      await this.api.session();

      this.report(new SyncProgress(SyncPhase.UpdateRemote, 'Pushing local changes…'));
      result.pushed = await this.pushLocal();

      this.report(new SyncProgress(SyncPhase.DeleteRemote, 'Pushing deletions…', result.pushed));
      result.deleted = await this.pushDeletions();

      this.report(new SyncProgress(SyncPhase.Delta, 'Fetching remote changes…', result.pushed, 0, result.deleted));
      result.pulled = await this.pullDelta();

      this.report(new SyncProgress(SyncPhase.Done, 'Sync complete',
        result.pushed, result.pulled, result.deleted));
    } catch (e) {
      result.ok = false;
      result.error = (e as Error).message;
      this.report(new SyncProgress(SyncPhase.Error, result.error,
        result.pushed, result.pulled, result.deleted));
    }
    result.durationMs = Date.now() - start;
    return result;
  }

  // Anything in sync_items with sync_time = 0 still needs to go up. The UNION
  // sub-select gives us the local updated_time per (type, id) pair in one shot.
  private async pushLocal(): Promise<number> {
    const rows: Row[] = await queryAll(
      `SELECT si.id AS sid, si.item_type AS item_type, si.item_id AS item_id,
              items.updated_time AS local_updated_time
         FROM sync_items si
         JOIN (
           SELECT 1 AS type_, id, updated_time FROM notes
           UNION ALL SELECT 2, id, updated_time FROM folders
           UNION ALL SELECT 4, id, updated_time FROM resources
           UNION ALL SELECT 5, id, updated_time FROM tags
           UNION ALL SELECT 7, id, updated_time FROM note_tags
         ) items ON items.type_ = si.item_type AND items.id = si.item_id
        WHERE si.sync_target = ? AND si.sync_time = 0`,
      [SyncTarget.JoplinServer]
    );
    let pushed: number = 0;
    for (const r of rows) {
      const sid: number = Number(r['sid'] ?? 0);
      const itemType: number = Number(r['item_type'] ?? 0);
      const itemId: string = String(r['item_id'] ?? '');
      try {
        await this.uploadItem(itemType, itemId);
        await exec('UPDATE sync_items SET sync_time = ? WHERE id = ?',
          [Number(r['local_updated_time'] ?? 0), sid]);
        pushed += 1;
      } catch (e) {
        // A single failed item should not abort the whole round.
        this.report(new SyncProgress(SyncPhase.UpdateRemote,
          `Push failed for ${itemId}: ${(e as Error).message}`, pushed));
      }
    }
    return pushed;
  }

  private async uploadItem(itemType: number, itemId: string): Promise<void> {
    const path: string = apiFilePath(itemId, extForType(itemType));

    if (itemType === ItemType.Note) {
      const note: Note | null = await noteRepo.get(itemId);
      if (note === null) {
        return;
      }
      await this.api.exec('PUT', path, null, serializeNote(note), textHeaders());
      return;
    }

    if (itemType === ItemType.Folder) {
      const folder: Folder | null = await folderRepo.get(itemId);
      if (folder === null) {
        return;
      }
      await this.api.exec('PUT', path, null, serializeFolder(folder), textHeaders());
      return;
    }

    if (itemType === ItemType.Tag) {
      const tag: Tag | null = await tagRepo.get(itemId);
      if (tag === null) {
        return;
      }
      await this.api.exec('PUT', path, null, serializeTag(tag), textHeaders());
      return;
    }

    if (itemType === ItemType.NoteTag) {
      const row: Row | null = await queryOne('SELECT * FROM note_tags WHERE id = ?', [itemId]);
      if (row === null) {
        return;
      }
      const noteTag: NoteTag = {
        type_: ItemType.NoteTag,
        id: String(row['id'] ?? ''),
        noteId: String(row['note_id'] ?? ''),
        tagId: String(row['tag_id'] ?? ''),
        createdTime: Number(row['created_time'] ?? 0),
        updatedTime: Number(row['updated_time'] ?? 0),
        userCreatedTime: Number(row['user_created_time'] ?? 0),
        userUpdatedTime: Number(row['user_updated_time'] ?? 0),
      };
      await this.api.exec('PUT', path, null, serializeNoteTag(noteTag), textHeaders());
    }
  }

  private async pushDeletions(): Promise<number> {
    const rows: Row[] = await queryAll('SELECT id, item_type, item_id FROM deleted_items');
    if (rows.length === 0) {
      return 0;
    }
    const paths: string[] = [];
    for (const r of rows) {
      const ext: string = extForType(Number(r['item_type'] ?? 0));
      paths.push(apiFilePath(String(r['item_id'] ?? ''), ext));
    }
    try {
      const payload: string = JSON.stringify(new BatchDeleteRequest(paths));
      await this.api.exec('POST', 'api/batch_delete', null, payload);
    } catch (e) {
      // Older servers have no batch_delete endpoint; fall back to one-by-one.
      for (const p of paths) {
        try {
          await this.api.exec('DELETE', p);
        } catch (inner) {
          // Ignore individual failures — the item may already be gone.
        }
      }
    }
    await exec('DELETE FROM deleted_items');
    return rows.length;
  }

  private async pullDelta(): Promise<number> {
    let cursor: string = (await settingsRepo.get('sync.cursor')) ?? '';
    let pulled: number = 0;
    let totalKnown: number = 0;
    let safety: number = 0;

    while (safety < 1000) {
      safety += 1;
      const q: QueryMap = {};
      if (cursor !== '') {
        q['cursor'] = cursor;
      }
      const res = await this.api.exec('GET', DELTA_PATH, q);
      const parsed: DeltaResponse = parseDelta(res.body);
      const items: DeltaItem[] = parsed.items ?? [];
      totalKnown += items.length;
      this.report(new SyncProgress(SyncPhase.Delta,
        `Applying ${items.length} change(s)…`, 0, pulled, 0, totalKnown, totalKnown - items.length));

      for (const remote of items) {
        try {
          await this.applyRemote(remote);
          pulled += 1;
        } catch (e) {
          this.report(new SyncProgress(SyncPhase.Delta,
            `Failed to apply ${remote.id}: ${(e as Error).message}`, 0, pulled, 0, totalKnown, pulled));
        }
      }

      const nextCursor: string = parsed.cursor ?? '';
      if (nextCursor !== '') {
        cursor = nextCursor;
        await settingsRepo.set('sync.cursor', cursor);
      }
      if (parsed.has_more !== true) {
        break;
      }
    }
    return pulled;
  }

  private async applyRemote(remote: DeltaItem): Promise<void> {
    if (remote.isDeleted === true) {
      await this.deleteLocalByType(remote.type_, remote.id);
      return;
    }
    const path: string = remote.path ?? apiFilePath(remote.id, extForType(remote.type_));
    const res = await this.api.exec('GET', path);
    const item: DeserializedItem = unserializeItem(res.body);
    if (item.typeId !== remote.type_) {
      // Mismatched type marker; skip rather than corrupt the local store.
      return;
    }
    const raw: PropRecord = item.raw;
    if (raw['id'] === undefined || raw['id'] === null || raw['id'] === '') {
      raw['id'] = remote.id;
    }

    if (item.typeId === ItemType.Note) {
      await noteRepo.upsert(recordToNote(raw), false);
      return;
    }
    if (item.typeId === ItemType.Folder) {
      await folderRepo.upsert(recordToFolder(raw), false);
      return;
    }
    if (item.typeId === ItemType.Tag) {
      await tagRepo.upsert(recordToTag(raw), false);
      return;
    }
    if (item.typeId === ItemType.NoteTag) {
      const noteId: string = String(raw['note_id'] ?? '');
      const tagId: string = String(raw['tag_id'] ?? '');
      if (noteId !== '' && tagId !== '') {
        await noteTagRepo.add(noteId, tagId, false);
      }
    }
  }

  private async deleteLocalByType(itemType: number, id: string): Promise<void> {
    if (itemType === ItemType.Note) {
      await noteRepo.delete(id, false);
      return;
    }
    if (itemType === ItemType.Folder) {
      await folderRepo.delete(id, false);
      return;
    }
    if (itemType === ItemType.Tag) {
      await tagRepo.delete(id, false);
      return;
    }
    if (itemType === ItemType.NoteTag) {
      const parts: string[] = id.split('_');
      if (parts.length === 2 && parts[0] !== '' && parts[1] !== '') {
        await noteTagRepo.remove(parts[0], parts[1], false);
      }
    }
  }
}
