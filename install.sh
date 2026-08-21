#!/usr/bin/env bash
# ============================================================
#  RustDesk ID Server - Magisk 模块一键安装脚本 (Linux/macOS)
#  自动将 hbbs ID 服务器（可选 hbbr 中继）安装到已 root 且装有 Magisk 的安卓手机。
#
#  用法:
#    ./install.sh                      # 自动生成随机 key 并安装
#    ./install.sh --key mykey123       # 指定 key
#    ./install.sh --relay              # 启用中继服务器
#    ./install.sh --serial 0123456     # 指定设备序列号
#    ./install.sh --out-only mod.zip   # 只打包不安装
#    ./install.sh --force              # 强制覆盖安装
# ============================================================
set -euo pipefail

# ---------- 参数 ----------
KEY=""
SERIAL=""
RELAY=0
OUT_ONLY=""
FORCE=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --key) KEY="$2"; shift 2 ;;
    --serial) SERIAL="$2"; shift 2 ;;
    --relay) RELAY=1; shift ;;
    --out-only) OUT_ONLY="$2"; shift 2 ;;
    --force) FORCE=1; shift ;;
    -h|--help) grep -E '^\s+#|用法|--key|--relay|--serial|--out-only|--force' "$0" | sed 's/^#//'; exit 0 ;;
    *) echo "未知参数: $1"; exit 1 ;;
  esac
done

# ---------- 路径 ----------
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# install.sh 位于模块根目录内，根目录即脚本所在目录
ROOT="$SCRIPT_DIR"
ENV_FILE="$ROOT/config/env.sh"

green(){ echo -e "\033[0;32m$1\033[0m"; }
cyan(){ echo -e "\033[0;36m==> $1\033[0m"; }
yellow(){ echo -e "\033[0;33m    [!] $1\033[0m"; }

# ---------- 1. 定位 adb ----------
cyan "定位 adb"
ADB="$(command -v adb || true)"
if [[ -z "$ADB" ]]; then
  yellow "未找到 adb。请安装 Android platform-tools 后重试。"
  yellow "  macOS:  brew install --cask android-platform-tools"
  yellow "  Linux:  sudo apt install adb  (或 android-tools-adb)"
  exit 1
fi
green "adb: $ADB"

# ---------- 2. 选择设备 ----------
cyan "检测设备"
"$ADB" start-server >/dev/null 2>&1
sleep 0.5
if [[ -n "$SERIAL" ]]; then
  DEVS=("$SERIAL")
else
  mapfile -t DEVS < <("$ADB" devices | awk '$2=="device"{print $1}')
