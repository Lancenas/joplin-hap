import router from '@ohos.router';
import { appStore } from '../viewmodel/AppStore';
import { SyncProgress, SyncResult, Synchronizer } from '../core/sync/Synchronizer';

@Entry
@Component
struct Settings {
  @State serverUrl: string = '';
  @State email: string = '';
  @State password: string = '';
  @State syncing: boolean = false;
  @State message: string = 'Configure your Joplin Server, then tap "Sync now".';

  aboutToAppear(): void {
    appStore.loadSyncConfig()
      .then(() => {
        this.serverUrl = appStore.syncUrl;
        this.email = appStore.syncUser;
        this.password = appStore.syncPassword;
      })
      .catch((e: Error) => { this.message = `Could not read settings: ${e.message}`; });
  }

  build() {
    Column() {
      Row() {
        Button('← Back')
          .height(32)
          .fontSize(13)
          .backgroundColor('#EEF1F5')
          .fontColor('#1F58B8')
          .onClick(() => { router.back(); })
        Text('Sync settings')
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .margin({ left: 12 })
      }
      .width('100%')
      .padding(12)

      Scroll() {
        Column() {
          Text('Joplin Server URL')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .margin({ top: 8, bottom: 6 })
          TextInput({ placeholder: 'https://your-server.example.com', text: this.serverUrl })
            .height(40)
            .width('100%')
            .onChange((v: string) => { this.serverUrl = v; })

          Text('Email')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .margin({ top: 14, bottom: 6 })
          TextInput({ placeholder: 'user@example.com', text: this.email })
            .height(40)
            .width('100%')
            .type(InputType.Email)
            .onChange((v: string) => { this.email = v; })

          Text('Password')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .margin({ top: 14, bottom: 6 })
          TextInput({ placeholder: 'password', text: this.password })
            .type(InputType.Password)
            .height(40)
            .width('100%')
            .onChange((v: string) => { this.password = v; })

          Button('Save')
            .margin({ top: 18 })
            .onClick(() => { this.persist(); })

          Divider().color('#E1E4E8').margin({ top: 24, bottom: 16 })

          Text('Sync')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
          Text(this.message)
            .fontSize(12)
            .fontColor('#6B6B6B')
            .width('100%')
            .margin({ top: 8 })
          Button(this.syncing ? 'Syncing…' : 'Sync now')
            .margin({ top: 12 })
            .enabled(!this.syncing)
            .onClick(() => { this.runSync(); })

          Button('Force full resync')
            .margin({ top: 8 })
            .fontSize(12)
            .backgroundColor('#EEF1F5')
            .fontColor('#1F58B8')
            .enabled(!this.syncing)
            .onClick(() => { this.forceResync(); })

          Text('joplin-hap keeps a Joplin-compatible SQLite database and speaks the '
            + 'same item format and sync protocol as the official clients, so the same '
            + 'account can be shared with Joplin on desktop and mobile.')
            .fontSize(11)
            .fontColor('#9A9A9A')
            .width('100%')
            .margin({ top: 24 })
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
      .then(() => { this.message = 'Saved.'; })
      .catch((e: Error) => { this.message = `Save failed: ${e.message}`; });
  }

  private runSync(): void {
    if (this.serverUrl.trim() === '' || this.email.trim() === '' || this.password === '') {
      this.message = 'Fill in the server URL, email and password first.';
      return;
    }
    this.syncing = true;
    this.message = 'Connecting…';
    appStore.saveSyncConfig(this.serverUrl.trim(), this.email.trim(), this.password)
      .then(() => {
        const sync = new Synchronizer(this.serverUrl.trim(), this.email.trim(), this.password);
        sync.onProgress((p: SyncProgress) => { this.message = p.message; });
        return sync.run();
      })
      .then((result: SyncResult) => {
        this.syncing = false;
        if (result.ok) {
          this.message = `Pushed ${result.pushed} · pulled ${result.pulled} · `
            + `deleted ${result.deleted} (${result.durationMs} ms)`;
          appStore.refreshAll().catch((e: Error) => {
            console.error(`[joplin-hap] refresh after sync: ${e.message}`);
          });
        } else {
          this.message = `Sync failed: ${result.error}`;
        }
      })
      .catch((e: Error) => {
        this.syncing = false;
        this.message = `Sync failed: ${e.message}`;
      });
  }

  private forceResync(): void {
    appStore.resetSyncCursor()
      .then(() => { this.message = 'Sync cursor cleared. Tap "Sync now" to pull everything from scratch.'; })
      .catch((e: Error) => { this.message = `Reset failed: ${e.message}`; });
  }
}
