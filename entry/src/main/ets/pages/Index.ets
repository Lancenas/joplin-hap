import router from '@ohos.router';
import { I18n } from '../common/I18n';
import { AppStore, appStore, TRASH_VIEW_ID } from '../viewmodel/AppStore';
import { NoteRouteParams } from '../viewmodel/RouteParams';
import { Folder, Note, Tag, newFolder, newNote } from '../core/models/Entities';
import { folderRepo, noteRepo } from '../core/services/Repositories';

@Entry
@Component
struct Index {
  @State store: AppStore = appStore;
  @State showSidebar: boolean = true;
  @State newFolderTitle: string = '';
  @State revision: number = 0;
  // 统一的内容覆盖层：避免在同一组件上叠加多个 bindContentCover 导致互相串线
  @State showCover: boolean = false;
  @State coverKind: string = 'none'; // 'createFolder' | 'moveNote' | 'deleteFolder'
  // 「移动到笔记本」数据
  @State moveNoteId: string = '';
  @State moveNoteParentId: string = '';
  // 「删除笔记本」数据（默认保留笔记移到根目录，可勾选级联删除）
  @State deleteFolderId: string = '';
  @State deleteFolderName: string = '';
  @State deleteFolderNotesToo: boolean = false;

  aboutToAppear(): void {
    this.reload();
  }

  onPageShow(): void {
    // 从编辑器或设置页返回后刷新一次，把外部改动接进 UI。
    this.reload();
  }

  private reload(): void {
    this.store.refreshAll()
      .then(() => { this.revision += 1; })
      .catch((e: Error) => { console.error(`[joplin-hap] reload failed: ${e.message}`); });
  }

  // ── 删除笔记 ──
  private confirmDeleteNote(note: Note): void {
    const title: string = note.title === '' ? I18n.untitled : note.title;
    AlertDialog.show({
      title: I18n.delete,
      message: I18n.noteDeleteConfirm(title),
      primaryButton: { value: I18n.cancel, action: () => {} },
      secondaryButton: {
        value: I18n.delete,
        fontColor: '#B3261E',
        action: () => { this.deleteNote(note); }
      }
    });
  }

  private deleteNote(note: Note): void {
    noteRepo.delete(note.id)
      .then(() => {
        console.info(`[joplin-hap] deleted note ${note.id}`);
        this.reload();
      })
      .catch((e: Error) => { console.error(`[joplin-hap] deleteNote: ${e.message}`); });
  }

  // ── 移动笔记 ──
  private startMoveNote(note: Note): void {
    this.moveNoteId = note.id;
    this.moveNoteParentId = note.parentId;
    this.coverKind = 'moveNote';
    this.showCover = true;
  }

  private execMoveNote(folderId: string): void {
    const noteId: string = this.moveNoteId;
    this.showCover = false;
    if (noteId === '' || folderId === this.moveNoteParentId) {
      return;
    }
    noteRepo.moveToFolder(noteId, folderId)
      .then(() => {
        console.info(`[joplin-hap] moved note ${noteId} → folder '${folderId}'`);
        this.reload();
      })
      .catch((e: Error) => { console.error(`[joplin-hap] moveNote: ${e.message}`); });
  }

  // ── 删除笔记本 ──
  private confirmDeleteFolder(folder: Folder): void {
    this.deleteFolderId = folder.id;
    this.deleteFolderName = folder.title === '' ? I18n.untitledNotebook : folder.title;
    this.deleteFolderNotesToo = false;
    this.coverKind = 'deleteFolder';
    this.showCover = true;
  }

  private execDeleteFolder(): void {
    const folderId: string = this.deleteFolderId;
    const cascade: boolean = this.deleteFolderNotesToo;
    this.showCover = false;
    if (folderId === '') {
      return;
    }
    folderRepo.delete(folderId, true, cascade)
      .then(() => {
        console.info(`[joplin-hap] deleted folder ${folderId} (cascade=${cascade})`);
        // 删除当前选中的笔记本时，回退到「全部笔记」
        if (this.store.selectedFolderId === folderId) {
          this.store.selectedFolderId = '';
        }
        this.reload();
      })
      .catch((e: Error) => { console.error(`[joplin-hap] deleteFolder: ${e.message}`); });
  }

