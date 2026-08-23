import UIAbility from '@ohos.app.ability.UIAbility';
import AbilityConstant from '@ohos.app.ability.AbilityConstant';
import Want from '@ohos.app.ability.Want';
import window from '@ohos.window';
import { bindAppContext } from '../core/db/Database';
import { appStore } from '../viewmodel/AppStore';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    bindAppContext(this.context);
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index', (err) => {
      if (err) {
        console.error('loadContent failed', JSON.stringify(err));
        return;
      }
      // Warm up the store once the main page is mounted.
      appStore.refreshFolders().catch((e: Error) => console.error('refreshFolders', e));
      appStore.refreshTags().catch((e: Error) => console.error('refreshTags', e));
      appStore.refreshNotes().catch((e: Error) => console.error('refreshNotes', e));
    });
  }

  onDestroy(): void {
  }

  onForeground(): void {
  }

  onBackground(): void {
  }
}
