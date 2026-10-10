# MoyuReader · 摸鱼阅读器

macOS 原生的透明置顶小说阅读器。参照 [binbyu/Reader](https://github.com/binbyu/Reader)（Windows）的核心体验，只做摸鱼阅读这一件事。

- 纯 **Objective-C + AppKit**，单文件源码，零第三方依赖
- 成品 App 约 130KB，无 Dock 图标、无后台服务
- 构建只需要系统自带的 clang，不需要安装任何东西

## 功能

| 功能 | 说明 |
|---|---|
| 透明置顶 | 无边框全透明窗口（黑字），永远浮在其他应用上面；可在右键菜单加底色（文字自动切白） |
| 老板键 | 全局热键 `Option + H` 一键隐藏 / 唤回，无需辅助功能权限 |
| 章节跳转 | 自动解析目录，`Cmd + T` 打开目录，`Cmd + ←/→` 上下章；目录正则可自定义 |
| 自动翻页 | `空格` 开始 / 停止，逐行滚动或整页翻页两种模式，鼠标悬停自动暂停，到文末自动停 |
| 菜单栏常驻 | 菜单栏书本图标（SF Symbol 单色）：唤回窗口 / 打开 TXT / 目录 / 退出 |
| 进度记忆 | 按文件记忆阅读位置，重开自动回到原处 |
| 编码识别 | 自动识别 UTF-8 / UTF-16 / GB18030，中文 TXT 直接拖入即读 |
| 双击关闭 | 双击窗口任意位置收起窗口 |

## 操作

**鼠标**

- 按住窗口任意位置拖动 = 移动窗口
- 右缘 / 底缘 / 右下角 = 拉伸改变窗口大小（缩放时文字实时重新排版）
- 单击窗口 = 显示底部进度状态栏 + 左上角红黄绿按钮 + 窗口边框（方便定位边界），鼠标移出自动隐藏
- 双击 = 收起窗口（红按钮效果相同）
- 右键 = 主菜单（打开 / 目录 / 章节跳转 / 自动阅读 / 字体 / 透明度 / 正则设置…）

**快捷键**（窗口获得焦点时）

| 键 | 功能 |
|---|---|
| `Option + H` | 老板键：全局隐藏 / 唤回 |
| `空格` | 开始 / 停止自动阅读 |
| `Cmd + O` | 打开 TXT |
| `Cmd + T` | 章节目录 |
| `Cmd + ←` / `Cmd + →` | 上一章 / 下一章 |
| `Cmd + +` / `Cmd + -` | 字体放大 / 缩小 |
| `Cmd + Q` | 退出 |

**打开文件**：拖 TXT 进窗口、`Cmd + O`、菜单栏图标 → 打开，或在 Finder 里「打开方式 → MoyuReader」。打开后自动记住这本书，下次启动直接回到上次进度。

## 构建

```bash
./build.sh            # 产物: build/MoyuReader.app
./build/test_logic    # 逻辑回归测试（17 项）
```

无 CocoaPods / SPM / Carthage，clang 一把梭。系统要求 macOS 13+（SF Symbols 菜单栏图标需要 11+）。

## 使用建议

- 开机自启：系统设置 → 通用 → 登录项，把 `MoyuReader.app` 拖进去
- 无 Dock 图标（LSUIElement），退出走右键菜单 → 退出，或 `Cmd + Q`，或菜单栏图标 → 退出
- 目录识别失败时：右键 → 目录正则设置…（默认匹配 `第…章` 开头的行，支持中文数字）

## 技术说明

- **全局热键**：Carbon `RegisterEventHotKey`，不需要辅助功能权限。
- **全透明窗口能收到鼠标事件**：macOS 对无边框窗口做逐像素命中测试，alpha=0 的区域事件会穿透到下层窗口。所以「全透」档实际渲染一层 1/255 的底色——肉眼不可见，但事件能被窗口接住。
- **红黄绿按钮**：`titled + fullSizeContentView + titlebarAppearsTransparent + titleVisibility=hidden` 组合，标题栏隐形但保留原生窗口按钮（需开 `closable` / `miniaturizable` 权限位，否则按钮是灰的）。
- **大文档滚动**：`allowsNonContiguousLayout = YES`，只布局可视区域附近，几 MB 的书也不卡。
- **缩放重排**：监听 clip view 的 frame 变化，强制文本宽度跟随并重新换行。
- **为什么是 Objective-C**：本机 Command Line Tools 存在 `SwiftBridging` modulemap 重复定义的已知 bug（swiftc 任何编译都失败），clang 不受影响，于是直接 ObjC——结果反而是零依赖最简方案。
- **测试**：`tools/test_logic.m` 通过 `#import "../Sources/main.m"` 直接编译真实实现，覆盖编码识别、章节解析、二分定位——保证「测的就是跑的」，不维护任何手抄副本。

## 目录

```
Sources/main.m      全部源码（单文件）
tools/test_logic.m  逻辑回归测试
build.sh            构建脚本
Info.plist          App 清单（LSUIElement + TXT 关联）
示例/sample.txt     40 章示例书
```

## 版权与免责

仅供学习与个人使用，请勿用于商业用途。上班摸鱼有风险，老板键不保熟。
