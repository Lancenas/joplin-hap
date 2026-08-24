# joplin-hap

**[Joplin](https://github.com/laurent22/joplin) 的 HarmonyOS NEXT 原生移植** —— 用 ArkTS / ArkUI 从零重写的笔记应用，保持与官方 Joplin 客户端的数据与同步兼容。

[![License: AGPL v3](https://img.shields.io/badge/License-AGPL_v3-blue.svg)](LICENSE)
![Platform](https://img.shields.io/badge/platform-HarmonyOS%20NEXT-black)
![API](https://img.shields.io/badge/API-24%20(6.1.1)-green)

---

## 这是什么

官方 Joplin 的移动端基于 React Native，无法直接跑在 HarmonyOS NEXT 上（RN 依赖的 JSC/Hermes + 原生桥接在鸿蒙生态缺失）。本项目**不是套壳，也不是 RN 适配层**，而是把 Joplin 的核心契约用 ArkTS 重新实现了一遍：

| 契约层 | 移植方式 |
|---|---|
| SQLite 表结构 | 按 `packages/lib/JoplinDatabase.ts` 1:1 复刻，官方客户端导出的数据可直接读 |
| 条目序列化格式 | 复刻 `BaseItem.serialize()` 的 `title\n\nbody\n\nkey: value…type_: N` 文本格式 |
| 同步协议 | 实现 Joplin Server REST（`api/sessions` / `api/items` / delta 增量游标 / batch_delete） |
| Markdown 渲染 | 手写扫描器产出 HTML（ArkTS 不支持 `String.replace` 回调，无法直接移植 marked），交 ArkWeb 渲染 |

也就是说：**用官方 Joplin 桌面端 + 自建 Joplin Server，可以和本应用双向同步。**

## 功能

- **简体中文界面**：全应用中文化（集中式 `I18n` 字符串表）
- **笔记本**：树形组织、新建、删除（默认把其中笔记移到根目录，弹窗可勾选「同时删除笔记本内所有笔记」级联删除）、侧栏显示每个笔记本的笔记数
- **笔记**：创建 / 编辑 / 删除 / 移动到其他笔记本（长按笔记 →「移动到笔记本」），Markdown 正文
- **标签**：管理、附加到笔记、按标签筛选。首页左分栏「标签」区带「+」入口进入标签管理页；管理页支持**新建 / 长按重命名 / 长按删除**（删除走确认弹窗，重命名/新建走输入弹窗），进入页面或同步后自动刷新
- **全文搜索**：标题 + 正文
- **Markdown 编辑**：工具栏快捷插入（粗体 / 斜体 / 删除线 / 标题 / 列表 / 待办 / 行内代码 / 代码块 / 链接 / 图片）
- **Markdown 预览**：Web 真实渲染（标题、列表、任务清单、代码块、粗斜体、删除线、引用、分割线、链接、**图片内嵌显示**）
- **附件**：图片在预览内嵌显示；PDF 等文件附件以卡片呈现，点击调起系统默认查看器打开（blob 按需下载并本地缓存）；**支持本地新建附件**（编辑器工具栏「🖼 图片」「📎 附件」选文件），随同步上传 blob + 元数据
- **回收站**：侧栏有「🗑 回收站」虚拟入口（显示已删笔记数）；同步 `deleted_time`，「全部笔记」与搜索自动隐藏已删笔记
- **同步**：与 Joplin Server 双向同步（delta 增量游标 + 冲突时间戳 + 删除上报 `batch_delete` + 网络失败自动重试）
- **本地存储**：SQLite 落盘，支持系统级备份（`backup_config.json`）

## 截图

> 待补充（功能已基本完整，待真机截图）

## 快速开始

### 环境要求

| 项 | 版本 |
|---|---|
| DevEco Studio | 6.x（内含 hvigor 6.24.4） |
| HarmonyOS SDK | API 24 / 6.1.1 |
| JDK | 17+（可直接用 DevEco 自带的 JBR 21） |
| 设备 | HarmonyOS NEXT 手机 / 平板 / 2in1 |

### 用 DevEco Studio 构建

1. `File > Open` 打开本项目根目录
2. `File > Project Structure > Signing Configs` → 勾选 **Automatically generate signature**（需登录华为开发者账号）
3. `Build > Build Hap(s)/APP(s) > Build Hap(s)`

### 用命令行构建

```bash
# 一条命令：定位 JDK/SDK → 注入本机调试证书 → 构建 → 签名 → 还原配置
bash scripts/dev-build.sh

# 构建并安装到已连接设备
bash scripts/dev-build.sh debug install

# release 包
bash scripts/dev-build.sh release
```

产物落在 `dist/joplin-hap-<版本>-<模式>.hap`。

脚本会自动处理三个易踩的坑：`PackageHap` 阶段需要 Java、`DEVECO_SDK_HOME` 必须指向含 `default/` 的父目录、调试 profile 与 `bundleName` 强绑定。细节见 [docs/BUILD.md](docs/BUILD.md)。

### 配置同步

应用内进入 **设置**，填入 Joplin Server 地址、邮箱、密码，点击「立即同步」。

设置项落在 Joplin 的标准 settings 键位（`sync.9.path` / `sync.9.username` / `sync.9.password`），与官方客户端语义一致。

## 项目结构

```
entry/src/main/ets/
├── common/
│   └── I18n.ets                  # 中文字符串表（集中式 i18n）
├── core/
│   ├── db/
│   │   ├── Database.ets          # Joplin 兼容 schema + 版本化迁移
│   │   └── Query.ets             # 轻量查询封装（错误附带 SQL 片段）
│   ├── models/Entities.ets       # Note/Folder/Tag/Resource + 工厂函数
│   ├── services/
│   │   ├── Repositories.ets      # 仓储层，带 track 标志避免同步回环
│   │   └── ResourceCache.ets     # 附件 blob 缓存 + 图片内嵌 + 系统打开
│   ├── sync/
│   │   ├── ItemSerializer.ets    # Joplin 条目文本格式 编/解码（防御式）
│   │   ├── JoplinApi.ets         # Joplin Server REST 客户端（含 blob 下载）
│   │   └── Synchronizer.ets      # 同步主循环（上传→删除→拉取 delta）
│   ├── markdown/MarkdownRenderer.ets  # 手写 Markdown 扫描器 → HTML
│   └── utils/                    # ID 生成、Joplin 时间格式、常量
├── viewmodel/
│   ├── AppStore.ets              # 全局状态 + 笔记本笔记数缓存
│   └── RouteParams.ets           # 类型化路由参数
└── pages/
    ├── Index.ets                 # 主页：侧栏（笔记本/标签）+ 笔记列表
    ├── NoteEditor.ets            # 编辑器 + Markdown 工具栏 + Web 预览 + 附件
    ├── NoteList.ets              # 按笔记本/标签筛选的列表
    ├── NoteSearch.ets            # 全文搜索
    ├── TagList.ets               # 标签管理
    └── Settings.ets              # 同步配置
```

约 5000 行 ArkTS。

## 同步兼容性说明

- **已实现**：notes / folders / tags / note_tags 的双向同步，delta 增量游标持久化，本地删除上报（`batch_delete`），resources 附件**双向同步**（元数据 + blob：下载内嵌/系统打开，本地新建**上传 blob + 元数据**），回收站（`deleted_time`）同步，网络瞬时失败自动重试。
- **未实现**：E2EE 端到端加密、共享笔记本、修订历史、冲突笔记可视化合并。
- 与官方客户端混用时，请先在桌面端做一次完整同步，再让本应用接入同一 Joplin Server；若同步异常，可在设置里点「强制全量重新同步」清空游标重来。

> ⚠️ 早期版本，请勿作为唯一数据副本。建议先在测试 Joplin Server 上验证。

### 同步协议踩坑记录（移植参考）

| 现象 | 根因 | 解法 |
|---|---|---|
| `Invalid path format: root:/delta` | delta 端点是 `api/items/root:/:/delta`（中间两个冒号） | 按官方 `file-api-driver-joplinServer.ts` 拼接 |
| `Not found: root:/<id>:` | item body 要走 `/content` 后缀，裸 `:id` 只返回元数据 | 用服务端 `item_name` 拼 `api/items/root:/<name>:/content` |
| `Missing required property: type_` | 防御式 `unserializeItem` 缺 `type_` 时返回 null 而非抛错 | 传入 `fallbackTypeId`，单条失败跳过不中断整批 |
| `Could not parse form (1): no parser found` | 上传 PUT body 发 `text/plain`，服务端 `formidable` 不识别 | 改 `application/octet-stream`（与官方一致） |
| `Failed to receive data from the peer` | 网络层瞬时失败（代理切断 / CDN RST） | 传输层错误线性退避重试，HTTP 非 2xx 直接抛 |
| `SQLite: Insert failed` | 加列迁移被 `if (stored!=='')` 守卫跳过 + 索引先于 ALTER | 版本号 +1 强制重迁移，迁移幂等无条件跑 |

## 与官方 Joplin 的差异

| | 官方移动端 | joplin-hap |
|---|---|---|
| 技术栈 | React Native | ArkTS / ArkUI 原生 |
| Markdown 渲染 | marked + WebView | 手写扫描器 → HTML → ArkWeb 渲染 |
| 加密 | 支持 E2EE | 暂不支持 |
| 附件 | 支持 | 支持（图片内嵌 + 文件系统打开 + 本地新建上传） |
| 回收站 | 支持 | 支持（`deleted_time` 同步 + 侧栏回收站入口） |
| 插件 | 支持 | 不支持 |

## 路线图

- [x] Resources 附件下载 / 图片内嵌预览 / 文件系统打开
- [x] 本地新建附件并上传 blob
- [x] Markdown 富文本渲染（Web 组件渲染 HTML）
- [x] 回收站同步 + 侧栏回收站入口
- [ ] E2EE 端到端加密
- [ ] 笔记本拖拽排序、嵌套笔记本 UI
- [ ] 待办（is_todo）专用视图
- [ ] 冲突笔记的可视化处理
- [ ] `@ohos.router` → `Navigation` + `NavPathStack` 迁移（API 24 已弃用 router）

## 更新日志

**2026-08-23**（首个端到端打通 → 功能基本完整）

- **首个可运行版本**：ArkTS/ArkUI 从零重写数据模型、SQLite 仓储、Joplin Server 同步协议，真机可安装运行。
- **同步协议修复链**：delta 端点路径 → item body 走 `/content` → 防御式 `unserializeItem`（`type_` 缺失容错）→ GET 不带 `Content-Type` → 上传改 `application/octet-stream` → 网络失败自动重试。
- **中文界面**：集中式 `I18n` 字符串表，6 个页面全中文化。
- **编辑与预览**：Markdown 格式化工具栏；预览升级为 Web 真实渲染（含图片内嵌）。
- **附件**：Resource 元数据同步 + blob 按需下载缓存；图片内嵌显示；PDF/文件点击调起系统查看器。
- **回收站**：`deleted_time` 字段 + 数据库版本化迁移，全部笔记隐藏已删、回收站可见。
- **删除**：笔记 / 笔记本手动删除，删除随同步上报（删除笔记本的「保留笔记移到根目录 / 级联删除」策略见 08-24 调整）。
- **关键排障**：Web 预览 `src=about:blank` 与 `loadData` 竞态导致空白 → 改响应式 src 单一导航；数据库迁移守卫导致 `deleted_time` 永久缺列 → 版本号强制重迁移。

**2026-08-24**

- **回收站侧栏**：Joplin 回收站是 `deleted_time>0` 笔记的虚拟视图（非同步文件夹），侧栏新增「🗑 回收站」虚拟入口 + 已删计数。
- **本地新建附件上传**：编辑器工具栏「🖼 图片」「📎 附件」选文件 → 建 Resource + 插入 `:/id` 引用 → 同步时先 PUT blob（`.resource/<id>`）再 PUT 元数据（`<id>.md`）上传到服务器。附件实现**双向同步**。
- **笔记移动**：长按笔记 →「移动到笔记本」，可选根目录或任意笔记本；`noteRepo.moveToFolder` 只改 `parent_id` 并标记待同步。
- **删除笔记本行为调整**：默认把笔记本内笔记移到根目录（不再直接级联删除）；确认弹窗可勾选「同时删除笔记本内所有笔记」走级联删除。同步器应用远端删除仍走级联（`folderRepo.delete(id, false)`）。
- **同步健壮性**：日志不再打印笔记正文（隐私）；同步进度消息全中文；delta 响应非 JSON 时告警；`batch_delete` 降级路径只清除删除成功的行，失败保留下次重试。
- **UI 弹窗修复**：`Index` 此前在同一组件上叠加多个 `bindContentCover` 导致互相串线（笔记「移动到笔记本」不弹窗、笔记本「删除」误弹移动列表），改为单一 `bindContentCover` + `coverKind` 状态机分发 createFolder / moveNote / deleteFolder。
- **踩坑**：`PhotoViewPicker` 此 API 版本为 0 参数构造（`new PhotoViewPicker()`，不传 context）。
- **标签管理页入口补齐**：`TagList` 此前为「死页面」——新建/重命名/删除功能已写好但无入口跳入；首页左分栏「标签」标题右侧加「+」按钮 `pushUrl` 进入标签管理页（路由已注册）。
- **标签管理功能**：标签管理页支持**新建**（「+ 标签」输入弹窗）、**长按重命名**（输入弹窗改 title 并标记同步）、**长按删除**（AlertDialog 确认，删 `tags` + `note_tags` + 记录同步删除）。
- **标签 UI 串线修复**：`TagList` 原 `ListItem.onClick`（进笔记列表）与 `bindMenu`（长按菜单）在同一组件互相抢事件，导致无论长按短按都误跳笔记列表 → 进列表改 `.gesture(TapGesture)` 与长按手势解耦；重命名/新建合并为单一 `bindContentCover` + `coverKind` 状态机消除浮层叠加串线；长按菜单新增「查看笔记」入口。
- **标签同步后 UI 不刷新**：`TagList` 用 `aboutToAppear` 快照，同步后页面已打开则看不到新标签 → 增加 `onPageShow` 自动 `refreshFromStore`；`AppStore.refreshTags` 增加标签数量诊断日志。抓包实锤标签双向同步链路正常（手机建「手机测试」PUT 成功、桌面建「desktoptest」手机 pullDelta 拉到并落库，本地库实测 7 个标签）。

## 许可

本项目移植自 [laurent22/joplin](https://github.com/laurent22/joplin)（AGPL-3.0），因此同样以 **AGPL-3.0** 发布。详见 [LICENSE](LICENSE)。

Joplin 是 Laurent Cozic 及其贡献者的作品。本项目为独立的第三方移植，与上游官方无隶属关系。
