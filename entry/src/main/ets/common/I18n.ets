// 应用级字符串表。当前默认提供简体中文文案。
//
// 使用方式：
//   import { I18n } from '../common/I18n';
//   Text(I18n.appTitle)
//
// 设计目标：
//   - 改文案时只动这一处，不需要全工程搜索替换
//   - 后续接系统 locale 切换、多语种时，把这里替换成查表函数即可
// 文案尽量贴近 Joplin 官方 [zh_CN] locale（packages/app-mobile/locales/zh_CN.json），
// 并参照 OpenHarmonyPCDeveloper/ohos_joplin 的实际中文交互习惯调整长文案。

export class I18n {
  // 应用
  static readonly appTitle: string = 'Joplin';
  static readonly appSubtitle: string = 'HarmonyOS 笔记';

  // 通用
  static readonly confirm: string = '确认';
  static readonly cancel: string = '取消';
  static readonly save: string = '保存';
  static readonly delete: string = '删除';
  static readonly edit: string = '编辑';
  static readonly back: string = '返回';
  static readonly done: string = '完成';
  static readonly close: string = '关闭';
  static readonly yes: string = '是';
  static readonly no: string = '否';
  static readonly loading: string = '加载中…';
  static readonly refreshing: string = '刷新中…';
  static readonly refresh: string = '刷新';
  static readonly untitled: string = '无标题';
  static readonly created: string = '创建于';
  static readonly updated: string = '更新于';
  static readonly search: string = '搜索';
  static readonly more: string = '更多';

  // 主导航
  static readonly tabNotes: string = '笔记';
  static readonly tabNotebooks: string = '笔记本';
  static readonly tabTags: string = '标签';
  static readonly tabSettings: string = '设置';

  // 主页 / 笔记列表
  static readonly notesTitle: string = '全部笔记';
  static readonly notebooksTitle: string = '笔记本';
  static readonly noNotes: string = '暂无笔记';
  static readonly createFirstNote: string = '点击右下角新建第一篇笔记';
  static readonly noNotebooks: string = '暂无笔记本';
  static readonly createFirstNotebook: string = '点击右下角新建第一个笔记本';
  static readonly newNote: string = '新建笔记';
  static readonly newNotebook: string = '新建笔记本';
  static readonly searchHint: string = '搜索笔记标题或内容';
  static readonly searchResultsEmpty: string = '没有匹配的笔记';
  static readonly pullToRefresh: string = '下拉刷新';

  static noteCount(n: number): string {
    return n + ' 条笔记';
  }

  static noteDeleteConfirm(title: string): string {
    return `确定删除笔记 “${title}”？删除后将在下次同步时从服务器移除。`;
  }
  static readonly noteDeleted: string = '笔记已删除';
  static readonly notebookDeleted: string = '笔记本已删除';
  static readonly trashTitle: string = '回收站';
  static readonly trashEmpty: string = '回收站为空';
  static readonly attachFile: string = '添加附件';
  static readonly attachImage: string = '添加图片';

  // 笔记本
  static readonly notebookRename: string = '重命名笔记本';
  static readonly notebookDelete: string = '删除笔记本';
  static notebookDeleteConfirm(name: string): string {
    return `确定删除笔记本 “${name}”？`;
  }
  static notebookDeleteKeepHint(n: number): string {
    return `笔记本内的 ${n} 条笔记将移动到根目录。`;
  }
  static readonly notebookDeleteAlsoNotes: string = '同时删除笔记本内所有笔记';
  static readonly pickANotebook: string = '请选择一个笔记本';
  static readonly untitledNotebook: string = '未命名笔记本';

  // 移动笔记
  static readonly noteMoveTo: string = '移动到笔记本';
  static readonly moveToRoot: string = '全部笔记（根目录）';
  static readonly noteMovedToast: string = '已移动';

  // 标签
  static readonly tagsTitle: string = '标签';
  static readonly noTags: string = '暂无标签';
  static readonly createFirstTag: string = '在笔记编辑器内通过「添加标签」按钮创建';
  static readonly attachTag: string = '添加标签';
  static readonly attachTagHint: string = '输入标签名称后点击「添加标签」';
  static readonly tagAlreadyAttached: string = '已附加此标签';
  static readonly noAttachedTags: string = '该笔记暂无标签';
  static readonly renameTag: string = '重命名标签';
  static readonly tagRenameHint: string = '输入新的标签名称';
  static readonly tagDeleteKeepNoteHint: string = '删除标签后，已打该标签的笔记会保留，仅移除标签关联';
  static readonly newTagNameExists: string = '已存在同名标签';

