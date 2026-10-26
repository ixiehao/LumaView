# LumaView

**高速でミニマルな、Mac ネイティブ画像ビューア。**

画像を 1 枚開けば、同じフォルダ内を続けて閲覧できます。LumaView は画像を中心に据え、日常的な操作をすぐ手の届く場所に置きます。

**[LumaView 1.2.9 ユニバーサル DMG をダウンロード](https://github.com/ixiehao/LumaView/releases/download/v1.2.9/LumaView-1.2.9-universal.dmg)** · [公式サイト](https://ixiehao.github.io/LumaView/?lang=ja) · [English](README.md) · [简体中文](README.zh-CN.md) · [変更履歴](CHANGELOG.md)

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

1. [ユニバーサル DMG をダウンロード](https://github.com/ixiehao/LumaView/releases/download/v1.2.9/LumaView-1.2.9-universal.dmg)します。
2. 開いた DMG から **LumaView.app** を **アプリケーション** フォルダへドラッグします。
3. 「アプリケーション」から LumaView を開きます。画像を直接開く場合は、Finder で画像を右クリックし、「このアプリケーションで開く」→ **LumaView** を選びます。

### 初回起動がブロックされる場合

macOS のバージョンにより、開発元を確認できない、または悪質なソフトウェアかどうか Apple で確認できない、という内容の警告が表示されることがあります。本プロジェクトの GitHub Releases または開発者が提供したテスト版から入手したことを確認したうえで、次の手順で開いてください。

1. 「アプリケーション」から **LumaView** を一度開き、上記の警告を閉じます。
2. 下表の設定を開き、**LumaView** に関するメッセージの **「このまま開く」** をクリックします。
3. 求められた場合はパスワードや Touch ID で認証し、**「開く」** を選びます。次回からは通常、ダブルクリックで起動できます。

| macOS のバージョン | 設定の場所 |
| --- | --- |
| macOS 12 Monterey（Monterey テスト版） | Apple メニュー → **システム環境設定 → セキュリティとプライバシー → 一般** |
| macOS 13 Ventura 以降 | Apple メニュー → **システム設定 → プライバシーとセキュリティ** → 下にスクロールして **セキュリティ** |

「このまま開く」が表示されない場合は、もう一度 LumaView を開いてから設定を確認してください。アプリの破損やコンピュータへの損害を知らせる警告には、この手順を使わず、起動を中止してプロジェクトから再ダウンロードするか、問題をご報告ください。

詳しくは [Apple の案内](https://support.apple.com/ja-jp/102445)を参照してください。

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

## 開発・保守ドキュメント

[ドキュメント一覧](docs/README.md) · [開発と検証](docs/DEVELOPMENT.md) · [公式サイトの保守](docs/WEBSITE.md)。

公式サイトのソースは `website/` に、開発・保守ドキュメントは `docs/` に置いています。
