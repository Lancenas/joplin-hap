import router from '@ohos.router';
import { I18n } from '../common/I18n';
import { Tag } from '../core/models/Entities';
import { tagRepo } from '../core/services/Repositories';
import { TagRouteParams } from '../viewmodel/RouteParams';
import { appStore } from '../viewmodel/AppStore';
import { newTag } from '../core/models/Entities';

@Entry
@Component
struct TagList {
  @State tags: Tag[] = [];
  // 统一内容覆盖层：单个 bindContentCover + coverKind 状态机，避免多覆盖层叠加串线
  @State showCover: boolean = false;
  @State coverKind: string = 'none'; // 'rename' | 'create'
  @State renameTagId: string = '';
  @State renameTitle: string = '';
  @State newTagName: string = '';

  aboutToAppear(): void {
    this.reload();
  }

  // 每次页面显示（含从其他页返回）都重新拉取，确保同步后的标签可见。
  onPageShow(): void {
    this.refreshFromStore();
  }

  // 从 AppStore 读最新标签列表，确保同步拉下来的标签能显示。
  private reload(): void {
    this.tags = appStore.tags.slice();
  }

  // 进入页面时让 AppStore 重新拉取一次本地标签（覆盖同步后 TagList 已打开的情况）。
  private async refreshFromStore(): Promise<void> {
    await appStore.refreshTags();
    this.reload();
  }

  // 独立创建一个标签（不挂在某篇笔记上），写入本地并标记待同步。
  private createTag(): void {
    const title: string = this.newTagName.trim();
    this.newTagName = '';
    this.showCover = false;
    this.coverKind = 'none';
    if (title === '') {
      return;
    }
    tagRepo.findByTitle(title)
      .then((existing: Tag | null) => {
        if (existing !== null) {
          throw new Error(I18n.newTagNameExists);
        }
        return tagRepo.upsert(newTag(title), true);
      })
      .then(() => { return this.refreshFromStore(); })
      .catch((e: Error) => {
        console.error(`[joplin-hap] create tag: ${e.message}`);
      });
  }

  // 弹出重命名输入框（单一 bindContentCover 状态机，避免关闭时误触底层列表点击）。
  private startRename(tag: Tag): void {
    this.renameTagId = tag.id;
    this.renameTitle = tag.title;
    // 延迟一帧再开弹窗：bindMenu 浮层关闭时的点击事件会冒泡到底层 ListItem.onClick，
    // 若同步打开覆盖层，会误触发「进入笔记列表」。下一帧再开可避开该冒泡。
    setTimeout(() => {
      this.coverKind = 'rename';
      this.showCover = true;
    }, 0);
  }

  private doRename(): void {
    const title: string = this.renameTitle.trim();
    const id: string = this.renameTagId;
    this.showCover = false;
    this.coverKind = 'none';
    if (title === '' || id === '') {
      return;
    }
    tagRepo.findByTitle(title)
      .then((existing: Tag | null) => {
        if (existing !== null && existing.id !== id) {
          throw new Error(I18n.newTagNameExists);
        }
        return tagRepo.get(id);
      })
      .then((tag: Tag | null) => {
        if (tag === null) {
          return;
        }
        tag.title = title;
        return tagRepo.upsert(tag, true);
      })
      .then(() => {
        return this.refreshFromStore();
      })
      .catch((e: Error) => {
        console.error(`[joplin-hap] rename tag: ${e.message}`);
      });
  }

  private confirmDelete(tag: Tag): void {
    const name: string = tag.title === '' ? I18n.tagsTitle : `#${tag.title}`;
    setTimeout(() => {
      AlertDialog.show({
        title: I18n.delete,
        message: `${I18n.tagDeleteConfirm}\n${I18n.tagDeleteKeepNoteHint}`,
        primaryButton: { value: I18n.cancel, action: () => {} },
        secondaryButton: {
          value: I18n.delete,
          fontColor: '#B3261E',
          action: () => { this.deleteTag(tag); }
        }
      });
    }, 0);
  }

  private deleteTag(tag: Tag): void {
    tagRepo.delete(tag.id)
      .then(() => { return this.refreshFromStore(); })
      .catch((e: Error) => { console.error(`[joplin-hap] delete tag: ${e.message}`); });
  }

