import router from '@ohos.router';
import { Note } from '../core/models/Entities';
import { noteRepo } from '../core/services/Repositories';
import { NoteRouteParams } from '../viewmodel/RouteParams';

// NOTE: the struct may not be called `Search` — ArkUI reserves that name for
// the built-in component (error 10905237).
@Entry
@Component
struct NoteSearchPage {
  @State query: string = '';
  @State results: Note[] = [];
  @State searched: boolean = false;

  build() {
    Column() {
      Row() {
        Button('← Back')
          .height(32)
          .fontSize(13)
          .backgroundColor('#EEF1F5')
          .fontColor('#1F58B8')
          .onClick(() => { router.back(); })
        TextInput({ placeholder: 'Search notes', text: this.query })
          .layoutWeight(1)
          .height(40)
          .margin({ left: 12 })
          .onChange((v: string) => { this.query = v; })
          .onSubmit(() => { this.runSearch(); })
        Button('Go')
          .height(32)
          .fontSize(13)
          .margin({ left: 8 })
          .onClick(() => { this.runSearch(); })
      }
      .width('100%')
      .padding(12)

      if (this.results.length === 0) {
        Column() {
          Text(this.searched ? 'No matching notes.' : 'Type a query and tap Go.')
            .fontSize(13)
            .fontColor('#6B6B6B')
        }
        .layoutWeight(1)
        .width('100%')
        .justifyContent(FlexAlign.Center)
      } else {
        List({ space: 0 }) {
          ForEach(this.results, (n: Note) => {
            ListItem() {
              Column() {
                Text(n.title === '' ? 'Untitled' : n.title)
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

  private runSearch(): void {
    const q: string = this.query.trim();
    if (q === '') {
      this.results = [];
      this.searched = false;
      return;
    }
    noteRepo.search(q)
      .then((rows: Note[]) => {
        this.results = rows;
        this.searched = true;
      })
      .catch((e: Error) => { console.error(`[joplin-hap] search: ${e.message}`); });
  }
}
