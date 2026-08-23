import router from '@ohos.router';
import { I18n } from '../common/I18n';
import { AppStore, appStore } from '../viewmodel/AppStore';
import { NoteRouteParams } from '../viewmodel/RouteParams';
import { Folder, Note, Tag, newFolder, newNote } from '../core/models/Entities';
import { folderRepo, noteRepo } from '../core/services/Repositories';

@Entry
@Component
struct Index {
  @State store: AppStore = appStore;
  @State showSidebar: boolean = true;
  @State showCreateFolder: boolean = false;
  @State newFolderTitle: string = '';
  @State revision: number = 0;

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
    .bindContentCover($$this.showCreateFolder, this.createFolderDialog())
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
          .onClick(() => { this.showCreateFolder = true; })
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
          }
        }, (folder: Folder) => `${folder.id}-${folder.updatedTime}`)
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
              this.showCreateFolder = false;
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

  private createFolder(): void {
    const title: string = this.newFolderTitle.trim();
    if (title === '') {
      return;
    }
    folderRepo.upsert(newFolder(title))
      .then(() => {
        this.newFolderTitle = '';
        this.showCreateFolder = false;
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
