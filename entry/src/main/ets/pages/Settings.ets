import router from '@ohos.router';
import { I18n } from '../common/I18n';
import { appStore } from '../viewmodel/AppStore';
import { SyncResult } from '../core/sync/Synchronizer';

@Entry
@Component
struct Settings {
  @State serverUrl: string = '';
  @State email: string = '';
  @State password: string = '';
  @State syncing: boolean = false;
  @State message: string = '请先填写服务器信息，然后点击「立即同步」。';

  aboutToAppear(): void {
    appStore.loadSyncConfig()
      .then(() => {
        this.serverUrl = appStore.syncUrl;
        this.email = appStore.syncUser;
        this.password = appStore.syncPassword;
      })
      .catch((e: Error) => { this.message = `${I18n.errorTitle}：${e.message}`; });
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
          .onClick(() => { router.back(); })
        Text(I18n.syncTitle)
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .margin({ left: 12 })
      }
      .width('100%')
      .padding(12)

      Scroll() {
        Column() {
          // —— 服务器配置 ——
          Text(I18n.syncTarget)
            .fontSize(13)
            .fontColor('#9A9A9A')
            .margin({ top: 4, bottom: 8 })

          Text(I18n.syncUrlLabel)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .margin({ top: 8, bottom: 6 })
          TextInput({ placeholder: I18n.syncUrlPlaceholder, text: this.serverUrl })
            .height(40)
            .width('100%')
            .onChange((v: string) => { this.serverUrl = v; })

          Text(I18n.syncEmailLabel)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .margin({ top: 14, bottom: 6 })
          TextInput({ placeholder: 'user@example.com', text: this.email })
            .height(40)
            .width('100%')
            .type(InputType.Email)
            .onChange((v: string) => { this.email = v; })

          Text(I18n.syncPasswordLabel)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .margin({ top: 14, bottom: 6 })
          TextInput({ placeholder: '••••••', text: this.password })
            .type(InputType.Password)
            .height(40)
            .width('100%')
            .onChange((v: string) => { this.password = v; })

          Button(I18n.syncSave)
            .margin({ top: 18 })
            .onClick(() => { this.persist(); })

          Divider().color('#E1E4E8').margin({ top: 24, bottom: 16 })

          // —— 同步操作 ——
          Text(I18n.syncStatus)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
          Text(this.message)
            .fontSize(12)
            .fontColor('#6B6B6B')
            .width('100%')
            .margin({ top: 8 })
          Button(this.syncing ? I18n.syncInProgress : I18n.syncNow)
            .margin({ top: 12 })
            .enabled(!this.syncing)
            .onClick(() => { this.runSync(); })

          Button(I18n.syncForceResync)
            .margin({ top: 8 })
            .fontSize(12)
            .backgroundColor('#EEF1F5')
            .fontColor('#1F58B8')
            .enabled(!this.syncing)
            .onClick(() => { this.forceResync(); })

          // —— 帮助 ——
          Divider().color('#E1E4E8').margin({ top: 28, bottom: 16 })

          Text(I18n.syncHelpDocTitle)
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .margin({ bottom: 8 })
          Text(I18n.syncHelpDoc)
            .fontSize(11)
            .fontColor('#6B6B6B')
            .width('100%')
            .lineHeight(18)

          Text(I18n.syncFooter)
            .fontSize(10)
            .fontColor('#9A9A9A')
            .width('100%')
            .margin({ top: 16 })
            .lineHeight(16)
        }
        .width('100%')
        .padding(16)
        .alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#FFFFFF')
  }

  private persist(): void {
    appStore.saveSyncConfig(this.serverUrl.trim(), this.email.trim(), this.password)
      .then(() => { this.message = I18n.editorSavedToast; })
      .catch((e: Error) => { this.message = `${this.errorLabel(e.message)}`; });
  }

  private runSync(): void {
    if (this.serverUrl.trim() === '' || this.email.trim() === '' || this.password === '') {
      this.message = '请先填写完整的服务器 URL、邮箱与密码。';
      return;
    }
    this.syncing = true;
    this.message = I18n.syncConnecting;
    appStore.saveSyncConfig(this.serverUrl.trim(), this.email.trim(), this.password)
      .then(() => {
        // 共享 AppStore.runSync：进度/结果会同时驱动侧边栏底部的同步状态。
        return appStore.runSync(() => { this.message = appStore.syncMessage; });
      })
      .then((result: SyncResult) => {
        this.syncing = false;
        if (result.ok) {
          this.message =
            `已上传 ${result.pushed} 项 · 已下载 ${result.pulled} 项 · ` +
            `已删除 ${result.deleted} 项（${result.durationMs} 毫秒）`;
        } else {
          this.message = I18n.syncFailed(result.error ?? '');
        }
      })
      .catch((e: Error) => {
        this.syncing = false;
        this.message = I18n.syncFailed(e.message);
      });
  }

  private forceResync(): void {
    appStore.resetSyncCursor()
      .then(() => { this.message = '同步游标已清空，请点击「立即同步」重新拉取全部数据。'; })
      .catch((e: Error) => { this.message = `${this.errorLabel(e.message)}`; });
  }

  private errorLabel(reason: string): string {
    return `${I18n.errorTitle}：${reason}`;
  }
}
