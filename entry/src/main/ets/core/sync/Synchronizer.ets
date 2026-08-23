// Bidirectional synchroniser for Joplin Server. Implements a compact version of
// laurent22/joplin's Synchronizer that exercises the same primitives:
//   1. update_remote  – push items that have changed locally
//   2. delete_remote  – push local deletions
//   3. delta          – pull the remote change set, then fetch each item body
//
// The server-side item-id format is non-obvious:
//
//   - Sync items (Note / Folder / Tag / NoteTag / Resource-metadata) are stored
//     under a "name" that is `<joplin-id>.<ext>`, where `<ext>` is always `md`
//     for the five sync item types (see BaseItem.systemPath in joplin/lib/
//     models/BaseItem.ts, default extension 'md'). Resources additionally have
//     a blob path under `.resource/<id>`.
//   - The URL space is `api/items/root:/<name>:` — `pathToName` then strips
//     `root:/` and the trailing `:` so it can look the item up by `name`.
//   - `GET /api/items/:id` returns only the metadata JSON. The serialized item
//     body lives at `GET /api/items/:id/content`. PUT is symmetric, and DELETE
//     is just `DELETE /api/items/:id` (no body).
//   - The delta endpoint is `api/items/root:/:/delta` — inner path is empty,
//     trailing colon is required. delta's response is a list of *change*
//     records (id, item_id, item_name, item_type, type: ChangeType, …), not a
//     list of full item bodies. We must fetch each item body separately.
//
// ArkTS notes: object literals need a declared type and cannot use computed or
// quoted keys, and destructuring declarations are rejected — hence the classes
// and the explicit index access below.
import {
  JoplinApi, HeaderMap, QueryMap, DELTA_PATH,
  itemContentPath, itemMetadataPath,
} from './JoplinApi';
import {
  DeserializedItem, PropRecord, recordToFolder, recordToNote, recordToTag,
  serializeFolder, serializeNote, serializeNoteTag, serializeTag, unserializeItem,
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

// Joplin Server returns one of these per affected item per delta call. The
// server keeps two separate enums:
//
//   item_type — the Joplin client ModelType (Note=1, Folder=2, Resource=4,
//     Tag=5, NoteTag=7). The server stores this in items.jop_type and on
//     changes.item_type.
//   type — ChangeType (1=Create, 2=Update, 3=Delete). This is what tells us
//     whether to fetch the body or remove the local copy.
//
// item_name is the actual file-name under which the server stores the item
// body — it carries the `<id>.md` (or `.resource` for resources) suffix.
interface DeltaItem {
  id: string;
  item_id?: string;
  item_name?: string;
  item_type?: number;
  type?: number;
  type_?: number;
  isDeleted?: boolean;
  updated_time?: number;
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

// Joplin server stores every sync item (Note / Folder / Tag / NoteTag) under
// the same `<id>.md` name pattern — see BaseItem.systemPath in upstream. Only
// Resource uses a different extension.
function extForType(itemType: number): string {
  if (itemType === ItemType.Resource) {
    return '.resource';
  }
  return '.md';
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

// PUT /content uploads must use application/octet-stream (not text/plain).
// The Joplin Server parses the body with `formidable`, which only recognises
// multipart/form-data, application/x-www-form-urlencoded, and
// application/octet-stream — text/plain triggers "no parser found".
// The raw serialized Joplin item text is sent as the body; formidable treats
// it as a file upload and the server reads it back from the temp file.
function uploadHeaders(): HeaderMap {
  const h: HeaderMap = {};
  h['Content-Type'] = 'application/octet-stream';
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

      // Post-sync diagnostic: verify local DB state matches expectations.
      const folderRow: Row | null = await queryOne('SELECT COUNT(*) AS c FROM folders', []);
      const noteRow: Row | null = await queryOne('SELECT COUNT(*) AS c FROM notes', []);
      const folderCount: number = folderRow === null ? 0 : Number(folderRow['c'] ?? 0);
      const noteCount: number = noteRow === null ? 0 : Number(noteRow['c'] ?? 0);
      console.info(`[sync] done: pushed=${result.pushed} pulled=${result.pulled} deleted=${result.deleted}, local: ${folderCount} folder(s), ${noteCount} note(s)`);

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
    console.info(`[sync] pushLocal: ${rows.length} item(s) pending upload`);
    let pushed: number = 0;
    for (const r of rows) {
      const sid: number = Number(r['sid'] ?? 0);
      const itemType: number = Number(r['item_type'] ?? 0);
      const itemId: string = String(r['item_id'] ?? '');
      if (itemType === 0 || itemId === '') {
        continue;
      }
      try {
        console.info(`[sync] pushLocal: uploading type=${itemType} id=${itemId}`);
        await this.uploadItem(itemType, itemId);
        await exec('UPDATE sync_items SET sync_time = ? WHERE id = ?',
          [Number(r['local_updated_time'] ?? 0), sid]);
        pushed += 1;
      } catch (e) {
        // A single failed item should not abort the whole round.
        console.warn(`[sync] pushLocal: FAILED type=${itemType} id=${itemId}: ${(e as Error).message}`);
        this.report(new SyncProgress(SyncPhase.UpdateRemote,
          `Push failed for ${itemId}: ${(e as Error).message}`, pushed));
      }
    }
    console.info(`[sync] pushLocal: done, ${pushed}/${rows.length} uploaded`);
    return pushed;
  }

  private async uploadItem(itemType: number, itemId: string): Promise<void> {
    const itemName: string = `${itemId}${extForType(itemType)}`;
    const path: string = itemContentPath(itemName);

    if (itemType === ItemType.Note) {
      const note: Note | null = await noteRepo.get(itemId);
      if (note === null) {
        return;
      }
      await this.api.exec('PUT', path, null, serializeNote(note), uploadHeaders());
      return;
    }

    if (itemType === ItemType.Folder) {
      const folder: Folder | null = await folderRepo.get(itemId);
      if (folder === null) {
        return;
      }
      await this.api.exec('PUT', path, null, serializeFolder(folder), uploadHeaders());
      return;
    }

    if (itemType === ItemType.Tag) {
      const tag: Tag | null = await tagRepo.get(itemId);
      if (tag === null) {
        return;
      }
      await this.api.exec('PUT', path, null, serializeTag(tag), uploadHeaders());
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
      await this.api.exec('PUT', path, null, serializeNoteTag(noteTag), uploadHeaders());
      return;
    }

    // Resource upload needs an additional blob PUT — left as a no-op stub.
  }

  private async pushDeletions(): Promise<number> {
    const rows: Row[] = await queryAll('SELECT id, item_type, item_id FROM deleted_items');
    console.info(`[sync] pushDeletions: ${rows.length} item(s) pending delete`);
    if (rows.length === 0) {
      return 0;
    }
    const paths: string[] = [];
    for (const r of rows) {
      const itemType: number = Number(r['item_type'] ?? 0);
      const itemId: string = String(r['item_id'] ?? '');
      if (itemType === 0 || itemId === '') {
        continue;
      }
      paths.push(itemMetadataPath(`${itemId}${extForType(itemType)}`));
    }
    if (paths.length === 0) {
      await exec('DELETE FROM deleted_items');
      return 0;
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
    return paths.length;
  }

  private async pullDelta(): Promise<number> {
    let cursor: string = (await settingsRepo.get('sync.cursor')) ?? '';
    console.info(`[sync] pullDelta: starting with cursor='${cursor === '' ? '(empty)' : cursor.slice(0, 20) + '...'}'`);
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
      console.info(`[sync] pullDelta: batch ${safety}, ${items.length} item(s), has_more=${parsed.has_more}`);
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

      // Diagnostic: count applied items by type so we can verify folders are pulled.
      if (items.length > 0) {
        const typeCounts: Record<string, number> = {};
        for (const remote of items) {
          const t: string = String(remote.item_type ?? remote.type_ ?? '?');
          typeCounts[t] = (typeCounts[t] ?? 0) + 1;
        }
        const parts: string[] = [];
        const keys: string[] = Object.keys(typeCounts);
        for (const k of keys) {
          const label: string = k === '1' ? 'Note' : k === '2' ? 'Folder' : k === '4' ? 'Resource' : k === '5' ? 'Tag' : k === '7' ? 'NoteTag' : k;
          parts.push(`${label}:${typeCounts[k]}`);
        }
        console.info(`[sync] delta batch: ${items.length} item(s) — ${parts.join(', ')}`);
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

  // ChangeType: 1=Create, 2=Update, 3=Delete. Older servers may use the
  // optional `isDeleted` flag as an alias, fall back to it for safety.
  private isRemoteDelete(remote: DeltaItem): boolean {
    if (remote.type === 3) {
      return true;
    }
    if (remote.isDeleted === true) {
      return true;
    }
    return false;
  }

  private remoteItemType(remote: DeltaItem): number {
    return Number(remote.item_type ?? remote.type_ ?? 0);
  }

  private remoteItemId(remote: DeltaItem): string {
    return String(remote.item_id ?? '');
  }

  private async applyRemote(remote: DeltaItem): Promise<void> {
    const remoteType: number = this.remoteItemType(remote);
    const remoteId: string = this.remoteItemId(remote);
    const remoteName: string = String(remote.item_name ?? '');
    const isDel: boolean = this.isRemoteDelete(remote);
    console.info(`[sync] applyRemote: type=${remoteType} id=${remoteId} name=${remoteName} changeType=${remote.type ?? '?'} isDelete=${isDel}`);

    if (isDel) {
      if (remoteType > 0 && remoteId !== '') {
        await this.deleteLocalByType(remoteType, remoteId);
        console.info(`[sync] applyRemote: deleted local type=${remoteType} id=${remoteId}`);
      }
      return;
    }

    if (remoteName === '') {
      console.warn(`[sync] applyRemote: skipping — no item_name`);
      return;
    }

    // Resource items (type=4) are stored as raw binary blobs at the same name;
    // the text `/content` endpoint returns the markdown payload only when
    // `jop_type > 0`. We don't yet round-trip resource blobs end-to-end, so
    // bail on Resources instead of trying to unserialise them.
    if (remoteType === ItemType.Resource) {
      console.info(`[sync] applyRemote: skipping Resource ${remoteId}`);
      return;
    }

    const path: string = itemContentPath(remoteName);
    // Per-item content fetch: retry transient transport failures (TLS reset,
    // proxy timeout, …) up to 3 attempts with linear backoff. pullDelta's
    // outer try/catch already isolates a hard failure for one item so the
    // rest of the batch still gets applied.
    const res = await this.api.exec('GET', path, null, null, null, 2, 600);
    console.info(`[sync] GET ${path} → ${res.status}, body ${res.body.length}B, head: ${res.body.slice(0, 120)}`);
    const item: DeserializedItem | null = unserializeItem(res.body, remoteType);
    if (item === null) {
      // Body did not look like a Joplin item (might be binary or HTML).
      // Continue with the rest of the delta — don't fail the whole batch.
      console.warn(`[sync] skipping ${remoteName}: body had no recognisable Joplin props`);
      return;
    }
    const raw: PropRecord = item.raw;
    const effectiveType: number = item.typeId > 0 ? item.typeId : remoteType;

    if (effectiveType === ItemType.Note) {
      await noteRepo.upsert(recordToNote(raw), false);
      return;
    }
    if (effectiveType === ItemType.Folder) {
      await folderRepo.upsert(recordToFolder(raw), false);
      return;
    }
    if (effectiveType === ItemType.Tag) {
      await tagRepo.upsert(recordToTag(raw), false);
      return;
    }
    if (effectiveType === ItemType.NoteTag) {
      const noteId: string = String(raw['note_id'] ?? '');
      const tagId: string = String(raw['tag_id'] ?? '');
      if (noteId !== '' && tagId !== '') {
        await noteTagRepo.add(noteId, tagId, false);
      }
      return;
    }
    // Resource / unknown type — silently skipped.
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
