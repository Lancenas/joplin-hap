# 构建指南

## 环境

| 项 | 版本 / 路径（macOS 示例） |
|---|---|
| DevEco Studio | 6.x，`/Applications/DevEco-Studio.app` |
| HarmonyOS SDK | API 24 (6.1.1)，`~/Library/Huawei/Sdk/<SdkDir>` |
| JDK | DevEco 自带 JBR 21：`/Applications/DevEco-Studio.app/Contents/jbr/Contents/Home` |
| hvigor | 6.24.4，`/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw` |
| hdc | `$DEVECO_SDK_HOME/default/openharmony/toolchains/hdc` |

## 一条命令

```bash
bash scripts/dev-build.sh                # debug HAP
bash scripts/dev-build.sh debug install  # 构建并安装到设备
bash scripts/dev-build.sh release        # release HAP
```

脚本做的事：定位 JDK → 定位 SDK → 从 `~/.ohos/config` 读调试证书 → 解析 profile 绑定的 bundleName → 临时写入 `build-profile.json5` → 构建 → 拷贝产物到 `dist/` → 无条件还原配置文件（`trap EXIT`，即便中途失败也会还原）。

## 手动构建

```bash
export JAVA_HOME="/Applications/DevEco-Studio.app/Contents/jbr/Contents/Home"
export PATH="$JAVA_HOME/bin:$PATH"
export DEVECO_SDK_HOME="$HOME/Library/Huawei/Sdk/HarmonyOS-NEXT2"

/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw \
  --no-daemon assembleHap -p product=default -p buildMode=debug
```

产物：`entry/build/default/outputs/default/entry-default-signed.hap`

安装：

```bash
HDC="$DEVECO_SDK_HOME/default/openharmony/toolchains/hdc"
"$HDC" list targets
"$HDC" -t <设备号> install -r dist/joplin-hap-0.1.0-debug.hap
"$HDC" -t <设备号> shell aa start -a EntryAbility -b <bundleName>
```

---

## 踩过的坑

### 1. `DEVECO_SDK_HOME` 指向层级错误

SDK 目录结构是 `<SdkDir>/default/{openharmony,hms}`。`DEVECO_SDK_HOME` 必须指向 **含 `default/` 的那一层**，不是 `default` 本身，也不是再上一层。

如果你的 SDK 实际落在 `~/Library/Huawei/Sdk/HarmonyOS-NEXT-DP1/default`，而 hvigor 又要求路径形如 `.../<name>/default`，可以建软链：

```bash
ln -s ~/Library/Huawei/Sdk/<实际目录> ~/Library/Huawei/Sdk/HarmonyOS-NEXT2
export DEVECO_SDK_HOME="$HOME/Library/Huawei/Sdk/HarmonyOS-NEXT2"
```

### 2. `PackageHap` 报 `00308018 Unknown Error`

```
> hvigor ERROR: Failed :entry:default@PackageHap...
> hvigor ERROR: Error Code: 00308018 Unknown Error
> hvigor ERROR: Error: Tools execution failed.
```

**这个 "Unknown Error" 会吞掉真实原因。** 去掉日志过滤重跑，才会看到：

```
The operation couldn't be completed. Unable to locate a Java Runtime.
```

`PackageHap` 调的是 Java 打包工具（`app_packing_tool.jar`）。macOS 上如果没装独立 JDK，`/usr/libexec/java_home` 找不到运行时就会失败。用 DevEco 自带的 JBR 即可：

```bash
export JAVA_HOME="/Applications/DevEco-Studio.app/Contents/jbr/Contents/Home"
```

> 教训：hvigor 的 `Unknown Error` 一律先看完整日志，不要 grep。

### 3. `SignHap` 报 `00303074 Configuration Error`

```
Error Message: The bundleName in app.json5/hvigorfile.ts does not match
the bundleName in the generated SigningConfigs.
```

HarmonyOS 的**调试 profile（`.p7b`）与 bundleName 强绑定**。可以直接读出里面绑的包名：

```bash
strings ~/.ohos/config/default_harmony_*.p7b \
  | sed -n 's/.*"bundle-name":"\([^"]*\)".*/\1/p'
```

