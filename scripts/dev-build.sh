#!/usr/bin/env bash
#
# joplin-hap 本地调试构建脚本
#
# 作用：
#   1. 自动定位 DevEco Studio 自带 JDK（hvigor 的 PackageHap 阶段依赖 Java）
#   2. 自动定位 HarmonyOS SDK（DEVECO_SDK_HOME 必须指向 .../<SdkDir>/default 的父级）
#   3. 从 ~/.ohos/config 读取 DevEco 自动签名生成的调试证书，临时注入 build-profile.json5
#   4. 从 .p7b profile 中解析出证书绑定的 bundleName；若与 AppScope/app.json5 不一致，
#      则以 product 级 bundleName 覆盖，使 SignHap 能通过（调试 profile 与包名强绑定）
#   5. 构建结束后无条件还原 build-profile.json5，保证不把本机口令写进仓库
#
# 用法：
#   bash scripts/dev-build.sh              # 构建 debug HAP
#   bash scripts/dev-build.sh release      # 构建 release HAP
#   bash scripts/dev-build.sh debug install # 构建并安装到已连接设备
#
set -euo pipefail

BUILD_MODE="${1:-debug}"
DO_INSTALL="${2:-}"

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROFILE="$PROJECT_ROOT/build-profile.json5"
BACKUP="$PROJECT_ROOT/build-profile.json5.bak"

log()  { printf '\033[36m[build]\033[0m %s\n' "$*"; }
warn() { printf '\033[33m[warn ]\033[0m %s\n' "$*"; }
die()  { printf '\033[31m[error]\033[0m %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------- 1. JDK
if [ -z "${JAVA_HOME:-}" ] || [ ! -x "${JAVA_HOME:-}/bin/java" ]; then
  for candidate in \
    "/Applications/DevEco-Studio.app/Contents/jbr/Contents/Home" \
    "$HOME/Applications/DevEco-Studio.app/Contents/jbr/Contents/Home" \
    "/opt/deveco-studio/jbr"
  do
    if [ -x "$candidate/bin/java" ]; then
      export JAVA_HOME="$candidate"
      break
    fi
  done
fi
[ -x "${JAVA_HOME:-}/bin/java" ] || die "找不到 JDK。hvigor 的 PackageHap 阶段需要 Java，请安装 JDK 17+ 或设置 JAVA_HOME。"
export PATH="$JAVA_HOME/bin:$PATH"
log "JAVA_HOME = $JAVA_HOME ($("$JAVA_HOME/bin/java" -version 2>&1 | head -1))"

# ---------------------------------------------------------------- 2. SDK
if [ -z "${DEVECO_SDK_HOME:-}" ] || [ ! -d "${DEVECO_SDK_HOME:-}/default" ]; then
  for candidate in \
    "$HOME/Library/Huawei/Sdk/HarmonyOS-NEXT2" \
    "$HOME/Library/Huawei/Sdk" \
    "/Applications/DevEco-Studio.app/Contents/sdk"
  do
    if [ -d "$candidate/default" ]; then
      export DEVECO_SDK_HOME="$candidate"
      break
    fi
  done
fi
[ -d "${DEVECO_SDK_HOME:-}/default" ] || die "找不到 HarmonyOS SDK。请设置 DEVECO_SDK_HOME 指向含 default/ 子目录的 SDK 路径。"
log "DEVECO_SDK_HOME = $DEVECO_SDK_HOME"

# ---------------------------------------------------------------- 3. hvigor
HVIGORW=""
for candidate in \
  "/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw" \
  "$HOME/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw" \
  "$PROJECT_ROOT/hvigorw"
do
  [ -x "$candidate" ] && HVIGORW="$candidate" && break
done
[ -n "$HVIGORW" ] || die "找不到 hvigorw。"

# ---------------------------------------------------------------- 4. 签名证书
CER="$(ls "$HOME"/.ohos/config/default_harmony_*.cer 2>/dev/null | head -1 || true)"
P12="$(ls "$HOME"/.ohos/config/default_harmony_*.p12 2>/dev/null | head -1 || true)"
P7B="$(ls "$HOME"/.ohos/config/default_harmony_*.p7b 2>/dev/null | head -1 || true)"

APP_BUNDLE="$(sed -n 's/.*"bundleName"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$PROJECT_ROOT/AppScope/app.json5" | head -1)"
PROFILE_BUNDLE=""

SIGNED=0
if [ -n "$CER" ] && [ -n "$P12" ] && [ -n "$P7B" ]; then
  SIGNED=1
  log "发现调试证书: $(basename "$CER")"
else
  warn "未在 ~/.ohos/config 找到调试证书，将产出 *未签名* HAP。"
  warn "请先在 DevEco Studio 中执行一次自动签名（File > Project Structure > Signing Configs）。"
fi

restore_profile() {
  if [ -f "$BACKUP" ]; then
    mv -f "$BACKUP" "$PROFILE"
    log "已还原 build-profile.json5"
  fi
}
trap restore_profile EXIT INT TERM

