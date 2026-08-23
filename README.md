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
| Markdown 渲染 | 手写扫描器（ArkTS 不支持 `String.replace` 回调，无法直接移植 marked） |

也就是说：**用官方 Joplin 桌面端 + 自建 Joplin Server，可以和本应用双向同步。**

## 功能

- 笔记本（folders）树形组织、增删
- 笔记的创建 / 编辑 / 删除，Markdown 正文
- 标签（tags）管理与按标签筛选
- 全文搜索（标题 + 正文）
- Markdown 预览（标题、列表、任务清单、行内代码、粗体/斜体/删除线、链接、`:/resourceId` 资源引用）
- 与 Joplin Server 双向同步（增量 delta + 冲突时间戳判定）
- 数据本地落盘 SQLite，支持系统级备份（`backup_config.json`）

## 截图

> 待补充（当前版本刚打通首个可安装 HAP）

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
├── core/
│   ├── db/
│   │   ├── Database.ets          # Joplin 兼容 schema + 迁移
│   │   └── Query.ets             # 轻量查询封装
│   ├── models/Entities.ets       # Note/Folder/Tag/Resource + 工厂函数
│   ├── services/Repositories.ets # 仓储层，带 track 标志避免同步回环
│   ├── sync/
│   │   ├── ItemSerializer.ets    # Joplin 条目文本格式 编/解码
│   │   ├── JoplinApi.ets         # Joplin Server REST 客户端
│   │   └── Synchronizer.ets      # 同步主循环（上传→删除→拉取 delta）
│   ├── markdown/MarkdownRenderer.ets  # 手写 Markdown 扫描器
│   └── utils/                    # ID 生成、Joplin 时间格式、常量
├── viewmodel/
│   ├── AppStore.ets              # 全局状态
│   └── RouteParams.ets           # 类型化路由参数
└── pages/
    ├── Index.ets                 # 主页：侧栏（笔记本/标签）+ 笔记列表
    ├── NoteEditor.ets            # 编辑器 + 预览 + 标签
    ├── NoteList.ets              # 按笔记本/标签筛选的列表
    ├── NoteSearch.ets            # 全文搜索
    ├── TagList.ets               # 标签管理
    └── Settings.ets              # 同步配置
```

约 3500 行 ArkTS。

## 同步兼容性说明

- **已实现**：notes / folders / tags / note_tags 的双向同步，delta 增量游标持久化，本地删除上报（`batch_delete`）
- **未实现**：E2EE 端到端加密、resources 二进制附件上传下载、共享笔记本、修订历史
- 与官方客户端混用时，请先在桌面端做一次完整同步，再让本应用接入同一 Joplin Server

> ⚠️ 早期版本，请勿作为唯一数据副本。建议先在测试 Joplin Server 上验证。

## 与官方 Joplin 的差异

| | 官方移动端 | joplin-hap |
|---|---|---|
| 技术栈 | React Native | ArkTS / ArkUI 原生 |
| Markdown 渲染 | marked + WebView | 手写扫描器 → 纯文本/结构化预览 |
| 加密 | 支持 E2EE | 暂不支持 |
| 附件 | 支持 | 暂不支持 |
| 插件 | 支持 | 不支持 |

## 路线图

- [ ] Resources 附件上传/下载
- [ ] E2EE 端到端加密
- [ ] Markdown 富文本渲染（ArkUI 组件树而非纯文本）
- [ ] 笔记本拖拽排序、嵌套笔记本 UI
- [ ] 待办（is_todo）专用视图
- [ ] 冲突笔记的可视化处理

## 许可

本项目移植自 [laurent22/joplin](https://github.com/laurent22/joplin)（AGPL-3.0），因此同样以 **AGPL-3.0** 发布。详见 [LICENSE](LICENSE)。

Joplin 是 Laurent Cozic 及其贡献者的作品。本项目为独立的第三方移植，与上游官方无隶属关系。
