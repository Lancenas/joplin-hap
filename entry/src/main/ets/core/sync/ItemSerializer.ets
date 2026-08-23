// Joplin item (de)serialization — implements BaseItem.serialize / unserialize
// from laurent22/joplin. The "remote" representation of a note is:
//
//   <title>\n
//   \n
//   <body>\n
//   \n
//   <key>: <value>\n
//   <key>: <value>\n
//
// where the trailing property block is separated from the body by a blank line.
//
// ArkTS forbids casting a class/interface value to an indexed type
// (`item as Record<string, ...>`), so each entity is projected into a Record
// through an explicit, hand-written mapping instead of a generic field walk.
import { Folder, Note, NoteTag, Resource, Tag } from '../models/Entities';
import { ItemType } from '../utils/Constants';
import { fromJoplinTime, toJoplinTime } from '../utils/IdGen';

export type PropRecord = Record<string, string | number | null>;

const TIME_KEYS: string[] = [
  'created_time', 'updated_time', 'sync_time',
  'user_created_time', 'user_updated_time',
];

function isTimeKey(key: string): boolean {
  return TIME_KEYS.indexOf(key) >= 0;
}

function formatValue(key: string, value: string | number | null): string {
  if (isTimeKey(key)) {
    if (value === null || value === '' || value === 0) {
      return '';
    }
    const ms: number = typeof value === 'string' ? Number(value) : value;
    if (!ms || Number.isNaN(ms)) {
      return '';
    }
    return toJoplinTime(ms);
  }
  if (value === null) {
    return '';
  }
  return String(value);
}

// Joplin escapes embedded newlines so every property stays on a single line.
function escapeValue(s: string): string {
  if (s.indexOf('\n') < 0 && s.indexOf('\r') < 0 && s.indexOf('\\') < 0) {
    return s;
  }
  return s
    .replace(/\\/g, '\\\\')
    .replace(/\n/g, '\\n')
    .replace(/\r/g, '\\r');
}

function unescapeValue(s: string): string {
  return s
    .replace(/\\n/g, '\n')
    .replace(/\\r/g, '\r')
    .replace(/\\\\/g, '\\');
}

function buildSerialized(title: string, body: string, props: PropRecord, keys: string[], typeId: number): string {
  const lines: string[] = [];
  for (const key of keys) {
    const raw: string | number | null = props[key] ?? null;
    lines.push(`${key}: ${escapeValue(formatValue(key, raw))}`);
  }
  lines.push(`type_: ${typeId}`);
  return `${title}\n\n${body}\n\n${lines.join('\n')}`;
}

const NOTE_KEYS: string[] = [
  'id', 'parent_id', 'is_conflict', 'latitude', 'longitude', 'altitude',
  'author', 'source_url', 'is_todo', 'todo_due', 'todo_completed',
  'source', 'source_application', 'application_data', 'order', 'deleted_time',
  'created_time', 'updated_time', 'user_created_time', 'user_updated_time',
  'encryption_cipher_text', 'encryption_applied', 'markup_language',
];

const FOLDER_KEYS: string[] = [
  'id', 'created_time', 'updated_time', 'user_created_time', 'user_updated_time',
  'encryption_cipher_text', 'encryption_applied', 'parent_id',
];

const TAG_KEYS: string[] = [
  'id', 'created_time', 'updated_time', 'user_created_time', 'user_updated_time',
  'encryption_cipher_text', 'encryption_applied', 'parent_id',
];

const NOTE_TAG_KEYS: string[] = [
  'id', 'note_id', 'tag_id',
  'created_time', 'updated_time', 'user_created_time', 'user_updated_time',
  'encryption_cipher_text', 'encryption_applied',
];

const RESOURCE_KEYS: string[] = [
  'id', 'mime', 'filename', 'created_time', 'updated_time',
  'user_created_time', 'user_updated_time',
  'file_extension', 'encryption_cipher_text', 'encryption_applied',
  'encryption_blob_encrypted', 'size',
];

export function serializeNote(note: Note): string {
  const props: PropRecord = {};
  props['id'] = note.id;
  props['parent_id'] = note.parentId;
  props['is_conflict'] = note.isConflict;
  props['latitude'] = note.latitude.toFixed(8);
  props['longitude'] = note.longitude.toFixed(8);
  props['altitude'] = note.altitude.toFixed(4);
  props['author'] = note.author;
  props['source_url'] = note.sourceUrl;
  props['is_todo'] = note.isTodo;
  props['todo_due'] = note.todoDue;
  props['todo_completed'] = note.todoCompleted;
  props['source'] = note.source;
  props['source_application'] = note.sourceApplication;
  props['application_data'] = note.applicationData;
  props['order'] = note.order;
  props['deleted_time'] = note.deletedTime;
  props['created_time'] = note.createdTime;
  props['updated_time'] = note.updatedTime;
  props['user_created_time'] = note.userCreatedTime;
  props['user_updated_time'] = note.userUpdatedTime;
  props['encryption_cipher_text'] = '';
  props['encryption_applied'] = 0;
  props['markup_language'] = 1;
  return buildSerialized(note.title, note.body, props, NOTE_KEYS, ItemType.Note);
}

