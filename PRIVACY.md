# Privacy / 隐私

## English

LumaView processes images on the Mac that opens them.

- The app has no account, telemetry, advertising SDK, cloud sync, or image upload path. It may query GitHub's public Releases API for version metadata at launch (at most once every 12 hours) or when the person explicitly checks for updates. This request sends no image, file path, account, or device identifier from LumaView; as with any network request, GitHub receives the network address and standard transport metadata supplied by the Mac's connection.
- It reads only files or folders the person selects or drops into the window. Images are decoded in memory for the current browsing session; the app does not create an internal image library or persistent preview cache.
- Source files are never copied, edited, renamed, or deleted by LumaView. Printing uses macOS's standard print panel, and **Reveal in Finder** asks macOS to select the current file in Finder.
- For a `.sketch` document, LumaView invokes the macOS-provided `/usr/bin/unzip` executable without a shell to read the document's embedded page preview. It does not parse or modify Sketch editing data.

If a future version changes this network access, adds analytics, an account, or persistent image data, this policy and the release notes must be updated before that version ships.

## 中文

LumaView 会在打开图片的这台 Mac 上完成处理。

- 应用不包含账号、遥测、广告 SDK、云同步或图片上传路径。应用会在启动时（最多每 12 小时一次）或用户手动检查更新时，查询 GitHub 公开的 Releases API 以获取版本元数据；请求不会发送图片、文件路径、账号或由 LumaView 生成的设备标识。与任何网络请求相同，GitHub 仍会从 Mac 的网络连接获得网络地址及标准传输元数据。
- 它只读取用户主动选择或拖入窗口的文件/文件夹。图片只在当前浏览会话中于内存解码；应用不会创建内部图片库或持久化缩略图缓存。
- LumaView 不会复制、编辑、重命名或删除源文件。打印使用 macOS 原生打印面板；“在访达中显示”仅请求 macOS 在 Finder 中选中当前文件。
- 对 `.sketch` 文档，LumaView 会无 Shell 调用 macOS 提供的 `/usr/bin/unzip`，读取文档内置页面预览；不会解析或改动 Sketch 的编辑数据。

若未来版本改变上述联网行为，或增加分析、账号或持久化图片数据，必须在发布前同步更新本文档与发布说明。