fi
if [[ ${#DEVS[@]} -eq 0 ]]; then
  yellow "未检测到已授权的安卓设备。请开启 USB 调试并授权。"
  exit 1
fi
DEV="${DEVS[0]}"
if [[ ${#DEVS[@]} -gt 1 ]]; then
  echo "检测到多个设备:"
  for i in "${!DEVS[@]}"; do echo "  [$i] ${DEVS[$i]}"; done
  read -rp "选择设备序号 [默认 0]: " sel
  [[ "$sel" != "" && "$sel" -lt "${#DEVS[@]}" ]] && DEV="${DEVS[$sel]}"
fi
green "目标设备: $DEV"
"$ADB" -s "$DEV" wait-for-device

# ---------- 3. 检查 root / Magisk ----------
cyan "检查 root (su) 与 Magisk"
if [[ "$("$ADB" -s "$DEV" shell "su -c 'id -u'" 2>/dev/null | tr -d '\r')" != "0" ]]; then
  yellow "设备未获得 root 权限。请确认 Magisk 已安装且已授权。"
  exit 1
fi
green "root 可用"
if "$ADB" -s "$DEV" shell "su -c 'test -e /data/adb/magisk/magisk'" 2>/dev/null; then
  green "Magisk 已安装"
else
  yellow "未检测到 Magisk，请先安装。"
  exit 1
fi

# ---------- 4. 生成 key ----------
cyan "配置 key"
if [[ -z "$KEY" ]]; then
  KEY="$(tr -dc 'A-HJ-NP-Za-km-z2-9' < /dev/urandom | head -c 32)"
fi
green "服务器 key: $KEY"
yellow "请务必记录此 key，客户端需填入相同值。"

# ---------- 5. 写入配置 ----------
cyan "写入配置到 config/env.sh"
sed -i.bak "s|SERVER_KEY=\"[^\"]*\"|SERVER_KEY=\"$KEY\"|" "$ENV_FILE"
sed -i.bak "s|ENABLE_RELAY=[0-1]|ENABLE_RELAY=$RELAY|" "$ENV_FILE"
rm -f "$ENV_FILE.bak"
green "配置已写入"

# ---------- 6. 打包 ----------
cyan "打包 Magisk 模块"
ARCH="$("$ADB" -s "$DEV" shell "getprop ro.product.cpu.abi" 2>/dev/null | tr -d '\r')"
BIN_ARCH="arm64"
case "$ARCH" in
  *armeabi*|*armv7*) BIN_ARCH="arm" ;;
  *x86_64*) BIN_ARCH="x86_64" ;;
  *x86*) BIN_ARCH="x86" ;;
esac
echo "    设备架构: $ARCH -> 使用 $BIN_ARCH"
if [[ ! -f "$ROOT/bin/$BIN_ARCH/hbbs" ]]; then
  yellow "缺少 $ROOT/bin/$BIN_ARCH/hbbs 二进制。"
  exit 1
fi
STAGE="$(mktemp -d)"
TMP_ZIP="$STAGE/module.zip"
mkdir -p "$STAGE/bin"
cp "$ROOT/module.prop" "$ROOT/service.sh" "$ROOT/customize.sh" "$ROOT/uninstall.sh" "$ROOT/README.md" "$STAGE/"
cp -r "$ROOT/config" "$STAGE/config"
cp -r "$ROOT/bin/$BIN_ARCH" "$STAGE/bin/$BIN_ARCH"
# 打包，强制正斜杠，排除不需要的文件
( cd "$STAGE" && zip -rq -X "$TMP_ZIP" . -x '*.DS_Store' )
green "打包完成: $TMP_ZIP ($(du -h "$TMP_ZIP" | cut -f1))"

# ---------- 7. OutOnly ----------
if [[ -n "$OUT_ONLY" ]]; then
  cp "$TMP_ZIP" "$OUT_ONLY"
  rm -rf "$STAGE"
  green "仅打包完成: $OUT_ONLY"
  green "服务器 key: $KEY"
  exit 0
fi

# ---------- 8. 推送并部署 ----------
cyan "推送到手机并部署"
REMOTE="/data/local/tmp/rustdesk-module.zip"
"$ADB" -s "$DEV" push "$TMP_ZIP" "$REMOTE" >/dev/null
if [[ "$FORCE" == "1" ]]; then
  "$ADB" -s "$DEV" shell "su -c 'rm -rf /data/adb/modules/rustdesk_id_server'"
else
  "$ADB" -s "$DEV" shell "su -c 'rm -f /data/adb/modules/rustdesk_id_server/{service.sh,bin,config,customize.sh,uninstall.sh,module.prop} -r'"
fi
"$ADB" -s "$DEV" shell "su -c 'mkdir -p /data/adb/modules/rustdesk_id_server && unzip -o $REMOTE -d /data/adb/modules/rustdesk_id_server && chmod 755 /data/adb/modules/rustdesk_id_server/service.sh /data/adb/modules/rustdesk_id_server/customize.sh /data/adb/modules/rustdesk_id_server/uninstall.sh /data/adb/modules/rustdesk_id_server/bin/*/hbbs /data/adb/modules/rustdesk_id_server/bin/*/hbbr'"
"$ADB" -s "$DEV" shell "su -c 'rm -f $REMOTE'"
rm -rf "$STAGE"
green "模块已部署到 /data/adb/modules/rustdesk_id_server/"

# ---------- 9. 启动 ----------
cyan "启动 hbbs 服务"
"$ADB" -s "$DEV" shell "su -c 'sh /data/adb/modules/rustdesk_id_server/service.sh'" >/dev/null 2>&1 || true
sleep 2

# ---------- 10. 校验 ----------
cyan "校验运行状态"
if "$ADB" -s "$DEV" shell "su -c 'pgrep -x hbbs'" >/dev/null 2>&1; then
  green "hbbs 运行中"
  "$ADB" -s "$DEV" shell "su -c 'ss -tulnp 2>/dev/null | grep hbbs'"
else
  yellow "hbbs 未运行，请查看 /data/local/tmp/rustdesk/rustdesk.log"
fi
IP="$("$ADB" -s "$DEV" shell "ip -4 addr show wlan0 2>/dev/null" 2>/dev/null | grep 'inet ' | awk '{print $2}' | cut -d/ -f1 | head -1)"

echo ""
green "============================================"
green "   RustDesk 服务器部署成功！"
green "   ============================================"
echo "   服务器 key : $KEY"
[[ -n "$IP" ]] && echo "   手机 IP    : $IP"
echo "   ID 服务器  : 手机 IP (如 $IP)"
echo "   Key(公钥)  : $KEY"
[[ "$RELAY" == "1" ]] && echo "   中继服务器 : 已启用 (同 IP)" || echo "   中继服务器 : 未启用"
green "   ============================================"
yellow "  客户端配置时填入上述 ID 服务器地址与 Key 即可连接。"
yellow "  公网访问需在路由器转发 21116(TCP+UDP)、21115(TCP)、(中继则 21117/TCP) 到手机。"