export function serializeFolder(folder: Folder): string {
  const props: PropRecord = {};
  props['id'] = folder.id;
  props['created_time'] = folder.createdTime;
  props['updated_time'] = folder.updatedTime;
  props['user_created_time'] = folder.userCreatedTime;
  props['user_updated_time'] = folder.userUpdatedTime;
  props['encryption_cipher_text'] = '';
  props['encryption_applied'] = 0;
  props['parent_id'] = folder.parentId;
  return buildSerialized(folder.title, '', props, FOLDER_KEYS, ItemType.Folder);
}

export function serializeTag(tag: Tag): string {
  const props: PropRecord = {};
  props['id'] = tag.id;
  props['created_time'] = tag.createdTime;
  props['updated_time'] = tag.updatedTime;
  props['user_created_time'] = tag.userCreatedTime;
  props['user_updated_time'] = tag.userUpdatedTime;
  props['encryption_cipher_text'] = '';
  props['encryption_applied'] = 0;
  props['parent_id'] = tag.parentId;
  return buildSerialized(tag.title, '', props, TAG_KEYS, ItemType.Tag);
}

export function serializeNoteTag(noteTag: NoteTag): string {
  const props: PropRecord = {};
  props['id'] = noteTag.id;
  props['note_id'] = noteTag.noteId;
  props['tag_id'] = noteTag.tagId;
  props['created_time'] = noteTag.createdTime;
  props['updated_time'] = noteTag.updatedTime;
  props['user_created_time'] = noteTag.userCreatedTime;
  props['user_updated_time'] = noteTag.userUpdatedTime;
  props['encryption_cipher_text'] = '';
  props['encryption_applied'] = 0;
  return buildSerialized('', '', props, NOTE_TAG_KEYS, ItemType.NoteTag);
}

export function serializeResource(resource: Resource): string {
  const props: PropRecord = {};
  props['id'] = resource.id;
  props['mime'] = resource.mime;
  props['filename'] = resource.filename;
  props['created_time'] = resource.createdTime;
  props['updated_time'] = resource.updatedTime;
  props['user_created_time'] = resource.userCreatedTime;
  props['user_updated_time'] = resource.userUpdatedTime;
  props['file_extension'] = resource.fileExtension;
  props['encryption_cipher_text'] = '';
  props['encryption_applied'] = 0;
  props['encryption_blob_encrypted'] = 0;
  props['size'] = resource.size;
  return buildSerialized(resource.title, '', props, RESOURCE_KEYS, ItemType.Resource);
}

export interface DeserializedItem {
  typeId: number;
  raw: PropRecord;
}

// Reverse of buildSerialized: scan the tail of the payload for `key: value`
// lines, stop at the first blank line, then treat everything above it as the
// title (first line) plus body (remainder).
//
// Returns null when the body contains no recognisable Joplin props at all
// (binary blob, HTML error page, empty payload, …) instead of throwing. The
// caller can then fall back to the `item_type` field supplied by the delta.
//
// `fallbackTypeId` lets the caller say "the server told me this is a Note/Folder/
// …, so trust that when the body's own `type_` line is absent or unreadable".
export function unserializeItem(content: string, fallbackTypeId: number = 0): DeserializedItem | null {
  const trimmed: string = content == null ? '' : content;
  if (trimmed.length < 4) {
    return null;
  }
  const lines: string[] = trimmed.split('\n');
  const props: Record<string, string> = {};
  let headEnd: number = lines.length;
  let foundTypeLine: boolean = false;
  for (let i = lines.length - 1; i >= 0; i--) {
    const line: string = lines[i].trim();
    if (line === '') {
      headEnd = i;
      break;
    }
    const sep: number = line.indexOf(':');
    if (sep <= 0) {
      // No colon (or colon at position 0): not a valid prop, end the scan.
      headEnd = i + 1;
      break;
    }
    const key: string = line.substring(0, sep).trim();
    if (key === '') {
      headEnd = i + 1;
      break;
    }
    const val: string = line.substring(sep + 1).trim();
    props[key] = unescapeValue(val);
    if (key === 'type_') {
      foundTypeLine = true;
    }
  }

  // Bail out cleanly when the prop block is empty or has no Joplin-looking
  // fields at all (every line was something else).
  const propKeys: string[] = Object.keys(props);
  if (propKeys.length === 0) {
    return null;
  }

  let typeId: number = fallbackTypeId;
  if (foundTypeLine) {
    const parsed: number = Number(props['type_']);
    if (parsed > 0) {
      typeId = parsed;
    }
  } else {
    // No `type_:` line at all in the body. Without a fallback we have no
    // idea what kind of item this is, so return null.
    if (typeId <= 0) {
      return null;
    }
  }

  const head: string[] = lines.slice(0, headEnd);
  let title: string = '';
  let bodyStart: number = 0;
  for (let i = 0; i < head.length; i++) {
    if (head[i].trim() !== '') {
      title = head[i];
      bodyStart = i + 1;
      break;
    }
  }
  let body: string = '';
  if (typeId === ItemType.Note && bodyStart < head.length) {
    body = head.slice(bodyStart).join('\n').replace(/^\n+/, '').replace(/\n+$/, '');
  }

  const out: PropRecord = {};
  for (const k of propKeys) {
    const v: string = props[k];
    if (k === 'type_') {
      out[k] = typeId;
      continue;
    }
    if (isTimeKey(k)) {
      out[k] = fromJoplinTime(v);
    } else {
      out[k] = v;
    }
  }
  out['title'] = title;
  out['body'] = body;
  if (!foundTypeLine) {
    out['type_'] = typeId;
  }
  return { typeId: typeId, raw: out };
}

