// Mirror of Joplin's BaseItem entities. We only carry the fields we actually
// read/write; encrypted blobs (`encryption_*`) and unused columns are skipped.
//
// Each entity carries a literal `type_` discriminator (matching BaseItem's
// type_ column) so the synchroniser can recover the concrete shape without
// resorting to the ArkTS-forbidden `in` operator.
//
// ArkTS notes:
//  * conditional types (`T extends X ? A : B`) are rejected (arkts-no-conditional-types)
//  * user-defined type predicates (`x is T`) are rejected (arkts-no-is)
// so the narrowing helpers below return plain booleans and callers use `as`.
import { ItemType } from '../utils/Constants';
import { newId, nowMs } from '../utils/IdGen';

export interface Folder {
  type_: ItemType;
  id: string;
  title: string;
  parentId: string;
  createdTime: number;
  updatedTime: number;
  userCreatedTime: number;
  userUpdatedTime: number;
}

export interface Note {
  type_: ItemType;
  id: string;
  parentId: string;
  title: string;
  body: string;
  createdTime: number;
  updatedTime: number;
  isConflict: number;
  latitude: number;
  longitude: number;
  altitude: number;
  author: string;
  sourceUrl: string;
  isTodo: number;
  todoDue: number;
  todoCompleted: number;
  source: string;
  sourceApplication: string;
  applicationData: string;
  order: number;
  userCreatedTime: number;
  userUpdatedTime: number;
}

export interface Tag {
  type_: ItemType;
  id: string;
  title: string;
  parentId: string;
  createdTime: number;
  updatedTime: number;
  userCreatedTime: number;
  userUpdatedTime: number;
}

export interface NoteTag {
  type_: ItemType;
  id: string;
  noteId: string;
  tagId: string;
  createdTime: number;
  updatedTime: number;
  userCreatedTime: number;
  userUpdatedTime: number;
}

export interface Resource {
  type_: ItemType;
  id: string;
  title: string;
  mime: string;
  filename: string;
  fileExtension: string;
  size: number;
  createdTime: number;
  updatedTime: number;
  userCreatedTime: number;
  userUpdatedTime: number;
}

// Bookkeeping rows — these are local-only and never uploaded as items.
export interface SyncItem {
  id: number;
  syncTarget: number;
  syncTime: number;
  itemType: number;
  itemId: string;
}

export interface DeletedItem {
  id: number;
  itemType: number;
  itemId: string;
  deletedTime: number;
}

export function isNote(typeId: number): boolean {
  return typeId === ItemType.Note;
}

export function isFolder(typeId: number): boolean {
  return typeId === ItemType.Folder;
}

export function isTag(typeId: number): boolean {
  return typeId === ItemType.Tag;
}

export function isNoteTag(typeId: number): boolean {
  return typeId === ItemType.NoteTag;
}

export function isResource(typeId: number): boolean {
  return typeId === ItemType.Resource;
}

// Factory helpers. ArkTS requires every object literal to match a declared
// type, and every declared field to be present — building entities through
// these functions keeps the call sites (pages, sync) free of boilerplate.
export function newNote(parentId: string, title: string = '', body: string = ''): Note {
  const now: number = nowMs();
  const note: Note = {
    type_: ItemType.Note,
    id: newId(),
    parentId: parentId,
    title: title,
    body: body,
    createdTime: now,
    updatedTime: now,
    isConflict: 0,
    latitude: 0,
    longitude: 0,
    altitude: 0,
    author: '',
    sourceUrl: '',
    isTodo: 0,
    todoDue: 0,
    todoCompleted: 0,
    source: 'joplin-hap',
    sourceApplication: 'cn.lancenas.joplinhap',
    applicationData: '',
    order: now,
    userCreatedTime: now,
    userUpdatedTime: now,
  };
  return note;
}

export function newFolder(title: string, parentId: string = ''): Folder {
  const now: number = nowMs();
  const folder: Folder = {
    type_: ItemType.Folder,
    id: newId(),
    title: title,
    parentId: parentId,
    createdTime: now,
    updatedTime: now,
    userCreatedTime: now,
    userUpdatedTime: now,
  };
  return folder;
}

export function newTag(title: string): Tag {
  const now: number = nowMs();
  const tag: Tag = {
    type_: ItemType.Tag,
    id: newId(),
    title: title,
    parentId: '',
    createdTime: now,
    updatedTime: now,
    userCreatedTime: now,
    userUpdatedTime: now,
  };
  return tag;
}

export function newResource(title: string, mime: string, fileExtension: string, size: number): Resource {
  const now: number = nowMs();
  const resource: Resource = {
    type_: ItemType.Resource,
    id: newId(),
    title: title,
    mime: mime,
    filename: '',
    fileExtension: fileExtension,
    size: size,
    createdTime: now,
    updatedTime: now,
    userCreatedTime: now,
    userUpdatedTime: now,
  };
  return resource;
}
