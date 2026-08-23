import router from '@ohos.router';
import { Note, Tag, newTag } from '../core/models/Entities';
import { noteRepo, noteTagRepo, tagRepo } from '../core/services/Repositories';
import { markdownToPlainText } from '../core/markdown/MarkdownRenderer';
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

  private noteId: string = '';

  aboutToAppear(): void {
    const params = router.getParams() as NoteRouteParams;
    this.noteId = params === null || params === undefined ? '' : params.id;
    this.load();
  }

  onBackPress(): boolean {
    // Persist silently so a back-swipe never loses the user's typing.
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
          this.status = 'Note not found';
          return;
        }
        this.note = n;
        this.body = n.body;
        this.title = n.title;
        this.refreshTags();
      })
      .catch((e: Error) => { this.status = `Load failed: ${e.message}`; });
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
      Row() {
        Button('← Back')
          .height(32)
          .fontSize(13)
          .backgroundColor('#EEF1F5')
          .fontColor('#1F58B8')
          .onClick(() => {
            this.save();
            router.back();
          })
        Blank()
        Button(this.showPreview ? 'Edit' : 'Preview')
          .height(32)
          .fontSize(13)
          .backgroundColor('#EEF1F5')
          .fontColor('#1F58B8')
          .margin({ right: 8 })
          .onClick(() => { this.showPreview = !this.showPreview; })
        Button(this.saving ? 'Saving…' : 'Save')
          .height(32)
          .fontSize(13)
          .enabled(!this.saving)
          .onClick(() => { this.save(); })
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 12, bottom: 8 })

      TextInput({ placeholder: 'Title', text: this.title })
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .height(48)
        .margin({ left: 8, right: 8 })
        .backgroundColor(Color.Transparent)
        .onChange((v: string) => { this.title = v; })

      if (this.showPreview) {
        Scroll() {
          Column() {
            Text(markdownToPlainText(this.body))
              .fontSize(15)
              .lineHeight(24)
              .width('100%')
              .padding(16)
              .textAlign(TextAlign.Start)
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
        }
        .layoutWeight(1)
        .width('100%')
        .align(Alignment.TopStart)
      } else {
        TextArea({ placeholder: 'Start writing markdown…', text: this.body })
          .layoutWeight(1)
          .width('100%')
          .fontSize(15)
          .padding(12)
          .backgroundColor(Color.Transparent)
          .onChange((v: string) => { this.body = v; })
      }

      if (this.status !== '') {
        Text(this.status)
          .fontSize(12)
          .fontColor('#B3261E')
          .width('100%')
          .padding({ left: 12, right: 12, bottom: 4 })
      }

      Row() {
        TextInput({ placeholder: 'Add tag', text: this.tagInput })
          .layoutWeight(1)
          .height(36)
          .onChange((v: string) => { this.tagInput = v; })
        Button('Attach')
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
    current.title = trimmed === '' ? 'Untitled' : trimmed;
    noteRepo.upsert(current)
      .then(() => {
        this.saving = false;
        this.status = '';
      })
      .catch((e: Error) => {
        this.saving = false;
        this.status = `Save failed: ${e.message}`;
      });
  }

  private attachTag(): void {
    const title: string = this.tagInput.trim();
    const current: Note | null = this.note;
    if (title === '' || current === null) {
      return;
    }
    tagRepo.findByTitle(title)
      .then((existing: Tag | null) => {
        // Reuse the tag when it already exists so we don't fork the taxonomy.
        return existing === null ? tagRepo.upsert(newTag(title)) : Promise.resolve(existing);
      })
      .then((tag: Tag) => noteTagRepo.add(current.id, tag.id))
      .then(() => {
        this.tagInput = '';
        this.refreshTags();
      })
      .catch((e: Error) => { this.status = `Tag failed: ${e.message}`; });
  }
}