// ---- Record -> entity projections used when applying remote changes ----

function str(raw: PropRecord, key: string): string {
  const v: string | number | null = raw[key] ?? null;
  return v === null ? '' : String(v);
}

function num(raw: PropRecord, key: string): number {
  const v: string | number | null = raw[key] ?? null;
  if (v === null || v === '') {
    return 0;
  }
  const n: number = typeof v === 'number' ? v : Number(v);
  return Number.isNaN(n) ? 0 : n;
}

export function recordToNote(raw: PropRecord): Note {
  const note: Note = {
    type_: ItemType.Note,
    id: str(raw, 'id'),
    parentId: str(raw, 'parent_id'),
    title: str(raw, 'title'),
    body: str(raw, 'body'),
    createdTime: num(raw, 'created_time'),
    updatedTime: num(raw, 'updated_time'),
    isConflict: num(raw, 'is_conflict'),
    latitude: num(raw, 'latitude'),
    longitude: num(raw, 'longitude'),
    altitude: num(raw, 'altitude'),
    author: str(raw, 'author'),
    sourceUrl: str(raw, 'source_url'),
    isTodo: num(raw, 'is_todo'),
    todoDue: num(raw, 'todo_due'),
    todoCompleted: num(raw, 'todo_completed'),
    source: str(raw, 'source'),
    sourceApplication: str(raw, 'source_application'),
    applicationData: str(raw, 'application_data'),
    order: num(raw, 'order'),
    deletedTime: num(raw, 'deleted_time'),
    userCreatedTime: num(raw, 'user_created_time'),
    userUpdatedTime: num(raw, 'user_updated_time'),
  };
  return note;
}

export function recordToFolder(raw: PropRecord): Folder {
  const folder: Folder = {
    type_: ItemType.Folder,
    id: str(raw, 'id'),
    title: str(raw, 'title'),
    parentId: str(raw, 'parent_id'),
    createdTime: num(raw, 'created_time'),
    updatedTime: num(raw, 'updated_time'),
    userCreatedTime: num(raw, 'user_created_time'),
    userUpdatedTime: num(raw, 'user_updated_time'),
  };
  return folder;
}

export function recordToTag(raw: PropRecord): Tag {
  const tag: Tag = {
    type_: ItemType.Tag,
    id: str(raw, 'id'),
    title: str(raw, 'title'),
    parentId: str(raw, 'parent_id'),
    createdTime: num(raw, 'created_time'),
    updatedTime: num(raw, 'updated_time'),
    userCreatedTime: num(raw, 'user_created_time'),
    userUpdatedTime: num(raw, 'user_updated_time'),
  };
  return tag;
}

export function recordToNoteTag(raw: PropRecord): NoteTag {
  const noteTag: NoteTag = {
    type_: ItemType.NoteTag,
    id: str(raw, 'id'),
    noteId: str(raw, 'note_id'),
    tagId: str(raw, 'tag_id'),
    createdTime: num(raw, 'created_time'),
    updatedTime: num(raw, 'updated_time'),
    userCreatedTime: num(raw, 'user_created_time'),
    userUpdatedTime: num(raw, 'user_updated_time'),
  };
  return noteTag;
}

export function recordToResource(raw: PropRecord): Resource {
  const resource: Resource = {
    type_: ItemType.Resource,
    id: str(raw, 'id'),
    title: str(raw, 'title'),
    mime: str(raw, 'mime'),
    filename: str(raw, 'filename'),
    fileExtension: str(raw, 'file_extension'),
    size: num(raw, 'size'),
    createdTime: num(raw, 'created_time'),
    updatedTime: num(raw, 'updated_time'),
    userCreatedTime: num(raw, 'user_created_time'),
    userUpdatedTime: num(raw, 'user_updated_time'),
  };
  return resource;
}
