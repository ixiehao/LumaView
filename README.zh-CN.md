# LumaView

**一款极速、极简的 Mac 原生看图软件。**

打开一张图片，直接浏览同一文件夹。LumaView 将画面留在中心，把日常操作放在顺手的位置。

**[下载 LumaView 1.2.9 · 通用 DMG](https://github.com/ixiehao/LumaView/releases/download/v1.2.9/LumaView-1.2.9-universal.dmg)** · [官网](https://ixiehao.github.io/LumaView/?lang=zh) · [English](README.md) · [日本語](README.ja.md) · [变更记录](CHANGELOG.md)

macOS 13+ · Intel + Apple Silicon · 通用版 DMG · 约 2 MB

## 软件实机截图

| 打开文件 | 浏览文件夹 |
| --- | --- |
| ![LumaView 中文欢迎界面，仅保留一个打开文件入口](docs/assets/lumaview-welcome.png) | ![LumaView 图片浏览界面，显示文件夹位置和前后浏览操作](docs/assets/lumaview-browse.png) |

## 功能

- **自然浏览** — 可从访达打开、选择文件或直接拖入；使用 `←` / `→` 或工具栏浏览当前文件夹的上一张、下一张。
- **看清画面** — 支持适合窗口、缩放、平移、旋转和打印；底部会显示真实缩放比例。
- **按需查看信息** — 工具栏一个按钮即可查看当前图片的文件信息与内嵌 EXIF；不额外扫描整个文件夹，也不建立元数据图库。
- **打开日常格式** — 支持 JPEG、PNG、HEIC、GIF、TIFF、BMP、ICO、WebP、PDF、多数 macOS 支持的 RAW 和 `.sketch` 预览。
- **为 Mac 而做** — 原生 SwiftUI，支持简体中文 / English / 日本語、浅色 / 深色 / 跟随系统，以及 Intel 与 Apple Silicon。

## 安装

1. [下载通用版 DMG](https://github.com/ixiehao/LumaView/releases/download/v1.2.9/LumaView-1.2.9-universal.dmg)。
2. 打开它，将 **LumaView.app** 拖进“应用程序”。
3. 从“应用程序”打开 LumaView；也可在访达中右键图片，选择“打开方式” → **LumaView**。

### 首次打开被系统拦截时

不同 macOS 版本的提示可能不同，例如“无法验证开发者”或“Apple 无法检查其是否包含恶意软件”。确认安装包来自本项目的 GitHub Releases 或开发者提供的测试包后，可以按以下步骤打开：

1. 从“应用程序”打开一次 **LumaView**，出现上述提示后关闭提示框。
2. 按下表进入系统安全设置，找到 **LumaView** 的拦截提示，点按 **“仍要打开”**（Open Anyway）。
3. 根据系统提示使用密码或触控 ID 确认，再选择 **“打开”**。以后通常可以直接双击启动。

| 系统版本 | 设置入口 |
| --- | --- |
| macOS 12 Monterey（使用 Monterey 测试包） | 苹果菜单 → **系统偏好设置** → **安全性与隐私** → **通用** |
| macOS 13 Ventura 及更新版本 | 苹果菜单 → **系统设置** → **隐私与安全性**（部分版本称“隐私与安全”）→ 向下找到 **安全性** |

如果没有看到“仍要打开”，先再次尝试打开 LumaView，再返回设置查看。若提示“已损坏”或“会损坏你的电脑”，请停止打开，重新从项目页面下载或反馈问题，不按上述流程放行。

参见 Apple 的 [Monterey 打开说明](https://support.apple.com/zh-cn/guide/mac-help/mh40616/12.0/mac/12.0)和[新版 macOS 打开说明](https://support.apple.com/zh-cn/102445)。

### 设为默认看图软件

在访达中选中一张图片 → 按 `⌘I` → 在“打开方式”中选择 **LumaView** → 点按“全部更改…”。

DMG 只是安装包。删除它不会删除 LumaView 或任何图片；如需卸载，只需退出应用，再将“应用程序”中的 `LumaView.app` 移入废纸篓。

## 快捷键

| 操作 | 快捷键 |
| --- | --- |
| 打开文件 | `⌘ O` |
| 上一张 / 下一张 | `←` / `→` |
| 放大 / 缩小 | `⌘ +` / `⌘ -` |
| 适合窗口 | `⌘ 0` |
| 向左 / 向右旋转 | `⌘ [` / `⌘ ]` |
| 打印当前图片 | `⌘ P` |

## 从源码构建

需要 macOS 13+、Xcode 15+ 与 Intel 或 Apple Silicon Mac。

```sh
open LumaView.xcodeproj
# 选择 LumaView scheme，再按 ⌘R。
```

提交 Pull Request 前请运行：

```sh
./Scripts/validate-project.sh
```

发版打包、人工验收和性能基线分别见[发布说明](docs/RELEASE.md)、[QA 说明](docs/QA.md)和[性能基线](docs/PERFORMANCE_BASELINE.md)。

## 反馈与贡献

遇到问题或有功能想法？请使用结构化的[问题反馈](https://github.com/ixiehao/LumaView/issues/new?template=bug_report.yml)或[功能建议](https://github.com/ixiehao/LumaView/issues/new?template=feature_request.yml)。开发协作请阅读[贡献说明](CONTRIBUTING.md)；本地数据行为见[隐私说明](PRIVACY.md)，安全问题请参考[安全说明](SECURITY.md)。

LumaView 使用 [MIT License](LICENSE)。Tabler 图标归属见 [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md)。

## 开发与维护文档

[文档索引](docs/README.md) · [开发与验证](docs/DEVELOPMENT.md) · [官网维护](docs/WEBSITE.md)。

官网源码统一位于 `website/`，`docs/` 用于开发与维护文档。
