#!/system/bin/sh
# ============================================================
#  RustDesk ID Server - 开机自启脚本 (service.sh)
#  Magisk late_start 服务模式执行，适合启动守护进程
# ============================================================

MODDIR=${0%/*}

# 加载配置
if [ -f "$MODDIR/config/env.sh" ]; then
  . "$MODDIR/config/env.sh"
else
  # 兜底默认值
  SERVER_KEY="IlIIlIIllllIIlIIIlll"
  ENABLE_RELAY=0
  HBBS_PORT=21116
  HBBR_PORT=21117
  DATA_DIR="/data/local/tmp/rustdesk"
  LOG_FILE="$DATA_DIR/rustdesk.log"
fi

# 确保数据目录存在（root 权限）
mkdir -p "$DATA_DIR" 2>/dev/null
chmod 777 "$DATA_DIR" 2>/dev/null

# 设置 HOME 指向可写目录，避免 hbbs 尝试写入不可写位置
export HOME="$DATA_DIR"
export XDG_CONFIG_HOME="$DATA_DIR/.config"
# 预创建配置目录，避免首次启动报错
mkdir -p "$DATA_DIR/.config/rustdesk" 2>/dev/null

# 根据架构选择二进制目录
ARCH=$(getprop ro.product.cpu.abi)
case "$ARCH" in
  arm64-v8a|aarch64*) BIN_DIR="$MODDIR/bin/arm64" ;;
  armeabi-v7a|armv7*)  BIN_DIR="$MODDIR/bin/arm" ;;
  x86_64)              BIN_DIR="$MODDIR/bin/x86_64" ;;
  x86)                 BIN_DIR="$MODDIR/bin/x86" ;;
  *) echo "[rustdesk] $(date) 不支持的架构: $ARCH" >> "$LOG_FILE"; exit 1 ;;
esac

HBBS="$BIN_DIR/hbbs"
HBBR="$BIN_DIR/hbbr"

# 确保二进制可执行
chmod 755 "$HBBS" 2>/dev/null
[ -f "$HBBR" ] && chmod 755 "$HBBR" 2>/dev/null

# 二进制不存在则提示并退出
if [ ! -f "$HBBS" ]; then
  echo "[rustdesk] $(date) 未找到 hbbs 二进制: $HBBS" >> "$LOG_FILE"
  exit 1
fi

# 启动 hbbs（若未在运行）
if pgrep -x hbbs >/dev/null 2>&1; then
  echo "[rustdesk] $(date) hbbs 已在运行，跳过" >> "$LOG_FILE"
else
  cd "$DATA_DIR"
  echo "[rustdesk] $(date) 启动 hbbs (key=$SERVER_KEY, port=$HBBS_PORT)" >> "$LOG_FILE"
  # setsid 完全脱离会话，重定向所有 fd，避免阻塞 shell
  setsid env HOME="$DATA_DIR" XDG_CONFIG_HOME="$DATA_DIR/.config" "$HBBS" -k "$SERVER_KEY" -p "$HBBS_PORT" </dev/null >>"$LOG_FILE" 2>&1 &
fi

# 可选启动 hbbr 中继
if [ "$ENABLE_RELAY" = "1" ]; then
  if [ -f "$HBBR" ]; then
    if pgrep -x hbbr >/dev/null 2>&1; then
      echo "[rustdesk] $(date) hbbr 已在运行，跳过" >> "$LOG_FILE"
    else
      cd "$DATA_DIR"
      echo "[rustdesk] $(date) 启动 hbbr (port=$HBBR_PORT)" >> "$LOG_FILE"
      setsid env HOME="$DATA_DIR" "$HBBR" -p "$HBBR_PORT" </dev/null >>"$LOG_FILE" 2>&1 &
    fi
  else
    echo "[rustdesk] $(date) 未找到 hbbr 二进制，跳过中继" >> "$LOG_FILE"
  fi
fi

exit 0
