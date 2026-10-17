# LumaView

**高速でミニマルな、Mac ネイティブ画像ビューア。**

画像を 1 枚開けば、同じフォルダ内を続けて閲覧できます。LumaView は画像を中心に据え、日常的な操作をすぐ手の届く場所に置きます。

**[LumaView 1.2.6 ユニバーサル DMG をダウンロード](https://github.com/ixiehao/LumaView/releases/download/v1.2.6/LumaView-1.2.6-universal.dmg)** · [公式サイト](https://ixiehao.github.io/LumaView/?lang=ja) · [English](README.md) · [简体中文](README.zh-CN.md) · [変更履歴](CHANGELOG.md)

macOS 13 以降 · Intel + Apple Silicon · ユニバーサル DMG · 約 2 MB

## 実際の画面

| ファイルを開く | フォルダ内を閲覧 |
| --- | --- |
| ![「ファイルを開く」だけを置いた LumaView のネイティブ歓迎画面](docs/assets/lumaview-welcome.png) | ![フォルダ内の位置と前後移動の操作を表示した LumaView の画像閲覧画面](docs/assets/lumaview-browse.png) |

## 主な機能

- **自然に閲覧** — Finder から開く、ファイルを選ぶ、またはドラッグ＆ドロップ。`←` / `→` キーやツールバーで、同じフォルダ内の前後の画像へ移動できます。
- **画像を見やすく** — ウインドウに合わせる、拡大・縮小、パン、回転、プリントに対応。ステータスバーには実際の拡大率を表示します。
- **必要なときだけ情報を見る** — ツールバーのボタンひとつで、現在の画像のファイル情報と埋め込み EXIF を確認できます。フォルダ全体を改めて走査したり、メタデータライブラリを作成したりしません。
- **日常的な形式に対応** — JPEG、PNG、HEIC、GIF、TIFF、BMP、ICO、WebP、PDF、多くの macOS 対応 RAW ファイル、`.sketch` のプレビューを開けます。
- **Mac のために** — ネイティブ SwiftUI、English・简体中文・日本語、ライト・ダーク・システムの外観、Intel と Apple Silicon に対応します。

## インストール

1. [ユニバーサル DMG をダウンロード](https://github.com/ixiehao/LumaView/releases/download/v1.2.6/LumaView-1.2.6-universal.dmg)します。
2. 開いた DMG から **LumaView.app** を **アプリケーション** フォルダへドラッグします。
3. LumaView を開くか、画像をダブルクリックして Finder の「このアプリケーションで開く」から選びます。

### LumaView を標準の画像ビューアにする

Finder で画像を選択 → `⌘I` → 「このアプリケーションで開く」で **LumaView** を選択 → 「すべてを変更…」をクリックします。

DMG はインストーラです。DMG を取り出しても LumaView や画像は削除されません。アンインストールする場合は、LumaView を終了してから「アプリケーション」の `LumaView.app` をゴミ箱へ移動してください。

## ショートカット

| 操作 | ショートカット |
| --- | --- |
| ファイルを開く | `⌘ O` |
| 前の画像 / 次の画像 | `←` / `→` |
| 拡大 / 縮小 | `⌘ +` / `⌘ -` |
| 画像をウインドウに合わせる | `⌘ 0` |
| 左 / 右に回転 | `⌘ [` / `⌘ ]` |
| 現在の画像をプリント | `⌘ P` |

## ソースからビルド

macOS 13 以降、Xcode 15 以降、Intel または Apple Silicon 搭載 Mac が必要です。

```sh
open LumaView.xcodeproj
# LumaView スキームを選び、⌘R を押します。
```

Pull Request を作成する前に、次を実行してください。

```sh
./Scripts/validate-project.sh
```

リリースのパッケージ作成、手動 QA、性能ベースラインは、[リリースガイド](docs/RELEASE.md)、[QA ガイド](docs/QA.md)、[性能ベースライン](docs/PERFORMANCE_BASELINE.md)に記載しています。

## フィードバックと貢献

問題を見つけた、またはアイデアがある場合は、構造化された[バグ報告](https://github.com/ixiehao/LumaView/issues/new?template=bug_report.yml)または[機能リクエスト](https://github.com/ixiehao/LumaView/issues/new?template=feature_request.yml)を利用してください。開発への協力については[コントリビューションガイド](CONTRIBUTING.md)、ローカルデータの取り扱いについては[プライバシー](PRIVACY.md)、脆弱性の報告については[セキュリティ](SECURITY.md)を参照してください。

LumaView は [MIT License](LICENSE) で提供しています。Tabler アイコンの帰属は [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md) に記載しています。