  // 编辑器
  static readonly editorTitlePlaceholder: string = '标题';
  static readonly editorBodyPlaceholder: string = '在这里开始书写…';
  static readonly editorSave: string = '保存';
  static readonly editorTagEmpty: string = '请输入标签';
  static readonly editorSavedToast: string = '已保存';
  static readonly editorDiscardConfirm: string = '修改尚未保存，确定退出？';
  static readonly editorPreview: string = '预览';
  static readonly editorEdit: string = '编辑';
  static readonly editorMarkdown: string = 'Markdown 编辑';
  static editorWordCount(w: number, c: number): string {
    return `${w} 字 · ${c} 字符`;
  }
  static readonly editorAttachments: string = '附件';
  static readonly editorNoBody: string = '该笔记暂无内容';

  // 设置页
  static readonly settingsTitle: string = '设置';
  static readonly settingsAccount: string = '账号';
  static readonly settingsSync: string = '同步';
  static readonly settingsAppearance: string = '外观';
  static readonly settingsAdvanced: string = '高级';
  static readonly settingsAbout: string = '关于';

  // 同步
  static readonly syncTitle: string = '同步设置';
  static readonly syncTarget: string = 'Joplin Server 目标';
  static readonly syncUrlLabel: string = 'Joplin Server URL';
  static readonly syncUrlPlaceholder: string = 'https://your.joplin.server';
  static readonly syncEmailLabel: string = '邮箱';
  static readonly syncPasswordLabel: string = '密码';
  static readonly syncSave: string = '保存';
  static readonly syncNow: string = '立即同步';
  static readonly syncForceResync: string = '强制全量重新同步';
  static readonly syncInProgress: string = '同步中…';
  static readonly syncStatus: string = '同步状态';
  static readonly syncIdle: string = '等待同步';
  static syncPushed(n: number): string { return `已上传 ${n} 项`; }
  static syncPulled(n: number): string { return `已下载 ${n} 项`; }
  static syncDeleted(n: number): string { return `已删除 ${n} 项`; }
  static syncFailed(reason: string): string { return `同步失败：${reason}`; }
  static readonly syncNotConfigured: string = '请先在设置中配置同步服务器';
  static syncLoginFailed(reason: string): string { return `登录失败：${reason}`; }

  // 同步进度（由 Synchronizer 经 SyncProgress 上报，直接显示在设置页）
  static readonly syncConnecting: string = '正在连接服务器…';
  static readonly syncPushing: string = '正在上传本地更改…';
  static readonly syncPushingDeletions: string = '正在上报本地删除…';
  static readonly syncFetching: string = '正在拉取远端更改…';
  static readonly syncComplete: string = '同步完成';
  static syncPushFailed(id: string, reason: string): string { return `上传失败（${id}）：${reason}`; }
  static syncApplying(n: number): string { return `正在应用 ${n} 条远端更改…`; }
  static syncApplyFailed(id: string, reason: string): string { return `应用远端更改失败（${id}）：${reason}`; }
  static readonly syncNever: string = '从未同步';
  static readonly syncForceConfirmTitle: string = '强制全量重新同步';
  static readonly syncForceConfirmMessage: string =
    '将清空本地同步游标并重新拉取所有笔记。仅当你确认当前账户的同步数据与本地不一致时使用。是否继续？';
  static readonly syncForceConfirmAction: string = '清空并重新同步';
  static readonly syncEncryptionTitle: string = '加密';
  static readonly syncEncryptionNotConfigured: string = '未配置端到端加密';

  // 同步描述 / 提示
  static readonly syncFooter: string =
    'joplin-hap 通过与官方 Joplin 完全一致的 SQLite schema、笔记序列化格式与同步协议，' +
    '保证同一账号可以在手机和桌面端双向无缝同步。';
  static readonly syncHelpDocTitle: string = '如何搭建 Joplin Server？';
  static readonly syncHelpDoc: string =
    'joplin-hap 兼容所有上游同步实现——Joplin Server、Nextcloud（WebDAV）、Dropbox、OneDrive、本地文件夹。' +
    '在「Joplin Server URL」填写完整的 https 地址，然后在桌面端用同一账号登录即可。';

  // 外观
  static readonly themeTitle: string = '主题';
  static readonly themeLight: string = '明亮';
  static readonly themeDark: string = '暗黑';
  static readonly themeOLED: string = '纯黑护眼';
  static readonly themeFollowSystem: string = '跟随系统';

  // 通用
  static readonly poweredBy: string = '由 ArkTS / ArkUI 强力驱动';
  static readonly errorTitle: string = '出错啦';
  static readonly retry: string = '重试';
  static readonly warning: string = '警告';
  static readonly info: string = '提示';

  // 关于页
  static readonly versionTitle: string = '版本';
  static readonly sourceTitle: string = '源代码';
  static readonly sourceOpen: string = '在 GitHub 查看 / 提 Issue';
  static readonly licenseTitle: string = '许可证';
  static readonly licenseValue: string = 'AGPL-3.0';

  // 标签管理弹窗
  static readonly tagDeleteConfirm: string = '删除该标签？';
}
