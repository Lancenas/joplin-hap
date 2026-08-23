import router from '@ohos.router';
import { I18n } from '../common/I18n';
import { Tag } from '../core/models/Entities';
import { tagRepo } from '../core/services/Repositories';
import { TagRouteParams } from '../viewmodel/RouteParams';

@Entry
@Component
struct TagList {
  @State tags: Tag[] = [];

  aboutToAppear(): void {
    tagRepo.list()
      .then((rows: Tag[]) => { this.tags = rows; })
      .catch((e: Error) => { console.error(`[joplin-hap] tag list: ${e.message}`); });
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
            .onClick(() => {
              router.pushUrl({ url: 'pages/NoteList', params: new TagRouteParams(t.id, t.title) })
                .catch((e: Error) => { console.error(`[joplin-hap] nav note list: ${e.message}`); });
            })
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
  }
}
