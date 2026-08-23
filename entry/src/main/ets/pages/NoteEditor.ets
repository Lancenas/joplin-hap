import router from '@ohos.router';
import { webview } from '@kit.ArkWeb';
import { I18n } from '../common/I18n';
import { Note, Tag, newTag } from '../core/models/Entities';
import { noteRepo, noteTagRepo, tagRepo } from '../core/services/Repositories';
import { markdownToHtml, previewTemplate } from '../core/markdown/MarkdownRenderer';
import { resolveImagesInHtml } from '../core/services/ResourceCache';
import { NoteRouteParams } from '../viewmodel/RouteParams';

@Entry
@Component
struct NoteEditor {
  @State note: Note | null = null;
  @State body: string = '';
  @State title: string = '';
  @State saving: boolean = false;
  @State showPreview: boolean = false;
  @State tagInput: string = '';
  @State attachedTags: string[] = [];
  @State status: string = '';
  @State previewLoading: boolean = false;
  @State selStart: number = 0;
  @State selEnd: number = 0;

  private noteId: string = '';
  private webController: webview.WebviewController = new webview.WebviewController();
  private webReady: boolean = false;
  private previewHtml: string = '';
  private textController: TextAreaController = new TextAreaController();

  aboutToAppear(): void {
    const params = router.getParams() as NoteRouteParams;
    this.noteId = params === null || params === undefined ? '' : params.id;
    this.load();
  }

  onBackPress(): boolean {
    // 系统返回手势触发静默保存，避免编辑内容丢失。
    this.save();
    return false;
  }

  private load(): void {
    if (this.noteId === '') {
      return;
    }
    noteRepo.get(this.noteId)
      .then((n: Note | null) => {
        if (n === null) {
          this.status = I18n.editorNoBody;
          return;
        }
        this.note = n;
        this.body = n.body;
        this.title = n.title;
        this.refreshTags();
      })
      .catch((e: Error) => { this.status = `${I18n.errorTitle}：${e.message}`; });
  }

  private refreshTags(): void {
    noteTagRepo.tagsForNote(this.noteId)
      .then((tags: Tag[]) => {
        const titles: string[] = [];
        for (const t of tags) {
          titles.push(t.title);
        }
        this.attachedTags = titles;
      })
      .catch((e: Error) => { console.error(`[joplin-hap] tagsForNote: ${e.message}`); });
  }

