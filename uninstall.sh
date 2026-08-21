#!/system/bin/sh
# ============================================================
#  卸载时运行 (uninstall.sh)
#  停止服务并清理数据
# ============================================================

MODDIR=${0%/*}

# 加载配置以获取数据目录（若文件还在）
if [ -f "$MODDIR/config/env.sh" ]; then
  . "$MODDIR/config/env.sh"
fi

# 停止服务
pkill -f "hbbs" 2>/dev/null
pkill -f "hbbr" 2>/dev/null

# 清理数据目录（谨慎：包含密钥对，卸载时一并删除）
if [ -n "$DATA_DIR" ] && [ -d "$DATA_DIR" ]; then
  rm -rf "$DATA_DIR"
fi

exit 0