  build() {
    Column() {
      // 顶栏
      Row() {
        if (!this.showSidebar) {
          Button('☰')
            .height(32)
            .width(40)
            .fontSize(16)
            .backgroundColor('#EEF1F5')
            .fontColor('#1F58B8')
            .margin({ right: 8 })
            .onClick(() => { this.showSidebar = true; })
        }
        Text(I18n.appTitle)
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .layoutWeight(1)
        Text(I18n.appSubtitle)
          .fontSize(11)
          .fontColor('#9A9A9A')
          .margin({ right: 8 })
        Button(I18n.tabSettings)
          .height(32)
          .fontSize(13)
          .margin({ left: 8 })
          .onClick(() => {
            router.pushUrl({ url: 'pages/Settings' })
              .catch((e: Error) => { console.error(`[joplin-hap] nav settings: ${e.message}`); });
          })
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 10, bottom: 10 })
      .backgroundColor('#FFFFFF')

      // 主内容
      Row() {
        if (this.showSidebar) {
          this.sideBar()
        }
        this.noteList()
      }
      .layoutWeight(1)
      .width('100%')
      .alignItems(VerticalAlign.Top)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F2F4F7')
    .bindContentCover($$this.showCover, this.coverDialog())
  }

  @Builder
  noteContextMenu(note: Note) {
    Menu() {
      MenuItem({ content: I18n.noteMoveTo })
        .onClick(() => { this.startMoveNote(note); })
      MenuItem({ content: I18n.delete })
        .onClick(() => { this.confirmDeleteNote(note); })
    }
  }

  @Builder
  folderContextMenu(folder: Folder) {
    Menu() {
      MenuItem({ content: I18n.notebookDelete })
        .onClick(() => { this.confirmDeleteFolder(folder); })
    }
  }