  build() {
    Column() {
      // 顶栏
      Row() {
        Button(`← ${I18n.back}`)
          .height(32)
          .fontSize(13)
          .backgroundColor('#EEF1F5')
          .fontColor('#1F58B8')
          .onClick(() => {
            this.save();
            router.back();
          })
        Blank()
        Button(I18n.delete)
          .height(32)
          .fontSize(13)
          .backgroundColor('#FEE')
          .fontColor('#B3261E')
          .margin({ right: 8 })
          .onClick(() => { this.confirmDelete(); })
        Button(this.showPreview ? I18n.editorEdit : I18n.editorPreview)
          .height(32)
          .fontSize(13)
          .backgroundColor('#EEF1F5')
          .fontColor('#1F58B8')
          .margin({ right: 8 })
          .onClick(() => {
            this.showPreview = !this.showPreview;
            if (this.showPreview) {
              this.renderPreview();
            }
          })
        Button(this.saving ? I18n.loading : I18n.editorSave)
          .height(32)
          .fontSize(13)
          .enabled(!this.saving)
          .onClick(() => { this.save(); })
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 12, bottom: 8 })

      // 标题输入
      TextInput({ placeholder: I18n.editorTitlePlaceholder, text: this.title })
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .height(48)
        .margin({ left: 8, right: 8 })
        .backgroundColor(Color.Transparent)
        .onChange((v: string) => { this.title = v; })

      if (this.showPreview) {
        // Web 渲染真正的 Markdown（标题/加粗/列表/代码块/图片等）
        Stack() {
          Web({ src: 'about:blank', controller: this.webController })
            .javaScriptAccess(true)
            .domStorageAccess(true)
            .imageAccess(true)
            .fileAccess(true)
            .onlineImageAccess(true)
            .layoutWeight(1)
            .width('100%')
            .onControllerAttached(() => {
              this.webReady = true;
              console.info('[joplin-hap] web controller attached');
              if (this.previewHtml !== '') {
                this.webController.loadData(this.previewHtml, 'text/html', 'utf-8');
              }
            })
            .onPageEnd(() => {
              console.info('[joplin-hap] web preview page loaded');
            })
          if (this.previewLoading) {
            Column() {
              LoadingProgress().width(36).height(36)
              Text('渲染中…').fontSize(13).fontColor('#9A9A9A').margin({ top: 8 })
            }
            .width('100%')
            .height('100%')
            .justifyContent(FlexAlign.Center)
            .backgroundColor('#FFFFFF')
          }
        }
        .layoutWeight(1)
        .width('100%')
      } else {
        // Markdown 格式化工具栏
        Scroll() {
          Row({ space: 6 }) {
            Button('B').fontSize(13).fontWeight(FontWeight.Bold).height(30)
              .backgroundColor('#EEF1F5').fontColor('#3C3C3C')
              .onClick(() => { this.wrapSelection('**', '**', '加粗'); })
            Button('I').fontSize(13).fontStyle(FontStyle.Italic).height(30)
              .backgroundColor('#EEF1F5').fontColor('#3C3C3C')
              .onClick(() => { this.wrapSelection('*', '*', '斜体'); })
            Button('S').fontSize(13).height(30)
              .backgroundColor('#EEF1F5').fontColor('#3C3C3C')
              .onClick(() => { this.wrapSelection('~~', '~~', '删除线'); })
            Button('H').fontSize(13).fontWeight(FontWeight.Medium).height(30)
              .backgroundColor('#EEF1F5').fontColor('#3C3C3C')
              .onClick(() => { this.insertLinePrefix('## '); })
            Button('• 列表').fontSize(12).height(30)
              .backgroundColor('#EEF1F5').fontColor('#3C3C3C')
              .onClick(() => { this.insertLinePrefix('- '); })
            Button('☑ 待办').fontSize(12).height(30)
              .backgroundColor('#EEF1F5').fontColor('#3C3C3C')
              .onClick(() => { this.insertLinePrefix('- [ ] '); })
            Button('<>').fontSize(12).height(30)
              .backgroundColor('#EEF1F5').fontColor('#3C3C3C')
              .onClick(() => { this.wrapSelection('`', '`', '代码'); })
            Button('{ }').fontSize(12).height(30)
              .backgroundColor('#EEF1F5').fontColor('#3C3C3C')
              .onClick(() => { this.wrapSelection('\n```\n', '\n```\n', '代码块'); })
            Button('🔗').fontSize(12).height(30)
              .backgroundColor('#EEF1F5').fontColor('#3C3C3C')
              .onClick(() => { this.wrapSelection('[', '](https://)', '链接文字'); })
            Button('🖼').fontSize(12).height(30)
              .backgroundColor('#EEF1F5').fontColor('#3C3C3C')
              .onClick(() => { this.wrapSelection('![', '](:/资源ID)', '图片'); })
          }
          .padding({ left: 12, right: 12 })
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .width('100%')
        .height(40)
        .align(Alignment.Start)

        TextArea({ placeholder: I18n.editorBodyPlaceholder, text: this.body, controller: this.textController })
          .layoutWeight(1)
          .width('100%')
          .fontSize(15)
          .padding(12)
          .backgroundColor(Color.Transparent)
          .onChange((v: string) => { this.body = v; })
          .onTextSelectionChange((start: number, end: number) => {
            this.selStart = start;
            this.selEnd = end;
          })
      }

      if (this.status !== '') {
        Text(this.status)
          .fontSize(12)
          .fontColor('#B3261E')
          .width('100%')
          .padding({ left: 12, right: 12, bottom: 4 })
      }

      // 标签输入
      Row() {
        TextInput({ placeholder: I18n.attachTagHint, text: this.tagInput })
          .layoutWeight(1)
          .height(36)
          .onChange((v: string) => { this.tagInput = v; })
        Button(I18n.attachTag)
          .height(36)
          .fontSize(13)
          .margin({ left: 8 })
          .onClick(() => { this.attachTag(); })
      }
      .width('100%')
      .padding({ left: 12, right: 12, bottom: 6 })

      if (this.attachedTags.length > 0) {
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.attachedTags, (t: string) => {
            Text(`#${t}`)
              .fontSize(12)
              .fontColor('#1F58B8')
              .backgroundColor('#E1ECFF')
              .padding({ left: 8, right: 8, top: 4, bottom: 4 })
              .borderRadius(12)
              .margin({ right: 6, bottom: 6 })
          }, (t: string) => t)
        }
        .width('100%')
        .padding({ left: 12, right: 12, bottom: 12 })
      } else {
        Text(I18n.noAttachedTags)
          .fontSize(12)
          .fontColor('#9A9A9A')
          .padding({ left: 12, right: 12, bottom: 12 })
          .width('100%')
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#FFFFFF')
  }

