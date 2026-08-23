// Top-level observable store that backs the UI. We keep it small and explicit;
// the goal is to wire the pages to a single source of truth without pulling
// in a full state-management library.
import { Folder, Note, Tag } from '../core/models/Entities';
import { folderRepo, noteRepo, settingsRepo, tagRepo } from '../core/services/Repositories';

// Settings keys, mirroring the names Joplin uses for the same concepts.
export const KEY_SYNC_URL = 'sync.9.path';
export const KEY_SYNC_USER = 'sync.9.username';
export const KEY_SYNC_PASSWORD = 'sync.9.password';

@Observed
export class AppStore {
  folders: Folder[] = [];
  tags: Tag[] = [];
  notes: Note[] = [];
  selectedFolderId: string = '';
  selectedTagId: string = '';
  selectedNoteId: string = '';
  syncing: boolean = false;
  syncMessage: string = 'Ready';
  syncPushed: number = 0;
  syncPulled: number = 0;
  syncDeleted: number = 0;
  searchQuery: string = '';
  totalNotes: number = 0;

  async refreshAll(): Promise<void> {
    await this.refreshFolders();
    await this.refreshTags();
    await this.refreshNotes();
  }

  async refreshFolders(): Promise<void> {
    this.folders = await folderRepo.list();
  }

  async refreshTags(): Promise<void> {
    this.tags = await tagRepo.list();
  }

  async refreshNotes(): Promise<void> {
    if (this.selectedTagId !== '') {
      this.notes = await tagRepo.notesForTag(this.selectedTagId);
    } else if (this.selectedFolderId === '') {
      // No notebook selected — show everything, newest first.
      this.notes = await noteRepo.listRecent();
    } else {
      this.notes = await noteRepo.listByFolder(this.selectedFolderId);
    }
    this.totalNotes = await noteRepo.countAll();
  }

  async selectFolder(id: string): Promise<void> {
    this.selectedFolderId = id;
    this.selectedTagId = '';
    this.selectedNoteId = '';
    await this.refreshNotes();
  }

  async selectTag(id: string): Promise<void> {
    this.selectedTagId = id;
    this.selectedFolderId = '';
    this.selectedNoteId = '';
    await this.refreshNotes();
  }

  async search(q: string): Promise<void> {
    this.searchQuery = q;
    if (q.trim() === '') {
      await this.refreshNotes();
      return;
    }
    this.notes = await noteRepo.search(q);
  }

  folderTitle(id: string): string {
    for (const f of this.folders) {
      if (f.id === id) {
        return f.title === '' ? 'Untitled' : f.title;
      }
    }
    return '';
  }

  tagTitle(id: string): string {
    for (const t of this.tags) {
      if (t.id === id) {
        return t.title;
      }
    }
    return '';
  }

  currentTitle(): string {
    if (this.selectedTagId !== '') {
      const t: string = this.tagTitle(this.selectedTagId);
      return t === '' ? 'Tag' : `# ${t}`;
    }
    if (this.selectedFolderId === '') {
      return 'All notes';
    }
    const f: string = this.folderTitle(this.selectedFolderId);
    return f === '' ? 'Notebook' : f;
  }

  async loadSyncConfig(): Promise<void> {
    this.syncUrl = await settingsRepo.getOr(KEY_SYNC_URL, '');
    this.syncUser = await settingsRepo.getOr(KEY_SYNC_USER, '');
    this.syncPassword = await settingsRepo.getOr(KEY_SYNC_PASSWORD, '');
  }

  async saveSyncConfig(url: string, user: string, password: string): Promise<void> {
    this.syncUrl = url;
    this.syncUser = user;
    this.syncPassword = password;
    await settingsRepo.set(KEY_SYNC_URL, url);
    await settingsRepo.set(KEY_SYNC_USER, user);
    await settingsRepo.set(KEY_SYNC_PASSWORD, password);
  }

  syncUrl: string = '';
  syncUser: string = '';
  syncPassword: string = '';
}

export const appStore: AppStore = new AppStore();
