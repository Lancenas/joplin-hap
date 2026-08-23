// Repository layer — typed CRUD on top of the RdbStore. Mirrors the surface of
// laurent22/joplin's BaseItem so that the synchroniser can call into it the
// same way the official clients do.
//
// Every mutating method takes a `track` flag: when true (the default, i.e. a
// local edit) the change is queued in sync_items / deleted_items so the next
// sync round uploads it. The synchroniser passes false while applying remote
// changes, otherwise every pull would immediately schedule a redundant push.
import { Folder, Note, NoteTag, Resource, Tag } from '../models/Entities';
import { ItemType, SyncTarget } from '../utils/Constants';
import { nowMs } from '../utils/IdGen';
import { Row, exec, queryAll, queryOne } from '../db/Query';

function rowToNote(row: Row): Note {
  const note: Note = {
    type_: ItemType.Note,
    id: String(row['id'] ?? ''),
    parentId: String(row['parent_id'] ?? ''),
    title: String(row['title'] ?? ''),
    body: String(row['body'] ?? ''),
    createdTime: Number(row['created_time'] ?? 0),
    updatedTime: Number(row['updated_time'] ?? 0),
    isConflict: Number(row['is_conflict'] ?? 0),
    latitude: Number(row['latitude'] ?? 0),
    longitude: Number(row['longitude'] ?? 0),
    altitude: Number(row['altitude'] ?? 0),
    author: String(row['author'] ?? ''),
    sourceUrl: String(row['source_url'] ?? ''),
    isTodo: Number(row['is_todo'] ?? 0),
    todoDue: Number(row['todo_due'] ?? 0),
    todoCompleted: Number(row['todo_completed'] ?? 0),
    source: String(row['source'] ?? ''),
    sourceApplication: String(row['source_application'] ?? ''),
    applicationData: String(row['application_data'] ?? ''),
    order: Number(row['order'] ?? 0),
    userCreatedTime: Number(row['user_created_time'] ?? 0),
    userUpdatedTime: Number(row['user_updated_time'] ?? 0),
  };
  return note;
}

function rowToFolder(row: Row): Folder {
  const folder: Folder = {
    type_: ItemType.Folder,
    id: String(row['id'] ?? ''),
    title: String(row['title'] ?? ''),
    parentId: String(row['parent_id'] ?? ''),
    createdTime: Number(row['created_time'] ?? 0),
    updatedTime: Number(row['updated_time'] ?? 0),
    userCreatedTime: Number(row['user_created_time'] ?? 0),
    userUpdatedTime: Number(row['user_updated_time'] ?? 0),
  };
  return folder;
}

function rowToTag(row: Row): Tag {
  const tag: Tag = {
    type_: ItemType.Tag,
    id: String(row['id'] ?? ''),
    title: String(row['title'] ?? ''),
    parentId: String(row['parent_id'] ?? ''),
    createdTime: Number(row['created_time'] ?? 0),
    updatedTime: Number(row['updated_time'] ?? 0),
    userCreatedTime: Number(row['user_created_time'] ?? 0),
    userUpdatedTime: Number(row['user_updated_time'] ?? 0),
  };
  return tag;
}

function rowToResource(row: Row): Resource {
  const resource: Resource = {
    type_: ItemType.Resource,
    id: String(row['id'] ?? ''),
    title: String(row['title'] ?? ''),
    mime: String(row['mime'] ?? ''),
    filename: String(row['filename'] ?? ''),
    fileExtension: String(row['file_extension'] ?? ''),
    size: Number(row['size'] ?? 0),
    createdTime: Number(row['created_time'] ?? 0),
    updatedTime: Number(row['updated_time'] ?? 0),
    userCreatedTime: Number(row['user_created_time'] ?? 0),
    userUpdatedTime: Number(row['user_updated_time'] ?? 0),
  };
  return resource;
}

function mapNotes(rows: Row[]): Note[] {
  const out: Note[] = [];
  for (const r of rows) {
    out.push(rowToNote(r));
  }
  return out;
}

function mapFolders(rows: Row[]): Folder[] {
  const out: Folder[] = [];
  for (const r of rows) {
    out.push(rowToFolder(r));
  }
  return out;
}

function mapTags(rows: Row[]): Tag[] {
  const out: Tag[] = [];
  for (const r of rows) {
    out.push(rowToTag(r));
  }
  return out;
}

