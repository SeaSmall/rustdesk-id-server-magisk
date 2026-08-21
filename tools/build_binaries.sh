#!/bin/bash
# ============================================================
#  交叉编译 RustDesk hbbs/hbbr 为 Android arm64
#  在本机（Linux/macOS/WSL，装有 Rust）执行。
#  编译产物复制到模块 bin/arm64/ 目录。
# ============================================================
set -e

TARGET=aarch64-linux-android

echo "==> 1. 安装 rustup target"
rustup target add $TARGET

echo "==> 2. 配置 NDK 链接器（需已安装 Android NDK）"
# 修改为你的 NDK 路径
NDK=${ANDROID_NDK_HOME:-$HOME/Android/Sdk/ndk}
if [ -z "$(ls $NDK 2>/dev/null)" ]; then
  echo "!! 未找到 NDK。请设置 ANDROID_NDK_HOME 指向 NDK 目录。"
  echo "   (例如 /opt/android-ndk-r26b)"
  exit 1
fi
LATEST_NDK=$(ls -d $NDK/*/ | sort -V | tail -1)

export CC=$LATEST_NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android24-clang
export CXX=${CC%clang}clang++
export AR=$LATEST_NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-ar
export RANLIB=$LATEST_NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-ranlib
export CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER=$CC

echo "==> 3. 克隆 rustdesk-server"
if [ ! -d rustdesk-server ]; then
  git clone --depth 1 https://github.com/rustdesk/rustdesk-server.git
fi
cd rustdesk-server

echo "==> 4. 编译 (release, android arm64)"
cargo build --release --target $TARGET

echo "==> 5. 复制产物到模块 bin/arm64/"
OUT=target/$TARGET/release
mkdir -p ../../bin/arm64
cp "$OUT/hbbs" "$OUT/hbbr" ../../bin/arm64/
echo "完成！产物已复制到 bin/arm64/"

echo
echo "提示：若 aarch64-linux-android 目标编译受阻，可尝试 musl 静态目标："
echo "   rustup target add aarch64-unknown-linux-musl"
echo "   cargo build --release --target aarch64-unknown-linux-musl"
echo "（musl 静态产物通常也能在 Android 上运行）"