profile 里还能看到有效期（通常 14 天）和已授权的设备 UDID 列表：

```json
{"type":"debug",
 "bundle-info":{"bundle-name":"...","apl":"normal"},
 "validity":{"not-before":...,"not-after":...},
 "debug-info":{"device-ids":["..."],"device-id-type":"udid"}}
```

两种解法：

- **推荐**：在 DevEco Studio 里为你自己的 bundleName 重新执行自动签名，生成匹配的 profile
- **临时**：在 `build-profile.json5` 的 product 里加 `bundleName` 覆盖（`scripts/dev-build.sh` 会自动这么做并给出警告）

```json5
"products": [
  {
    "name": "default",
    "signingConfig": "default",
    "bundleName": "<profile 里绑定的包名>",   // product 级覆盖 app.json5
    ...
  }
]
```

### 4. 签名配置不要入库

`signingConfigs.material` 里含本机绝对路径和 keystore 口令。本仓库的 `build-profile.json5` 提交的是 `signingConfigs: []`，口令放在被 gitignore 的 `build-profile.local.json5`，构建时由脚本临时注入、构建后还原。

### 5. `aa start` 报 `10106102`

```
The device screen is locked during the application launch, unlock screen failed.
Error cause: The current mode is developer mode, and the screen cannot be unlocked automatically
```

设备锁屏时无法通过 hdc 拉起应用。**先解锁手机**，再执行 `aa start`，或直接在桌面点图标。安装（`hdc install`）不受锁屏影响。

### 6. Shell 脚本里变量名紧跟中文标点

```bash
log "buildMode=$BUILD_MODE）..."     # ✗ set -u 下报 BUILD_MODE\xef...: unbound variable
log "buildMode=${BUILD_MODE}）..."   # ✓
```

某些 locale 下 bash 会把多字节字符当成变量名的一部分。中文提示信息里的变量一律用 `${}` 包起来。

---

## ArkTS 严格模式限制备忘

移植 TypeScript 代码时，这些写法 ArkTS 一律拒绝。踩过一轮共 56 个编译错误，归纳如下：

| 规则 | 被拒绝的写法 | 替代方案 |
|---|---|---|
| `arkts-no-conditional-types` | `type X<T> = T extends A ? B : C` | 拆成具体类型或函数重载 |
| `arkts-no-is` | `function f(x): x is T` | 返回 `boolean`，调用方自己收窄 |
| `arkts-no-indexed-signatures` | `interface Q { [k: string]: T }` | 用 `type Q = Record<string, T>`（Record 可索引） |
| `arkts-identifiers-as-prop-names` | `{ 'Content-Type': v }` | 先建对象再 `obj[KEY] = v`，KEY 为常量 |
| `arkts-no-props-by-index` | `classInstance['field']` | 显式字段访问 |
| `arkts-no-structural-typing` | 结构相同即可赋值 | 显式构造目标类型 |
| `arkts-no-destruct-decls` | `const [a, b] = s.split('_')` | `const p = s.split('_'); p[0]; p[1]` |
| `arkts-no-untyped-obj-literals` | 缺字段的对象字面量 | 用 class 构造函数或工厂函数 |
| — | `str.replace(re, (m) => ...)` 回调重载 | 手写字符扫描器 |
| — | `globalThis as Record<string, T>` | 模块级变量 + 显式 bind/resolve |

另外两个 API 细节：

- `@ohos.util` 的 `util` 是 **default export**：`import util from '@ohos.util'`，UUID 为 `util.generateRandomUUID(false)`
- 页面 struct 不能叫 `Search`（保留名，报 `10905237`），本项目改名 `NoteSearchPage`

## 编译警告

当前构建有约 24 条警告，均为已知且无害：

- `Function may throw exceptions. Special handling is required.` —— `relationalStore` 同步 API 的提示，调用处已有 try/catch
- `'pushUrl' / 'getParams' / 'back' has been deprecated.` —— `@ohos.router` 在 API 24 被标记弃用，官方推荐迁到 `Navigation` + `NavPathStack`。已列入路线图，功能不受影响。
