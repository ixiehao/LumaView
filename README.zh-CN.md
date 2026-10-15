# LumaView

**一款面向 Apple Silicon Mac 的本地原生图片浏览器。**

LumaView 打开图片后持续专注于看图：前后浏览、查看大图、缩放、旋转、打印，以及在访达中定位当前文件。它不会创建图片库、复制源文件、要求登录或上传图片。

[**最新发布：v1.2.1 arm64 DMG**](https://github.com/ixiehao/LumaView/releases/tag/v1.2.1) · macOS 13+ · 仅 Apple Silicon

[官网](https://ixiehao.github.io/LumaView/) · [English](README.md) · [贡献说明](CONTRIBUTING.md) · [隐私](PRIVACY.md) · [安全](SECURITY.md) · [发布说明](docs/RELEASE.md) · [变更记录](CHANGELOG.md)

## 软件实机截图

| 本地开始浏览 | 无侧栏专注看图 |
| --- | --- |
| ![LumaView 中文欢迎界面，仅保留一个打开文件入口](docs/assets/lumaview-welcome.png) | ![LumaView 图片浏览界面，显示文件夹位置和前后浏览操作](docs/assets/lumaview-browse.png) |

截图来自真实运行的 LumaView，只使用原创测试图，不含用户照片、文件名、文件夹或桌面内容。

## 功能

- 原生 SwiftUI 看图器，支持 macOS 13+ 的 **Apple Silicon** Mac；不支持 Intel Mac。
- 可从访达打开、选择文件或直接拖入；通过 `←` / `→` 和工具栏浏览当前文件夹。
- 支持 JPEG、PNG、HEIC、GIF、TIFF、BMP、ICO、WebP、PDF、多数 macOS 支持的 RAW 与 `.sketch` 预览。
- 支持大图缩放、适合窗口、平移、旋转与原生打印；底部显示相对原图的真实百分比。
- 中文 / English / 跟随系统语言，以及浅色 / 深色 / 跟随系统外观即时切换。

## 环境要求

- Apple Silicon Mac（arm64）
- macOS 13 Ventura 或更高版本
- 从源码构建需 Xcode 15 或更新版本

## 下载

请打开[最新发布页](https://github.com/ixiehao/LumaView/releases/latest)，下载
**`LumaView-1.2.1-arm64.dmg`** 和同名的
`LumaView-1.2.1-arm64.dmg.sha256` 校验文件。该版本仅适用于 Apple Silicon，
不能在 Intel Mac 上运行。

## 安全安装

1. 双击下载的 `.dmg`，将 **LumaView.app** 拖进“应用程序”。
2. 复制完成后可推出或删除 DMG；它只是安装包，不会删除已经安装的应用。
3. 这是首个公开预览版，采用 ad-hoc 签名，**尚未经过 Apple 公证**。若系统提示无法验证开发者，请在“应用程序”中按住 Control 点按 **LumaView**，选择“打开”，再确认一次“打开”。无需关闭 macOS 的系统级安全设置。

之后如需卸载，先退出应用，再将“应用程序”中的 `LumaView.app` 移入废纸篓。原始图片会保留在原位置。

## 打开与运行

```sh
open LumaView.xcodeproj
```

选择 **LumaView** scheme 后按 `⌘R`。工程会始终生成 `arm64` 应用。

## 快捷键

| 操作 | 快捷键 |
| --- | --- |
| 打开文件 | `⌘ O` |
| 上一张 / 下一张 | `←` / `→` |
| 放大 / 缩小 | `⌘ +` / `⌘ -` |
| 适合窗口 | `⌘ 0` |
| 向左 / 向右旋转 | `⌘ [` / `⌘ ]` |
| 打印当前图片 | `⌘ P` |

## 验证与打包

```sh
./Scripts/validate-project.sh
./Scripts/package-dmg.sh
```

验证脚本会运行核心测试、UI 测试（含真实 1 / 4 / 8 窗口 5K 渲染门禁）、Release 构建和合成图库压力测试。真实窗口门禁会记录首图/全量渲染时间、RSS、文档身份和各窗口独立的初始视图状态；访达方式打开后的 `←` / `→` 浏览有独立的端到端覆盖。不能在无头 XCTest 中可靠驱动的 LaunchServices、拖放、打印、VoiceOver 与损坏文件验收步骤见 [docs/QA.md](docs/QA.md)。`package-dmg.sh` 会生成 ad-hoc 签名 DMG；v1.2.1 GitHub 发布沿用 ShotMap 的透明预览方式，附上同一 DMG 的 SHA-256，并明确非公证状态与首次启动指引。面向正式公开稳定版的 Developer ID 签名、公证、staple 和 Gatekeeper 验证流程仍见 [docs/RELEASE.md](docs/RELEASE.md)。
当前 5K 多窗口的 RSS 与切换延迟基线见 [docs/PERFORMANCE_BASELINE.md](docs/PERFORMANCE_BASELINE.md)。
公开发布前必须有可审计的首个提交，并以指向实际发布源码的 annotated `vX.Y.Z` tag 标记；流程见 [docs/RELEASE.md](docs/RELEASE.md)。打包脚本绝不会自动创建提交、tag、凭据或伪造签名。

## 项目边界

LumaView 是看图软件，不是编辑器、图片管理器、云备份或清理工具。保持浏览主路径简洁是有意的设计选择。

源码采用 [MIT License](LICENSE)。Tabler 图标归属见 [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md)。