  private save(): void {
    const current: Note | null = this.note;
    if (current === null || this.saving) {
      return;
    }
    this.saving = true;
    current.body = this.body;
    const trimmed: string = this.title.trim();
    current.title = trimmed === '' ? I18n.untitled : trimmed;
    noteRepo.upsert(current)
      .then(() => {
        this.saving = false;
        this.status = '';
      })
      .catch((e: Error) => {
        this.saving = false;
        this.status = `${I18n.editorSave}：${e.message}`;
      });
  }

  private confirmDelete(): void {
    const current: Note | null = this.note;
    if (current === null) {
      return;
    }
    const title: string = current.title === '' ? I18n.untitled : current.title;
    AlertDialog.show({
      title: I18n.delete,
      message: I18n.noteDeleteConfirm(title),
      primaryButton: { value: I18n.cancel, action: () => {} },
      secondaryButton: {
        value: I18n.delete,
        fontColor: '#B3261E',
        action: () => { this.deleteNote(current); }
      }
    });
  }

  private deleteNote(note: Note): void {
    noteRepo.delete(note.id)
      .then(() => {
        console.info(`[joplin-hap] deleted note ${note.id} from editor`);
        router.back();
      })
      .catch((e: Error) => { this.status = `${I18n.delete}：${e.message}`; });
  }

  private attachTag(): void {
    const title: string = this.tagInput.trim();
    const current: Note | null = this.note;
    if (title === '' || current === null) {
      return;
    }
    tagRepo.findByTitle(title)
      .then((existing: Tag | null) => {
        // 标签已存在时直接复用，避免分裂标签命名空间。
        return existing === null ? tagRepo.upsert(newTag(title)) : Promise.resolve(existing);
      })
      .then((tag: Tag) => noteTagRepo.add(current.id, tag.id))
      .then(() => {
        this.tagInput = '';
        this.refreshTags();
      })
      .catch((e: Error) => { this.status = `${I18n.attachTag}：${e.message}`; });
  }

  // 渲染预览：markdown → HTML，解析其中的资源图片（下载 + base64 内嵌），
  // 再套 previewTemplate 的样式，最后交给 Web 组件。
  private renderPreview(): void {
    this.previewLoading = true;
    const rawHtml: string = this.body === ''
      ? '<p style="color:#9A9A9A">该笔记暂无内容</p>'
      : markdownToHtml(this.body);
    const hasImg: boolean = rawHtml.indexOf('data-resource-id') >= 0;
    console.info(`[joplin-hap] renderPreview: body ${this.body.length} chars, html ${rawHtml.length} chars, hasResourceImg=${hasImg}`);
    resolveImagesInHtml(rawHtml)
      .then((resolved: string) => {
        this.previewHtml = previewTemplate(resolved);
        this.previewLoading = false;
        console.info(`[joplin-hap] renderPreview: resolved html ${this.previewHtml.length} chars, webReady=${this.webReady}`);
        if (this.webReady) {
          this.webController.loadData(this.previewHtml, 'text/html', 'utf-8');
        }
      })
      .catch((e: Error) => {
        console.warn(`[joplin-hap] renderPreview resolve failed: ${e.message}`);
        this.previewHtml = previewTemplate(rawHtml);
        this.previewLoading = false;
        if (this.webReady) {
          this.webController.loadData(this.previewHtml, 'text/html', 'utf-8');
        }
      });
  }

  // 用 prefix/suffix 包裹当前选区；无选区时插入占位文本。
  private wrapSelection(prefix: string, suffix: string, placeholder: string): void {
    const s: number = Math.min(this.selStart, this.selEnd);
    const e: number = Math.max(this.selStart, this.selEnd);
    const selected: string = this.body.substring(s, e);
    const inner: string = selected === '' ? placeholder : selected;
    this.body = this.body.substring(0, s) + prefix + inner + suffix + this.body.substring(e);
    const caret: number = s + prefix.length + inner.length + suffix.length;
    setTimeout(() => {
      try {
        this.textController.caretPosition(caret);
      } catch (err) {
        // 光标复位失败无害，内容已插入。
      }
    }, 50);
  }

  // 在当前行行首插入前缀（标题 / 列表 / 待办）。
  private insertLinePrefix(prefix: string): void {
    const s: number = Math.min(this.selStart, this.selEnd);
    const safeS: number = s < 0 ? 0 : s;
    const nl: number = this.body.lastIndexOf('\n', safeS > 0 ? safeS - 1 : 0);
    const lineStart: number = nl < 0 ? 0 : nl + 1;
    this.body = this.body.substring(0, lineStart) + prefix + this.body.substring(lineStart);
    const caret: number = safeS + prefix.length;
    setTimeout(() => {
      try {
        this.textController.caretPosition(caret);
      } catch (err) {
        // ignore
      }
    }, 50);
  }
}