if [ "$SIGNED" = "1" ]; then
  # 从 keystore 读取 DevEco 写入的 key/store 口令。DevEco 把口令以密文形式写在
  # 已有工程的 build-profile.json5 里；若本机曾经自动签名过任意工程，可直接复用。
  # 优先顺序：环境变量 > 已存在的 build-profile.local.json5 > 报错提示。
  KEY_PASSWORD="${OHOS_KEY_PASSWORD:-}"
  STORE_PASSWORD="${OHOS_STORE_PASSWORD:-}"
  LOCAL_CFG="$PROJECT_ROOT/build-profile.local.json5"
  if [ -z "$KEY_PASSWORD" ] && [ -f "$LOCAL_CFG" ]; then
    KEY_PASSWORD="$(sed -n 's/.*"keyPassword"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p'   "$LOCAL_CFG" | head -1)"
    STORE_PASSWORD="$(sed -n 's/.*"storePassword"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$LOCAL_CFG" | head -1)"
  fi
  if [ -z "$KEY_PASSWORD" ] || [ -z "$STORE_PASSWORD" ]; then
    warn "缺少 keystore 口令，无法自动签名。请任选其一："
    warn "  a) export OHOS_KEY_PASSWORD=... OHOS_STORE_PASSWORD=..."
    warn "  b) 把 DevEco 自动签名生成的 signingConfigs 片段存为 build-profile.local.json5"
    warn "  c) 直接在 DevEco Studio 里点击 Build > Build Hap(s)"
    SIGNED=0
  fi
fi

if [ "$SIGNED" = "1" ]; then
  # 解析 profile 绑定的 bundleName
  PROFILE_BUNDLE="$(strings "$P7B" | sed -n 's/.*"bundle-name":"\([^"]*\)".*/\1/p' | head -1 || true)"
  log "app.json5 bundleName = $APP_BUNDLE"
  log "profile   bundleName = ${PROFILE_BUNDLE:-<解析失败>}"

  BUNDLE_OVERRIDE=""
  if [ -n "$PROFILE_BUNDLE" ] && [ "$PROFILE_BUNDLE" != "$APP_BUNDLE" ]; then
    warn "包名不一致 —— 调试 profile 与 bundleName 强绑定，本次构建将覆盖为 $PROFILE_BUNDLE"
    warn "如需使用 ${APP_BUNDLE}，请在 DevEco Studio 中为该包名重新生成调试 profile。"
    BUNDLE_OVERRIDE="\"bundleName\": \"$PROFILE_BUNDLE\","
  fi

  cp -f "$PROFILE" "$BACKUP"
  cat > "$PROFILE" <<EOF
{
  "app": {
    "signingConfigs": [
      {
        "name": "default",
        "type": "HarmonyOS",
        "material": {
          "certpath": "$CER",
          "keyAlias": "debugKey",
          "keyPassword": "$KEY_PASSWORD",
          "profile": "$P7B",
          "signAlg": "SHA256withECDSA",
          "storeFile": "$P12",
          "storePassword": "$STORE_PASSWORD"
        }
      }
    ],
    "products": [
      {
        "name": "default",
        "signingConfig": "default",
        $BUNDLE_OVERRIDE
        "targetSdkVersion": "6.1.1(24)",
        "compatibleSdkVersion": "6.1.1(24)",
        "runtimeOS": "HarmonyOS",
        "buildOption": {
          "strictMode": {
            "caseSensitiveCheck": true,
            "useNormalizedOHMUrl": true
          }
        }
      }
    ],
    "buildModeSet": [
      { "name": "debug" },
      { "name": "release" }
    ]
  },
  "modules": [
    {
      "name": "entry",
      "srcPath": "./entry",
      "targets": [
        { "name": "default", "applyToProducts": ["default"] }
      ]
    }
  ]
}
EOF
fi

# ---------------------------------------------------------------- 5. 构建
log "开始构建（buildMode=${BUILD_MODE}）..."
cd "$PROJECT_ROOT"
"$HVIGORW" --no-daemon assembleHap -p product=default -p "buildMode=$BUILD_MODE"

OUT_DIR="$PROJECT_ROOT/entry/build/default/outputs/default"
HAP="$OUT_DIR/entry-default-signed.hap"
[ -f "$HAP" ] || HAP="$OUT_DIR/entry-default-unsigned.hap"
[ -f "$HAP" ] || die "构建结束但未找到 HAP 产物。"

VERSION="$(sed -n 's/.*"versionName"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$PROJECT_ROOT/AppScope/app.json5" | head -1)"
mkdir -p "$PROJECT_ROOT/dist"
SUFFIX="debug"; [ "$BUILD_MODE" = "release" ] && SUFFIX="release"
case "$HAP" in *unsigned*) SUFFIX="$SUFFIX-unsigned";; esac
DEST="$PROJECT_ROOT/dist/joplin-hap-${VERSION}-${SUFFIX}.hap"
cp -f "$HAP" "$DEST"
log "产物: $DEST ($(du -h "$DEST" | cut -f1))"

# ---------------------------------------------------------------- 6. 安装
if [ "$DO_INSTALL" = "install" ]; then
  HDC="$DEVECO_SDK_HOME/default/openharmony/toolchains/hdc"
  [ -x "$HDC" ] || die "找不到 hdc: $HDC"
  TARGET="$("$HDC" list targets 2>/dev/null | grep -v '^\[' | head -1 | tr -d '\r')"
  [ -n "$TARGET" ] && [ "$TARGET" != "[Empty]" ] || die "没有检测到已连接的设备。"
  log "安装到设备 $TARGET ..."
  "$HDC" -t "$TARGET" install -r "$DEST"
  log "安装完成。请解锁设备后手动打开应用，或执行："
  log "  $HDC -t $TARGET shell aa start -a EntryAbility -b ${PROFILE_BUNDLE:-$APP_BUNDLE}"
fi

log "完成。"
