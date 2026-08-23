import BackupExtensionAbility from '@ohos.application.BackupExtensionAbility';

export default class EntryBackupAbility extends BackupExtensionAbility {
  async onBackup(): Promise<void> {
    // The default backup includes AppSandbox; joplin.db is stored under the
    // relationalStore sandbox folder which HarmonyOS picks up automatically.
  }

  async onRestore(): Promise<void> {
  }
}
