# 架构说明

## 为什么是重写而不是适配

官方 Joplin 移动端（`packages/app-mobile`）是 React Native 应用，依赖链包括 JSC/Hermes 引擎、`react-native-sqlite-storage`、`react-native-fs` 等原生模块。HarmonyOS NEXT 不提供 RN 运行时，逐个补齐原生桥接的工作量远大于按契约重写。

因此本项目的策略是：**放弃代码复用，保留数据契约。** 只要 SQLite schema、条目序列化格式、同步协议三者与上游一致，就能和官方客户端互操作。

```
                    ┌─────────────────────────┐
                    │     Joplin Server       │
                    │  (自建 / joplin cloud)  │
                    └───────────┬─────────────┘
                                │ 同一套 REST + 同一套条目格式
                ┌───────────────┼───────────────┐
                │               │               │
        ┌───────▼──────┐ ┌──────▼──────┐ ┌──────▼──────┐
        │ Joplin 桌面端│ │ Joplin 移动 │ │ joplin-hap  │
        │  Electron/TS │ │React Native │ │ ArkTS/ArkUI │
        └──────────────┘ └─────────────┘ └─────────────┘
```

## 分层

```
pages/  ArkUI 声明式 UI，@Entry/@Component
   │    只做渲染与事件，不含业务逻辑
   ▼
viewmodel/  AppStore（@Observed 全局状态）+ RouteParams（类型化路由）
   │
   ▼
core/services/Repositories.ets  仓储层：CRUD + 同步队列维护
   │
   ├──► core/db/         SQLite（relationalStore）
   ├──► core/sync/       序列化 + REST + 同步主循环
   └──► core/markdown/   渲染
```

## 数据层

`core/db/Database.ets` 按 `packages/lib/JoplinDatabase.ts` 复刻表结构：

| 表 | 用途 |
|---|---|
| `folders` | 笔记本 |
| `notes` | 笔记（含 `is_todo` / `todo_due` / 经纬度 / `order` 等全部字段） |
| `tags` / `note_tags` | 标签与多对多关联 |
| `resources` | 附件元数据（blob 存 `.resource/<id>`，按需下载缓存，本地新建随同步上传） |
| `sync_items` | 同步状态：`sync_time=0` 表示待上传 |
| `deleted_items` | 本地删除待上报 |
| `settings` | 键值配置，键名沿用 Joplin（如 `sync.9.path`） |
| `schema_meta` | 本项目自加，记录 schema 版本用于迁移 |

索引也一并复刻（`notes_parent_id`、`notes_updated_time`、`folders_title` 等），保证在同等数据量下查询特性一致。

时间统一用 **毫秒 epoch** 存库（与 Joplin 一致），只在序列化为条目文本时转成 `YYYY-MM-DDThh:mm:ss.SSSZ`。

## 条目序列化

Joplin 在服务端存的不是 JSON，而是这种文本格式（`BaseItem.serialize()`）：

```
笔记标题

正文第一行
正文第二行

id: 8f4c1a2b3d4e5f60718293a4b5c6d7e8
parent_id: a1b2c3d4e5f60718293a4b5c6d7e8f90
created_time: 2026-08-23T06:12:34.567Z
updated_time: 2026-08-23T06:12:34.567Z
is_conflict: 0
...
type_: 1
```

规则：第一行是 title，空行后是 body，最后一段是 `key: value` 元数据块，`type_` 必须是最后一项。folder/tag 等没有 body 的类型只有 title + 元数据块。

`ItemSerializer.ets` 里为每种类型写了独立的 `serializeXxx()`，逐字段构造 `PropRecord`（`Record<string, string | number | null>`），而不是反射遍历对象 —— 因为 ArkTS 不允许把 class 实例 cast 成 `Record` 做通用字段遍历。反向解析 `unserializeItem()` 返回 `{ typeId, raw }`，再由 `recordToNote/Folder/Tag/...` 投影成实体。

## 同步协议

`Synchronizer.run()` 三段式，与上游 `Synchronizer.ts` 的 primitive 一致：

```
1. update_remote  查 sync_items 里 sync_time=0 的条目
                  → PUT api/items/root:/<id>.md:/content
                  → 更新 sync_time

2. delete_remote  查 deleted_items
                  → 优先 POST api/items/batch_delete（多数 Joplin Server 版本支持）
                  → 若服务端返回 Not allowed: POST，降级为逐条 DELETE api/items/<id>
                  → 仅清除删除成功的行，失败的保留下次重试

3. delta          GET api/items/root:/children/delta?cursor=<游标>
                  → 逐条 GET 内容、unserialize、按 updated_time 判定后写库
                  → 游标存入 settings['sync.cursor']
```

