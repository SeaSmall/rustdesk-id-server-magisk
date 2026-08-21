#!/system/bin/sh
# ============================================================
#  安装时运行 (customize.sh)
#  检查架构并提示需要放入的二进制
# ============================================================

ui_print "- 正在安装 RustDesk ID Server"

# 检测架构
ARCH=$(getprop ro.product.cpu.abi)
case "$ARCH" in
  arm64-v8a|aarch64*) BIN_ARCH="arm64" ;;
  armeabi-v7a|armv7*) BIN_ARCH="arm" ;;
  x86_64)             BIN_ARCH="x86_64" ;;
  x86)                BIN_ARCH="x86" ;;
  *) BIN_ARCH="unknown" ;;
esac

ui_print "  检测到架构: $ARCH"
ui_print "  请将 hbbs (和可选 hbbr) 放入:"
ui_print "    $MODPATH/bin/$BIN_ARCH/"

# 检查是否已有二进制
if [ -f "$MODPATH/bin/$BIN_ARCH/hbbs" ]; then
  ui_print "  检测到 hbbs 二进制 ✓"
else
  ui_print "  ! 未找到 hbbs 二进制"
  ui_print "  ! 模块可正常安装，但启动前必须放入二进制"
  ui_print "  ! 参见 README.md 如何获取/编译 arm64 二进制"
fi

ui_print "- 安装完成"
exit 0
