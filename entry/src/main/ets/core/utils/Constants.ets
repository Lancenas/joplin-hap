// Joplin item type identifiers — kept in sync with laurent22/joplin BaseModel.
export const enum ItemType {
  Folder = 2,
  Note = 1,
  Tag = 5,
  NoteTag = 7,
  Resource = 4,
}

// Sync target identifiers used by Joplin's sync machinery.
export const enum SyncTarget {
  JoplinServer = 1,
  FileSystem = 2,
  OneDrive = 3,
  WebDAV = 4,
  Dropbox = 5,
}

// Marker stored in the settings table to identify rows the framework inserts.
export const enum SettingType {
  String = 1,
  Number = 2,
}

// Field types used by Joplin's table_fields bookkeeping table.
export const enum FieldType {
  Text = 1,
  Int = 2,
  Real = 3,
  Blob = 4,
}
