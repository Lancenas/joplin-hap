import router from '@ohos.router';
import { I18n } from '../common/I18n';
import { Note } from '../core/models/Entities';
import { noteRepo, tagRepo } from '../core/services/Repositories';
import { NoteRouteParams, TagRouteParams } from '../viewmodel/RouteParams';

@Entry
@Component
struct NoteList {
  @State notes: Note[] = [];
  @State title: string = I18n.notesTitle;

  private tagId: string = '';

  aboutToAppear(): void {
    const params = router.getParams() as TagRouteParams;
    if (params !== null && params !== undefined) {
      this.tagId = params.tagId;
      if (params.title !== '') {
        this.title = `#${params.title}`;
      }
    }
    this.load();
  }

  onPageShow(): void {
    this.load();
  }

  private load(): void {
    const p: Promise<Note[]> = this.tagId === ''
      ? noteRepo.listRecent()
      : tagRepo.notesForTag(this.tagId);
    p.then((rows: Note[]) => { this.notes = rows; })
      .catch((e: Error) => { console.error(`[joplin-hap] note list: ${e.message}`); });
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
        Text(this.title)
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .margin({ left: 12 })
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .padding(12)

      if (this.notes.length === 0) {
        Column() {
          Text(I18n.noNotes)
            .fontSize(13)
            .fontColor('#6B6B6B')
        }
        .layoutWeight(1)
        .width('100%')
        .justifyContent(FlexAlign.Center)
      } else {
        List({ space: 0 }) {
          ForEach(this.notes, (n: Note) => {
            ListItem() {
              Column() {
                Text(n.title === '' ? I18n.untitled : n.title)
                  .fontSize(16)
                  .fontWeight(FontWeight.Medium)
                  .width('100%')
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                if (n.body !== '') {
                  Text(n.body.substring(0, 200))
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
            .onClick(() => {
              router.pushUrl({ url: 'pages/NoteEditor', params: new NoteRouteParams(n.id) })
                .catch((e: Error) => { console.error(`[joplin-hap] nav editor: ${e.message}`); });
            })
          }, (n: Note) => `${n.id}-${n.updatedTime}`)
        }
        .layoutWeight(1)
        .width('100%')
        .divider({ strokeWidth: 0.5, color: '#E1E4E8' })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#FFFFFF')
  }
}
