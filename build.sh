#!/bin/zsh
# MoyuReader 构建脚本：clang 编译 + 打包 .app
set -e
cd "$(dirname "$0")"

echo "[1/2] clang 编译..."
mkdir -p build
clang -fobjc-arc -O2 Sources/main.m -o build/MoyuReader \
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
