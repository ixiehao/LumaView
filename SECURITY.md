# Security / 安全

## English

LumaView has no image-upload, telemetry, account, or cloud-sync path. Its only
application-initiated network request is the limited public GitHub Releases
metadata check described in [PRIVACY.md](PRIVACY.md); it never includes image
data or local file paths. Please do not put security-sensitive details, private
images, or exploit instructions in a public issue. When this project is
connected to GitHub, use the repository's **Report a vulnerability** flow and
include the affected version, macOS version, a minimal reproduction, and the
impact.

Files are opened only after explicit selection or drag-and-drop. The `.sketch`
preview reader launches `/usr/bin/unzip` with an argument array, never through
a shell; a preview over 64 MiB is rejected before image decoding.

## 中文

LumaView 不提供图片上传、遥测、账号或云同步通道。应用唯一主动发起的联网请求是 [PRIVACY.md](PRIVACY.md) 所述的 GitHub 公开 Releases 元数据检查；该请求不会包含图片数据或本地文件路径。请勿在公开 Issue 中发布安全敏感细节、私人图片或利用步骤。项目接入 GitHub 后，请使用仓库 Security 标签中的 **Report a vulnerability** 流程，并提供受影响版本、macOS 版本、最小复现步骤与影响说明。

文件只会在用户主动选择或拖入后打开。`.sketch` 预览读取器以参数数组启动 `/usr/bin/unzip`，不经过 Shell；超过 64 MiB 的预览会在图像解码前被拒绝。
