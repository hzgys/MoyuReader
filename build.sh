#!/bin/zsh
# MoyuReader 构建脚本：clang 编译 + 打包 .app
set -e
cd "$(dirname "$0")"

echo "[1/2] clang 编译（arm64 + x86_64 双架构）..."
mkdir -p build
clang -fobjc-arc -O2 -arch arm64 -arch x86_64 Sources/main.m -o build/MoyuReader \
    -framework AppKit -framework Carbon -framework QuartzCore -framework UniformTypeIdentifiers

echo "[2/2] 打包 .app..."
APP=build/MoyuReader.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp build/MoyuReader "$APP/Contents/MacOS/MoyuReader"
cp Info.plist "$APP/Contents/Info.plist"
touch "$APP"
codesign --force -s - "$APP" >/dev/null 2>&1 || true

echo "完成: $(pwd)/$APP"

# 可选：-d 参数同时产出 DMG 安装镜像（拖入 Applications 那种）
if [ "$1" = "-d" ]; then
    echo "[+] 制作 DMG..."
    DMG_SRC=$(mktemp -d)
    cp -R "$APP" "$DMG_SRC/"
    ln -s /Applications "$DMG_SRC/Applications"
    hdiutil create -volname MoyuReader -srcfolder "$DMG_SRC" \
        -ov -format UDZO -quiet build/MoyuReader.dmg
    rm -rf "$DMG_SRC"
    echo "完成: $(pwd)/build/MoyuReader.dmg"
fi
