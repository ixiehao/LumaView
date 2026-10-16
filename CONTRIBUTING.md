# Contributing / 参与贡献 / コントリビューション

## English

Keep each pull request focused on one user-visible fix, feature, or
documentation improvement. Do not add telemetry, accounts, cloud upload,
network clients, private image fixtures, credentials, or third-party assets
without documenting the reason, licence, privacy impact, and verification.

Before requesting review, run:

```sh
./Scripts/validate-project.sh
```

For visual changes, inspect English, Simplified Chinese, and Japanese in both
Light and Dark appearances. For decoding or navigation changes, also test a non-private
folder with ordinary images, a large image, an unsupported file, and (when
affected) a `.sketch` document. Do not attach private images to issues or pull
requests.

## 中文

每个 Pull Request 应聚焦一项用户可见的修复、功能或文档改进。未说明原因、许可证、隐私影响和验证方式前，请勿加入遥测、账号、云上传、网络客户端、私有图片测试素材、凭据或第三方资源。

请求评审前请运行：

```sh
./Scripts/validate-project.sh
```

涉及界面的改动，请在浅色/深色下分别检查 English、简体中文与日本語。涉及解码或导航的改动，还应使用非私有图片文件夹检查普通图片、大图、不支持文件，以及（如受影响）`.sketch` 文档。请勿在 Issue 或 Pull Request 中上传私人图片。

## 日本語

各 Pull Request は、ユーザーに見える 1 つの修正、機能、または文書改善に絞ってください。理由、ライセンス、プライバシーへの影響、検証方法を記録せずに、テレメトリー、アカウント、クラウドアップロード、ネットワーククライアント、非公開画像のテスト素材、認証情報、第三者アセットを追加しないでください。

レビューを依頼する前に、次を実行します。

```sh
./Scripts/validate-project.sh
```

画面に関わる変更では、ライトとダークの両方で English、简体中文、日本語を確認してください。デコードまたは閲覧の変更では、一般的な画像、大きな画像、未対応ファイル、影響する場合は `.sketch` 書類を含む非公開でないフォルダでも確認します。Issue や Pull Request に個人画像を添付しないでください。
