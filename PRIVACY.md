# Privacy / 隐私 / プライバシー

## English

LumaView processes images on the Mac that opens them.

- The app has no account, telemetry, advertising SDK, cloud sync, or image upload path. It may query GitHub's public Releases API for version metadata at launch (at most once every 12 hours) or when the person explicitly checks for updates. This request sends no image, file path, account, or device identifier from LumaView; as with any network request, GitHub receives the network address and standard transport metadata supplied by the Mac's connection.
- It reads opened files and lists supported files in their parent folder for previous/next browsing. It also decodes nearby files in advance to speed up navigation. Images are decoded in memory for the current browsing session; the app does not create an internal image library or persistent preview cache.
- Source files are never copied, edited, renamed, or deleted by LumaView. Printing uses macOS's standard print panel, and **Reveal in Finder** asks macOS to select the current file in Finder.
- For a `.sketch` document, LumaView invokes the macOS-provided `/usr/bin/unzip` executable without a shell to read the document's embedded page preview. It does not parse or modify Sketch editing data.

If a future version changes this network access, adds analytics, an account, or persistent image data, this policy and the release notes must be updated before that version ships.

## 中文

LumaView 会在打开图片的这台 Mac 上完成处理。

- 应用不包含账号、遥测、广告 SDK、云同步或图片上传路径。应用会在启动时（最多每 12 小时一次）或用户手动检查更新时，查询 GitHub 公开的 Releases API 以获取版本元数据；请求不会发送图片、文件路径、账号或由 LumaView 生成的设备标识。与任何网络请求相同，GitHub 仍会从 Mac 的网络连接获得网络地址及标准传输元数据。
- 应用会读取已打开的文件，并列出同一文件夹内支持的文件以便前后浏览；也会预读相邻文件，以加快切换。图片只在当前浏览会话中于内存解码；应用不会创建内部图片库或持久化缩略图缓存。
- LumaView 不会复制、编辑、重命名或删除源文件。打印使用 macOS 原生打印面板；“在访达中显示”仅请求 macOS 在 Finder 中选中当前文件。
- 对 `.sketch` 文档，LumaView 会无 Shell 调用 macOS 提供的 `/usr/bin/unzip`，读取文档内置页面预览；不会解析或改动 Sketch 的编辑数据。

若未来版本改变上述联网行为，或增加分析、账号或持久化图片数据，必须在发布前同步更新本文档与发布说明。

## 日本語

LumaView は、画像を開いた Mac 上で処理を行います。

- アカウント、テレメトリー、広告 SDK、クラウド同期、画像アップロード機能は含みません。起動時（12 時間に 1 回まで）または利用者が手動でアップデートを確認したときに、バージョン情報のため GitHub の公開 Releases API を照会することがあります。このリクエストで画像、ファイルパス、アカウント情報、LumaView が生成したデバイス識別子を送信することはありません。ただし、あらゆるネットワークリクエストと同様に、GitHub には Mac の接続が提供するネットワークアドレスと標準的な転送メタデータが届きます。
- 開いたファイルを読み取り、前後の画像へ移動するため、同じフォルダ内の対応ファイルを列挙します。切り替えを速くするため、前後のファイルも先読みします。画像は現在の閲覧セッション中にメモリ上でデコードし、内部の画像ライブラリや永続的なプレビューキャッシュは作成しません。
- LumaView が元のファイルをコピー、編集、名前変更、削除することはありません。プリントには macOS 標準のプリントパネルを使い、「Finderで表示」は macOS に現在のファイルを Finder で選択するよう依頼するだけです。
- `.sketch` 書類では、シェルを介さず macOS 提供の `/usr/bin/unzip` を実行して、書類に埋め込まれたページプレビューを読み取ります。Sketch の編集データを解析したり変更したりすることはありません。

将来のバージョンでこのネットワークアクセスを変更したり、分析、アカウント、永続的な画像データを追加したりする場合は、そのバージョンを公開する前に本ポリシーとリリースノートを更新します。