export class NoteRepository {
  async listByFolder(folderId: string, limit: number = 200, offset: number = 0): Promise<Note[]> {
    const rows: Row[] = await queryAll(
      'SELECT * FROM notes WHERE parent_id = ? AND is_conflict = 0 ORDER BY updated_time DESC LIMIT ? OFFSET ?',
      [folderId, limit, offset]
    );
    return mapNotes(rows);
  }

  async listRecent(limit: number = 200): Promise<Note[]> {
    const rows: Row[] = await queryAll(
      'SELECT * FROM notes WHERE is_conflict = 0 ORDER BY updated_time DESC LIMIT ?',
      [limit]
    );
    return mapNotes(rows);
  }

  async get(id: string): Promise<Note | null> {
    const row: Row | null = await queryOne('SELECT * FROM notes WHERE id = ?', [id]);
    return row === null ? null : rowToNote(row);
  }

  async search(q: string, limit: number = 200): Promise<Note[]> {
    const term: string = q.trim();
    if (term === '') {
      return [];
    }
    const like: string = `%${term}%`;
    const rows: Row[] = await queryAll(
      'SELECT * FROM notes WHERE title LIKE ? OR body LIKE ? ORDER BY updated_time DESC LIMIT ?',
      [like, like, limit]
    );
    return mapNotes(rows);
  }

  async upsert(note: Note, track: boolean = true): Promise<Note> {
    const now: number = nowMs();
    if (!note.createdTime) {
      note.createdTime = now;
    }
    if (!note.userCreatedTime) {
      note.userCreatedTime = now;
    }
    if (track) {
      note.updatedTime = now;
      note.userUpdatedTime = now;
    } else {
      if (!note.updatedTime) {
        note.updatedTime = now;
      }
      if (!note.userUpdatedTime) {
        note.userUpdatedTime = note.updatedTime;
      }
    }
    await exec(
      `INSERT OR REPLACE INTO notes (
         id, parent_id, title, body, created_time, updated_time,
         is_conflict, latitude, longitude, altitude, author, source_url,
         is_todo, todo_due, todo_completed, source, source_application,
         application_data, \`order\`, user_created_time, user_updated_time
       ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)`,
      [
        note.id, note.parentId, note.title, note.body,
        note.createdTime, note.updatedTime,
        note.isConflict, note.latitude, note.longitude, note.altitude,
        note.author, note.sourceUrl,
        note.isTodo, note.todoDue, note.todoCompleted,
        note.source, note.sourceApplication,
        note.applicationData, note.order,
        note.userCreatedTime, note.userUpdatedTime
      ]
    );
    if (track) {
      await markItemForSync(ItemType.Note, note.id);
    }
    return note;
  }

  async delete(id: string, track: boolean = true): Promise<void> {
    await exec('DELETE FROM notes WHERE id = ?', [id]);
    await exec('DELETE FROM note_tags WHERE note_id = ?', [id]);
    if (track) {
      await recordDeletion(ItemType.Note, id);
    }
  }

  async countByFolder(folderId: string): Promise<number> {
    const row: Row | null = await queryOne('SELECT COUNT(*) AS c FROM notes WHERE parent_id = ?', [folderId]);
    return row === null ? 0 : Number(row['c'] ?? 0);
  }

  async countAll(): Promise<number> {
    const row: Row | null = await queryOne('SELECT COUNT(*) AS c FROM notes');
    return row === null ? 0 : Number(row['c'] ?? 0);
  }
}

export class FolderRepository {
  async list(): Promise<Folder[]> {
    const rows: Row[] = await queryAll('SELECT * FROM folders ORDER BY title COLLATE NOCASE ASC');
    return mapFolders(rows);
  }

  async get(id: string): Promise<Folder | null> {
    const row: Row | null = await queryOne('SELECT * FROM folders WHERE id = ?', [id]);
    return row === null ? null : rowToFolder(row);
  }

  async upsert(folder: Folder, track: boolean = true): Promise<Folder> {
    const now: number = nowMs();
    if (!folder.createdTime) {
      folder.createdTime = now;
    }
    if (!folder.userCreatedTime) {
      folder.userCreatedTime = now;
    }
    if (track) {
      folder.updatedTime = now;
      folder.userUpdatedTime = now;
    } else if (!folder.updatedTime) {
      folder.updatedTime = now;
      folder.userUpdatedTime = now;
    }
    await exec(
      `INSERT OR REPLACE INTO folders (id, title, parent_id, created_time, updated_time, user_created_time, user_updated_time)
       VALUES (?,?,?,?,?,?,?)`,
      [folder.id, folder.title, folder.parentId, folder.createdTime, folder.updatedTime,
       folder.userCreatedTime, folder.userUpdatedTime]
    );
    if (track) {
      await markItemForSync(ItemType.Folder, folder.id);
    }
    return folder;
  }