  @Builder
  tagContextMenu(tag: Tag) {
    Menu() {
      MenuItem({ content: '查看笔记' })
        .onClick(() => {
          router.pushUrl({ url: 'pages/NoteList', params: new TagRouteParams(tag.id, tag.title) })
            .catch((e: Error) => { console.error(`[joplin-hap] nav note list: ${e.message}`); });
        })
      MenuItem({ content: I18n.renameTag })
        .onClick(() => { this.startRename(tag); })
      MenuItem({ content: I18n.delete })
        .onClick(() => { this.confirmDelete(tag); })
    }
  }

  build() {
    Column() {
      Row() {
        Button(`← ${I18n.back}`)
          .height(32)
          .fontSize(13)
          .backgroundColor('#EEF1F5')
          .fontColor('#1F58B8')
          .onClick(() => { router.back(); })
        Text(I18n.tagsTitle)
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .margin({ left: 12 })
        Blank()
        Button(`+ ${I18n.tagsTitle}`)
          .height(32)
          .fontSize(13)
          .backgroundColor('#EEF1F5')
          .fontColor('#1F58B8')
          .onClick(() => { this.coverKind = 'create'; this.showCover = true; })
        Button(I18n.refresh)
          .height(32)
          .fontSize(13)
          .backgroundColor('#EEF1F5')
          .fontColor('#1F58B8')
          .margin({ left: 8 })
          .onClick(() => { this.refreshFromStore(); })
      }
      .width('100%')
      .padding(12)

      if (this.tags.length === 0) {
        Column() {
          Text(I18n.noTags)
            .fontSize(13)
            .fontColor('#6B6B6B')
          Text(I18n.createFirstTag)
            .fontSize(11)
            .fontColor('#9A9A9A')
            .margin({ top: 4 })
        }
        .layoutWeight(1)
        .width('100%')
        .justifyContent(FlexAlign.Center)
      } else {
        List({ space: 0 }) {
          ForEach(this.tags, (t: Tag) => {
            ListItem() {
              Text(`#${t.title}`)
                .fontSize(15)
                .padding(16)
                .width('100%')
            }
            .bindMenu(this.tagContextMenu(t))
            // 用 TapGesture 而非 .onClick：避免与 bindMenu 长按手势互相吞事件导致串线
            .gesture(
              TapGesture()
                .onAction(() => {
                  router.pushUrl({ url: 'pages/NoteList', params: new TagRouteParams(t.id, t.title) })
                    .catch((e: Error) => { console.error(`[joplin-hap] nav note list: ${e.message}`); });
                })
            )
          }, (t: Tag) => `${t.id}-${t.updatedTime}`)
        }
        .layoutWeight(1)
        .width('100%')
        .divider({ strokeWidth: 0.5, color: '#E1E4E8' })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#FFFFFF')
    .bindContentCover($$this.showCover, this.coverDialog())
  }

  @Builder
  coverDialog() {
    if (this.coverKind === 'rename') {
      this.renameDialog()
    } else if (this.coverKind === 'create') {
      this.createDialog()
    }
  }

  @Builder
  renameDialog() {
    Column() {
      Text(I18n.renameTag)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .width('100%')
        .margin({ bottom: 12 })
      TextInput({ placeholder: I18n.tagRenameHint, text: this.renameTitle })
        .width('100%')
        .onChange((v: string) => { this.renameTitle = v; })
      Row() {
        Button(I18n.cancel)
          .layoutWeight(1)
          .backgroundColor('#EEF1F5')
          .fontColor('#1F58B8')
          .onClick(() => { this.showCover = false; this.coverKind = 'none'; })
        Button(I18n.confirm)
          .layoutWeight(1)
          .onClick(() => { this.doRename(); })
      }
      .width('100%')
      .margin({ top: 16 })
    }
    .padding(20)
    .backgroundColor('#FFFFFF')
    .borderRadius(12)
    .width('80%')
  }

  @Builder
  createDialog() {
    Column() {
      Text(I18n.attachTag)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .width('100%')
        .margin({ bottom: 12 })
      TextInput({ placeholder: I18n.attachTagHint, text: this.newTagName })
        .width('100%')
        .onChange((v: string) => { this.newTagName = v; })
      Row() {
        Button(I18n.cancel)
          .layoutWeight(1)
          .backgroundColor('#EEF1F5')
          .fontColor('#1F58B8')
          .onClick(() => { this.showCover = false; this.coverKind = 'none'; })
        Button(I18n.confirm)
          .layoutWeight(1)
          .onClick(() => { this.createTag(); })
      }
      .width('100%')
      .margin({ top: 16 })
    }
    .padding(20)
    .backgroundColor('#FFFFFF')
    .borderRadius(12)
    .width('80%')
  }
}