  @Builder
  sideBar() {
    Column() {
      // 笔记本分组
      Row() {
        Text(I18n.notebooksTitle)
          .fontSize(12)
          .fontColor('#6B6B6B')
          .layoutWeight(1)
        Button('+')
          .height(26)
          .width(34)
          .fontSize(15)
          .backgroundColor('#EEF1F5')
          .fontColor('#1F58B8')
          .onClick(() => { this.openCreateFolder(); })
        Button('×')
          .height(26)
          .width(34)
          .fontSize(15)
          .backgroundColor('#EEF1F5')
          .fontColor('#6B6B6B')
          .margin({ left: 4 })
          .onClick(() => { this.showSidebar = false; })
      }
      .width('100%')
      .padding({ left: 12, right: 8, top: 8, bottom: 4 })

      List({ space: 2 }) {
        ListItem() {
          Row() {
            Text(I18n.notesTitle)
              .layoutWeight(1)
              .fontSize(14)
              .fontWeight(this.store.selectedFolderId === '' && this.store.selectedTagId === ''
                ? FontWeight.Medium : FontWeight.Normal)
            Text(`${this.store.totalNotes}`)
              .fontSize(12)
              .fontColor('#9A9A9A')
          }
          .padding(10)
          .backgroundColor(this.store.selectedFolderId === '' && this.store.selectedTagId === ''
            ? '#E1ECFF' : Color.Transparent)
          .borderRadius(8)
          .onClick(() => { this.pickFolder(''); })
        }

        ForEach(this.store.folders, (folder: Folder) => {
          ListItem() {
            Row() {
              Text('📁')
                .fontSize(14)
                .margin({ right: 6 })
              Text(folder.title === '' ? I18n.untitledNotebook : folder.title)
                .layoutWeight(1)
                .fontSize(14)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              // 笔记数（参照桌面端侧栏）
              Text(`${this.store.folderNoteCounts[folder.id] ?? 0}`)
                .fontSize(12)
                .fontColor('#9A9A9A')
                .margin({ right: 4 })
              if (this.store.selectedFolderId === folder.id) {
                Text('•').fontColor('#1F58B8').fontSize(18)
              }
            }
            .padding(10)
            .backgroundColor(this.store.selectedFolderId === folder.id ? '#E1ECFF' : Color.Transparent)
            .borderRadius(8)
            .onClick(() => { this.pickFolder(folder.id); })
            .bindContextMenu(this.folderContextMenu(folder), ResponseType.LongPress)
          }
        }, (folder: Folder) => `${folder.id}-${folder.updatedTime}`)

        // 回收站（虚拟视图：deleted_time>0 的笔记，不是同步下来的真实 folder）
        ListItem() {
          Row() {
            Text('🗑')
              .fontSize(14)
              .margin({ right: 6 })
            Text(I18n.trashTitle)
              .layoutWeight(1)
              .fontSize(14)
              .fontColor(this.store.selectedFolderId === TRASH_VIEW_ID ? '#1F58B8' : '#3C3C3C')
            Text(`${this.store.trashCount}`)
              .fontSize(12)
              .fontColor('#9A9A9A')
              .margin({ right: 4 })
            if (this.store.selectedFolderId === TRASH_VIEW_ID) {
              Text('•').fontColor('#1F58B8').fontSize(18)
            }
          }
          .padding(10)
          .backgroundColor(this.store.selectedFolderId === TRASH_VIEW_ID ? '#E1ECFF' : Color.Transparent)
          .borderRadius(8)
          .onClick(() => { this.pickTrash(); })
        }
      }
      .layoutWeight(3)
      .width('100%')
      .padding({ left: 6, right: 6 })
      .listDirection(Axis.Vertical)

      Divider().color('#E1E4E8')

      // 标签分组
      Text(I18n.tagsTitle)
        .fontSize(12)
        .fontColor('#6B6B6B')
        .width('100%')
        .padding({ left: 12, top: 10, bottom: 4 })

      List({ space: 2 }) {
        ForEach(this.store.tags, (tag: Tag) => {
          ListItem() {
            Row() {
              Text(`# ${tag.title}`)
                .fontSize(13)
                .fontColor(this.store.selectedTagId === tag.id ? '#1F58B8' : '#3C3C3C')
                .layoutWeight(1)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .padding({ left: 10, right: 10, top: 7, bottom: 7 })
            .backgroundColor(this.store.selectedTagId === tag.id ? '#E1ECFF' : Color.Transparent)
            .borderRadius(8)
            .onClick(() => { this.pickTag(tag.id); })
          }
        }, (tag: Tag) => `${tag.id}-${tag.updatedTime}`)
      }
      .layoutWeight(2)
      .width('100%')
      .padding({ left: 6, right: 6, bottom: 8 })
      .listDirection(Axis.Vertical)
    }
    .width('42%')
    .height('100%')
    .backgroundColor('#FFFFFF')
  }

  @Builder
  coverDialog() {
    if (this.coverKind === 'createFolder') {
      this.createFolderDialog()
    } else if (this.coverKind === 'moveNote') {
      this.moveNoteDialog()
    } else if (this.coverKind === 'deleteFolder') {
      this.deleteFolderDialog()
    }
  }

  @Builder
  createFolderDialog() {
    Column() {
      Column() {
        Text(I18n.newNotebook)
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .margin({ bottom: 12 })
        TextInput({ placeholder: I18n.newNotebook, text: this.newFolderTitle })
          .onChange((v: string) => { this.newFolderTitle = v; })
        Row() {
          Button(I18n.cancel)
            .backgroundColor('#EEF1F5')
            .fontColor('#3C3C3C')
            .onClick(() => {
              this.newFolderTitle = '';
              this.showCover = false;
            })
          Blank()
          Button(I18n.confirm)
            .onClick(() => { this.createFolder(); })
        }
        .width('100%')
        .margin({ top: 16 })
      }
      .padding(20)
      .backgroundColor('#FFFFFF')
      .borderRadius(12)
      .width('80%')
    }
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .width('100%')
    .height('100%')
    .backgroundColor('rgba(0,0,0,0.4)')
  }

  @Builder
  moveNoteDialog() {
    Column() {
      Column() {
        Text(I18n.noteMoveTo)
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .margin({ bottom: 12 })
        List({ space: 2 }) {
          // 根目录（全部笔记）
          ListItem() {
            Row() {
              Text(I18n.moveToRoot)
                .layoutWeight(1)
                .fontSize(14)
              if (this.moveNoteParentId === '') {
                Text('•').fontColor('#1F58B8').fontSize(18)
              }
            }
            .padding(10)
            .borderRadius(8)
            .backgroundColor(this.moveNoteParentId === '' ? '#E1ECFF' : Color.Transparent)
            .onClick(() => { this.execMoveNote(''); })
          }
          ForEach(this.store.folders, (folder: Folder) => {
            ListItem() {
              Row() {
                Text('📁')
                  .fontSize(14)
                  .margin({ right: 6 })
                Text(folder.title === '' ? I18n.untitledNotebook : folder.title)
                  .layoutWeight(1)
                  .fontSize(14)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                if (this.moveNoteParentId === folder.id) {
                  Text('•').fontColor('#1F58B8').fontSize(18)
                }
              }
              .padding(10)
              .borderRadius(8)
              .backgroundColor(this.moveNoteParentId === folder.id ? '#E1ECFF' : Color.Transparent)
              .onClick(() => { this.execMoveNote(folder.id); })
            }
          }, (folder: Folder) => folder.id)
        }
        .width('100%')
        .layoutWeight(1)
        .listDirection(Axis.Vertical)
        Row() {
          Blank()
          Button(I18n.cancel)
            .backgroundColor('#EEF1F5')
            .fontColor('#3C3C3C')
            .onClick(() => { this.showCover = false; })
        }
        .width('100%')
        .margin({ top: 16 })
      }
      .padding(20)
      .backgroundColor('#FFFFFF')
      .borderRadius(12)
      .width('80%')
      .height('60%')
    }
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .width('100%')
    .height('100%')
    .backgroundColor('rgba(0,0,0,0.4)')
  }

  @Builder
  deleteFolderDialog() {
    Column() {
      Column() {
        Text(I18n.notebookDelete)
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .margin({ bottom: 12 })
        Text(I18n.notebookDeleteConfirm(this.deleteFolderName))
          .fontSize(14)
          .fontColor('#3C3C3C')
          .width('100%')
        if (!this.deleteFolderNotesToo) {
          Text(I18n.notebookDeleteKeepHint(this.store.folderNoteCounts[this.deleteFolderId] ?? 0))
            .fontSize(13)
            .fontColor('#6B6B6B')
            .width('100%')
            .margin({ top: 8 })
        }
        Row() {
          Checkbox()
            .select(this.deleteFolderNotesToo)
            .onChange((v: boolean) => { this.deleteFolderNotesToo = v; })
          Text(I18n.notebookDeleteAlsoNotes)
            .fontSize(14)
            .fontColor('#B3261E')
            .margin({ left: 8 })
        }
        .width('100%')
        .margin({ top: 12 })
        Row() {
          Button(I18n.cancel)
            .backgroundColor('#EEF1F5')
            .fontColor('#3C3C3C')
            .onClick(() => { this.showCover = false; })
          Blank()
          Button(I18n.delete)
            .fontColor('#B3261E')
            .backgroundColor('#FBE9E7')
            .onClick(() => { this.execDeleteFolder(); })
        }
        .width('100%')
        .margin({ top: 16 })
      }
      .padding(20)
      .backgroundColor('#FFFFFF')
      .borderRadius(12)
      .width('80%')
    }
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .width('100%')
    .height('100%')
    .backgroundColor('rgba(0,0,0,0.4)')
  }

  @Builder
  noteList() {
    Column() {
      Row() {
        Text(this.store.currentTitle())
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Button(I18n.search)
          .height(32)
          .fontSize(13)
          .backgroundColor('#EEF1F5')
          .fontColor('#1F58B8')
          .onClick(() => {
            router.pushUrl({ url: 'pages/NoteSearch' })
              .catch((e: Error) => { console.error(`[joplin-hap] nav search: ${e.message}`); });
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 14, bottom: 10 })

      if (this.store.notes.length === 0) {
        Column() {
          Text(I18n.noNotes)
            .fontSize(16)
            .fontColor('#6B6B6B')
          Text(I18n.createFirstNote)
            .fontSize(13)
            .fontColor('#9A9A9A')
            .margin({ top: 8 })
        }
        .layoutWeight(1)
        .width('100%')
        .justifyContent(FlexAlign.Center)
      } else {
        List({ space: 0 }) {
          ForEach(this.store.notes, (note: Note) => {
            ListItem() {
              this.noteRow(note)
            }
            .onClick(() => { this.openNote(note.id); })
            .bindContextMenu(this.noteContextMenu(note), ResponseType.LongPress)
          }, (note: Note) => `${note.id}-${note.updatedTime}`)
        }
        .layoutWeight(1)
        .width('100%')
        .divider({ strokeWidth: 0.5, color: '#E1E4E8' })
      }

      Row() {
        Blank()
        Button(`+ ${I18n.newNote}`)
          .onClick(() => { this.createNote(); })
      }
      .width('100%')
      .padding(16)
    }
    .layoutWeight(1)
    .height('100%')
  }

  @Builder
  noteRow(note: Note) {
    Column() {
      Text(note.title === '' ? I18n.untitled : note.title)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .width('100%')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      if (note.body !== '') {
        Text(note.body.substring(0, 200))
          .fontSize(12)
          .fontColor('#6B6B6B')
          .width('100%')
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 4 })
      }
    }
    .alignItems(HorizontalAlign.Start)
    .padding(16)
    .width('100%')
  }