  // 删除笔记本时，连同其中所有笔记一起删除（含 note_tags 和 sync 删除标记），
  // 与桌面端 Joplin 的删除行为一致。
  async delete(id: string, track: boolean = true): Promise<void> {
    // 1. 找出该笔记本下的所有笔记
    const noteRows: Row[] = await queryAll('SELECT id FROM notes WHERE parent_id = ?', [id]);
    // 2. 批量删除笔记（SQL 层面一次删完）
    await exec('DELETE FROM notes WHERE parent_id = ?', [id]);
    // 3. 逐条清理 note_tags 并记录 sync 删除标记
    for (const row of noteRows) {
      const noteId: string = String(row['id'] ?? '');
      if (noteId === '') {
        continue;
      }
      await exec('DELETE FROM note_tags WHERE note_id = ?', [noteId]);
      if (track) {
        await recordDeletion(ItemType.Note, noteId);
      }
    }
    // 4. 删除笔记本本身
    await exec('DELETE FROM folders WHERE id = ?', [id]);
    if (track) {
      await recordDeletion(ItemType.Folder, id);
    }
    console.info(`[joplin-hap] folderRepo.delete: folder ${id} + ${noteRows.length} note(s) deleted`);
  }
}

export class TagRepository {
  async list(): Promise<Tag[]> {
    const rows: Row[] = await queryAll('SELECT * FROM tags ORDER BY title COLLATE NOCASE ASC');
    return mapTags(rows);
  }

  async get(id: string): Promise<Tag | null> {
    const row: Row | null = await queryOne('SELECT * FROM tags WHERE id = ?', [id]);
    return row === null ? null : rowToTag(row);
  }

  async findByTitle(title: string): Promise<Tag | null> {
    const row: Row | null = await queryOne('SELECT * FROM tags WHERE title = ? COLLATE NOCASE', [title]);
    return row === null ? null : rowToTag(row);
  }

  async upsert(tag: Tag, track: boolean = true): Promise<Tag> {
    const now: number = nowMs();
    if (!tag.createdTime) {
      tag.createdTime = now;
    }
    if (!tag.userCreatedTime) {
      tag.userCreatedTime = now;
    }
    if (track) {
      tag.updatedTime = now;
      tag.userUpdatedTime = now;
    } else if (!tag.updatedTime) {
      tag.updatedTime = now;
      tag.userUpdatedTime = now;
    }
    await exec(
      `INSERT OR REPLACE INTO tags (id, title, parent_id, created_time, updated_time, user_created_time, user_updated_time)
       VALUES (?,?,?,?,?,?,?)`,
      [tag.id, tag.title, tag.parentId, tag.createdTime, tag.updatedTime,
       tag.userCreatedTime, tag.userUpdatedTime]
    );
    if (track) {
      await markItemForSync(ItemType.Tag, tag.id);
    }
    return tag;
  }

  async delete(id: string, track: boolean = true): Promise<void> {
    await exec('DELETE FROM tags WHERE id = ?', [id]);
    await exec('DELETE FROM note_tags WHERE tag_id = ?', [id]);
    if (track) {
      await recordDeletion(ItemType.Tag, id);
    }
  }

  async notesForTag(tagId: string): Promise<Note[]> {
    const rows: Row[] = await queryAll(
      `SELECT notes.* FROM notes
         JOIN note_tags ON note_tags.note_id = notes.id
        WHERE note_tags.tag_id = ?
        ORDER BY notes.updated_time DESC`,
      [tagId]
    );
    return mapNotes(rows);
  }

  async countNotes(tagId: string): Promise<number> {
    const row: Row | null = await queryOne('SELECT COUNT(*) AS c FROM note_tags WHERE tag_id = ?', [tagId]);
    return row === null ? 0 : Number(row['c'] ?? 0);
  }
}