认证走 `POST api/sessions`（邮箱+密码）拿 session id，之后所有请求带 `X-API-AUTH` 头。

### 防同步回环

关键设计：`Repositories` 里每个写方法都有 `track: boolean = true` 参数。

- 用户在 UI 里改笔记 → `upsert(note)`，`track=true` → 写 `sync_items` 标记待上传
- 同步器从远端拉到变更并写库 → `upsert(note, false)`，`track=false` → **不**标记待上传

没有这个开关的话，拉下来的每条远端变更都会被当作本地修改再推回服务端，形成无限往复。

### 同步结果的 UI 可见性

同步把数据写进本地 SQLite，但 UI 不会自动"看到"新数据，除非显式重读。`AppStore` 是 `@Observed` 单例，同步结束后 `Synchronizer.run()` 回调里会调 `appStore.refreshAll()`（依次 `refreshFolders` / `refreshTags` / `refreshNotes`），更新 `appStore.tags` 等数组，驱动 `@State store: AppStore` 持有的页面重渲染。

需要特别注意：**用 `aboutToAppear` 快照的页面（如 `TagList` 在 `aboutToAppear` 拷贝 `appStore.tags`）不会在同步后自动更新**。本项目在 `TagList` 上额外挂了 `onPageShow()` 每次页面显示都 `refreshFromStore()`，覆盖"同步时页面已打开、新标签不出现"的坑。若新增独立的只读列表页，也应优先用 `onPageShow` 而非仅靠 `aboutToAppear`。

### 冲突处理

当前策略是 last-write-wins：比较本地与远端的 `updated_time`，远端更新则覆盖本地。Joplin 原生的冲突笔记机制（复制一份到冲突笔记本、`is_conflict=1`）尚未实现，表字段已预留。

## Markdown 渲染

ArkTS 不支持 `String.prototype.replace(re, callback)` 的回调重载，`marked` 这类基于回调替换的库无法移植。`MarkdownRenderer.ets` 因此是手写的：

- **块级**：逐行扫描，用 `HEADING_RE` / `BULLET_RE` / `ORDERED_RE` / `RULE_RE` 匹配，`isBlockStart()` 判断段落边界
- **行内**：`renderInline()` 是字符级状态机，逐字符前进，遇到 `![`、`[`、`` ` ``、`~~`、`**`、`*`、`\` 时用 `readDelimited()` / `readLink()` 向前找配对符号

处理顺序有讲究：图片先于链接（`![` 是 `[` 的超集），`**` 先于 `*`（否则粗体被解析成两个空斜体）。

任务清单 `[ ]` / `[x]` 与 Joplin 的 `:/resourceId` 内部资源引用都在行内扫描器里处理。

`markdownToPlainText()` 用于列表页摘要，`markdownToHtml()` 用于预览。

## ArkTS 移植约束

ArkTS 是 TypeScript 的严格子集，禁用了运行时类型不确定的特性。移植时遇到的完整限制清单见 [BUILD.md](BUILD.md#arkts-严格模式限制备忘)，核心影响：

- 没有条件类型 / 类型谓词 → 类型收窄靠显式判断
- 接口不能有索引签名，但 `Record<K,V>` 可以 → 所有动态键值都走 `Record` 别名
- 对象字面量必须有声明类型且字段完整 → 大量改用 class 构造函数和工厂函数（`newNote()` / `newFolder()` 等）
- 不能解构声明 → `split()` 结果用下标访问
- 没有结构化类型 → 跨层传递必须显式构造目标类型

这些约束反过来让代码里的类型边界更清晰，代价是样板代码变多（约 3500 行 ArkTS 对应上游相关逻辑的规模）。

## 已知缺口

| 缺口 | 影响 |
|---|---|
| E2EE | 无法接入已启用端到端加密的 Joplin 账户 |
| 冲突笔记 | 并发编辑同一笔记会静默按时间戳覆盖 |
| 修订历史 | 无 `revisions` 表，不支持版本回溯 |
| `@ohos.router` 已弃用 | API 24 起标记弃用，需迁移到 `Navigation` + `NavPathStack` |
| 同步密码明文存储 | `sync.9.password` 以明文存于本地 `settings` 表（与官方客户端一致），尚未接系统 KeyStore |
| delta 逐条拉取 | 每条远端变更单独 GET item body（N+1），与官方客户端行为一致；首次全量同步大库较慢 |
