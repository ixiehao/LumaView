# Changelog

All notable user-facing changes are recorded here. Version numbers follow
`MAJOR.MINOR.PATCH`; a release tag must be `vX.Y.Z` and match the app's
marketing version.

## 1.2.1 — 2026-10-15

- Restored source-build compatibility with Xcode 15.4 by removing a Swift name-shadowing ambiguity in the canvas and explicitly selecting Darwin trigonometry for rotated bounds.
- Reworked Finder and window ownership: every selected file now receives one independent AppKit-owned document window, with no transient SwiftUI placeholder scene.
- Show the chosen image before its immediate folder is indexed; cancellation stops only the relevant window's scan or prefetch work.
- Replaced the shared decode cache with bounded global LRU caches, while each window owns and cancels only its own adjacent-image prefetch operations.
- Clear the prior render as soon as a new image is requested, preventing an old frame from appearing under a new file title.
- Bound Sketch preview extraction to a 64 MiB output limit and a four-second timeout, with cooperative cancellation of the archive process.
- Added a 1/4/8-window 5K synthetic baseline to the validation harness for RSS, first-image time, and navigation latency.
- Renamed the app-specific image-controls menu to Image / 图像 and preserved macOS Help instead of replacing it.

### English

- Added preview support for `.sketch` documents through the embedded page preview.
- Completed key-based English and Simplified Chinese localization with coverage tests.
- Added a native About panel plus a safe GitHub release checker with automatic, manual, available-update, and offline states.
- Rebuilt the DMG installer with original LumaView artwork, a clear drag-to-install flow, and reproducible Finder layout validation.
- Made standard macOS menu labels follow LumaView's selected language without replacing the system Help menu.
- Standardized the project with bilingual documentation, contributor, privacy, security, release, and CI records.

### 中文

- 通过读取文档内置页面预览，新增 `.sketch` 文件预览支持。
- 完成基于 key 的中英文资源库，并加入翻译完整性测试。
- 新增原生“关于”面板与安全的 GitHub 更新检查，涵盖自动检查、手动检查、有新版本和离线失败状态。
- 重制 DMG 安装界面：使用原创 LumaView 品牌插画、清晰拖拽引导，并加入可复现的 Finder 布局校验。
- 让 macOS 标准菜单完整跟随 LumaView 的语言选择，同时保留系统“帮助”菜单。
- 补齐双语文档、贡献、隐私、安全、发布和 CI 记录，使项目管理方式与同级项目一致。