export class NoteTagRepository {
  async add(noteId: string, tagId: string, track: boolean = true): Promise<void> {
    const now: number = nowMs();
    const id: string = `${noteId}_${tagId}`;
    await exec(
      `INSERT OR REPLACE INTO note_tags (id, note_id, tag_id, created_time, updated_time, user_created_time, user_updated_time)
       VALUES (?,?,?,?,?,?,?)`,
      [id, noteId, tagId, now, now, now, now]
    );
    if (track) {
      await markItemForSync(ItemType.NoteTag, id);
    }
  }

  async remove(noteId: string, tagId: string, track: boolean = true): Promise<void> {
    await exec('DELETE FROM note_tags WHERE note_id = ? AND tag_id = ?', [noteId, tagId]);
    if (track) {
      await recordDeletion(ItemType.NoteTag, `${noteId}_${tagId}`);
    }
  }

  async tagsForNote(noteId: string): Promise<Tag[]> {
    const rows: Row[] = await queryAll(
      `SELECT tags.* FROM tags
         JOIN note_tags ON note_tags.tag_id = tags.id
        WHERE note_tags.note_id = ?
        ORDER BY tags.title COLLATE NOCASE ASC`,
      [noteId]
    );
    return mapTags(rows);
  }
}

export class ResourceRepository {
  async get(id: string): Promise<Resource | null> {
    const row: Row | null = await queryOne('SELECT * FROM resources WHERE id = ?', [id]);
    return row === null ? null : rowToResource(row);
  }

  async upsert(resource: Resource, track: boolean = true): Promise<Resource> {
    const now: number = nowMs();
    if (!resource.createdTime) {
      resource.createdTime = now;
    }
    if (!resource.userCreatedTime) {
      resource.userCreatedTime = now;
    }
    if (track) {
      resource.updatedTime = now;
      resource.userUpdatedTime = now;
    } else if (!resource.updatedTime) {
      resource.updatedTime = now;
      resource.userUpdatedTime = now;
    }
    await exec(
      `INSERT OR REPLACE INTO resources (id, title, mime, filename, file_extension, size,
         created_time, updated_time, user_created_time, user_updated_time)
       VALUES (?,?,?,?,?,?,?,?,?,?)`,
      [resource.id, resource.title, resource.mime, resource.filename, resource.fileExtension,
       resource.size, resource.createdTime, resource.updatedTime,
       resource.userCreatedTime, resource.userUpdatedTime]
    );
    if (track) {
      await markItemForSync(ItemType.Resource, resource.id);
    }
    return resource;
  }
}

export class SettingsRepository {
  async get(key: string): Promise<string | null> {
    const row: Row | null = await queryOne('SELECT `value` FROM settings WHERE `key` = ?', [key]);
    if (row === null) {
      return null;
    }
    const v: string | number | null = row['value'] ?? null;
    return v === null ? null : String(v);
  }

  async getOr(key: string, fallback: string): Promise<string> {
    const v: string | null = await this.get(key);
    return v === null ? fallback : v;
  }

  async set(key: string, value: string, type: number = 1): Promise<void> {
    await exec('INSERT OR REPLACE INTO settings (`key`, `value`, `type`) VALUES (?,?,?)',
      [key, value, type]);
  }
}

// Joplin uses sync_time = 0 to mean "still needs to be uploaded"; once a sync
// round completes, the matching row's sync_time is bumped to updated_time.
async function markItemForSync(itemType: number, itemId: string): Promise<void> {
  await exec('DELETE FROM sync_items WHERE sync_target = ? AND item_type = ? AND item_id = ?',
    [SyncTarget.JoplinServer, itemType, itemId]);
  await exec('INSERT INTO sync_items (sync_target, sync_time, item_type, item_id) VALUES (?, 0, ?, ?)',
    [SyncTarget.JoplinServer, itemType, itemId]);
}

async function recordDeletion(itemType: number, itemId: string): Promise<void> {
  await exec('DELETE FROM sync_items WHERE item_type = ? AND item_id = ?', [itemType, itemId]);
  await exec('INSERT INTO deleted_items (item_type, item_id, deleted_time) VALUES (?, ?, ?)',
    [itemType, itemId, nowMs()]);
}

export const noteRepo: NoteRepository = new NoteRepository();
export const folderRepo: FolderRepository = new FolderRepository();
export const tagRepo: TagRepository = new TagRepository();
export const noteTagRepo: NoteTagRepository = new NoteTagRepository();
export const resourceRepo: ResourceRepository = new ResourceRepository();
export const settingsRepo: SettingsRepository = new SettingsRepository();