  private pickFolder(id: string): void {
    this.store.selectFolder(id)
      .then(() => { this.revision += 1; })
      .catch((e: Error) => { console.error(`[joplin-hap] selectFolder: ${e.message}`); });
  }

  private pickTrash(): void {
    this.store.selectTrash()
      .then(() => { this.revision += 1; })
      .catch((e: Error) => { console.error(`[joplin-hap] selectTrash: ${e.message}`); });
  }

  private pickTag(id: string): void {
    this.store.selectTag(id)
      .then(() => { this.revision += 1; })
      .catch((e: Error) => { console.error(`[joplin-hap] selectTag: ${e.message}`); });
  }

  private openNote(id: string): void {
    this.store.selectedNoteId = id;
    router.pushUrl({ url: 'pages/NoteEditor', params: new NoteRouteParams(id) })
      .catch((e: Error) => { console.error(`[joplin-hap] nav editor: ${e.message}`); });
  }

  private openCreateFolder(): void {
    this.coverKind = 'createFolder';
    this.showCover = true;
  }

  private createFolder(): void {
    const title: string = this.newFolderTitle.trim();
    if (title === '') {
      return;
    }
    folderRepo.upsert(newFolder(title))
      .then(() => {
        this.newFolderTitle = '';
        this.showCover = false;
        this.reload();
      })
      .catch((e: Error) => { console.error(`[joplin-hap] createFolder: ${e.message}`); });
  }

  private createNote(): void {
    const note: Note = newNote(this.store.selectedFolderId, I18n.untitled, '');
    noteRepo.upsert(note)
      .then(() => {
        this.openNote(note.id);
      })
      .catch((e: Error) => { console.error(`[joplin-hap] createNote: ${e.message}`); });
  }
}
