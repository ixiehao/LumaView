# Changelog

All notable user-facing changes are recorded here. Version numbers follow
`MAJOR.MINOR.PATCH`; a release tag must be `vX.Y.Z` and match the app's
marketing version.

## 1.2.8 — 2026-10-17

### English

- Show square and portrait images edge to edge, without blank strips beside the canvas.
- Fix a launch-time crash that could occur before macOS finished creating the application object.

### 中文

- 正方形和竖图贴合窗口两侧，不再留下白边。
- 修复 macOS 尚未完成应用初始化时可能发生的启动崩溃。

### 日本語

- 正方形や縦長の画像を左右の余白なく表示します。
- macOS がアプリケーションの初期化を終える前に発生することがあった起動時のクラッシュを修正しました。

## 1.2.7 — 2026-10-17

### English

- Match the window to the image canvas below the toolbar, removing the blank strips beside square and portrait images.

### 中文

- 窗口按工具栏下方的实际画布尺寸适配图片，去除正方形与竖图两侧的留白。

### 日本語

- ツールバー下の画像表示領域にウインドウを合わせ、正方形や縦長の画像の左右にできる余白をなくしました。

## 1.2.6 — 2026-10-17

### English

- Close Image Information when moving to another image, so EXIF never remains from the previous file.
- Resize the canvas and window after rotation, keeping the full image fitted to its new orientation.

### 中文

- 切换图片时自动关闭“图片信息”，避免保留上一张图片的 EXIF。
- 图片旋转后，画布与窗口会按新的方向调整，完整贴合画面。

### 日本語

- 前後の画像へ移動すると「画像情報」を閉じ、前の画像の EXIF が残らないようにしました。
- 画像を回転した後、キャンバスとウインドウが新しい向きに合わせて調整され、画像全体をぴったり表示します。

## 1.2.5 — 2026-10-17

### English

- Corrected the portable SHA-256 file shipped with the universal DMG so downloads can be verified directly.

### 中文

- 修正通用 DMG 附带的可移植 SHA-256 校验文件，下载后可直接校验。

### 日本語

- ユニバーサル DMG に添付するポータブルな SHA-256 チェックサムファイルを修正し、ダウンロード後に直接検証できるようにしました。

## 1.2.4 — 2026-10-17

### English

- Added an on-demand Image Information inspector for file facts and embedded EXIF data.
- Made each image window recalculate its canvas geometry when browsing so the full image stays visible without side rails.

### 中文

- 新增按需读取的“图片信息”面板，可查看文件信息与内嵌 EXIF 数据。
- 浏览上一张、下一张时，窗口会按当前图片重新计算画布尺寸，完整显示画面且不再留下左右留白。

### 日本語

- ファイル情報と埋め込み EXIF を必要なときだけ確認できる「画像情報」パネルを追加しました。
- 前後の画像へ移動したときにウインドウがキャンバスの寸法を再計算し、画像全体を表示して左右の余白を残さないようにしました。

## 1.2.3 — 2026-10-16

### English

- Added complete Japanese localization for the app, website, README, QA guidance, and release documentation.

### 中文

- 为应用、官网、README、QA 指引和发布文档补充完整日语本地化。

### 日本語

- アプリ、公式サイト、README、QA ガイド、リリース文書に日本語ローカライズを追加しました。

## 1.2.2 — 2026-10-15

- Added a universal macOS build with both Apple Silicon (`arm64`) and Intel (`x86_64`) slices.
- Updated build, packaging, mounted-DMG verification, installer, documentation, and release guidance to require and describe the universal artifact.

### 中文

- 新增同时支持 Apple Silicon（`arm64`）与 Intel（`x86_64`）的 macOS 通用版。
- 更新构建、打包、挂载后 DMG 校验、安装界面、文档与发布流程，统一要求并说明通用安装包。

### 日本語

- Apple Silicon（`arm64`）と Intel（`x86_64`）の両方に対応する macOS ユニバーサル版を追加しました。
- ビルド、パッケージ作成、DMG マウント後の検証、インストーラ画面、文書、リリース手順を更新し、ユニバーサルインストーラの要件と内容を統一しました。

## 1.2.1 — 2026-10-15

- Restored source-build compatibility with Xcode 15.4 by removing a Swift name-shadowing ambiguity in the canvas and explicitly selecting Darwin trigonometry for rotated bounds.
- Reworked Finder and window ownership: every selected file now receives one independent AppKit-owned document window, with no transient SwiftUI placeholder scene.
- Show the chosen image before its immediate folder is indexed; cancellation stops only the relevant window's scan or prefetch work.
- Replaced the shared decode cache with bounded global LRU caches, while each window owns and cancels only its own adjacent-image prefetch operations.
- Clear the prior render as soon as a new image is requested, preventing an old frame from appearing under a new file title.
- Bound Sketch preview extraction to a 64 MiB output limit and a four-second timeout, with cooperative cancellation of the archive process.
- Added a 1/4/8-window 5K synthetic baseline to the validation harness for RSS, first-image time, and navigation latency.
- Renamed the app-specific image-controls menu to Image / 图像 and preserved macOS Help instead of replacing it.
- Published the first Apple-silicon DMG through the documented transparent preview path, with a matching SHA-256 asset and non-notarized first-run guidance.

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

### 日本語

- 埋め込みページプレビューを読み取り、`.sketch` 書類のプレビューに対応しました。
- key ベースの英語・簡体中国語リソースと、翻訳の完全性テストを整備しました。
- ネイティブの「LumaViewについて」パネルと安全な GitHub 更新確認を追加し、自動確認、手動確認、更新あり、オフライン失敗の状態を扱えるようにしました。
- オリジナルの LumaView ブランド画像、分かりやすいドラッグ＆ドロップ案内、再現可能な Finder レイアウト検証を備えた DMG インストーラを再構築しました。
- macOS の標準メニューを LumaView の選択言語に追従させつつ、システムの「ヘルプ」メニューを維持しました。
- 二言語の文書、コントリビューション、プライバシー、セキュリティ、リリース、CI の記録を整備し、同等プロジェクトと一貫した管理方式にしました。
