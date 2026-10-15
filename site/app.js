const content = {
  zh: {
    navExperience: "体验", navLocal: "本地优先", navDownload: "下载", eyebrow: "仅为 Apple Silicon Mac 打造",
    heroTitle: "让图片，<br /><em>占满注意力。</em>", heroLede: "LumaView 是一款极简的本地原生看图软件：打开一张图片，即刻沿同级文件夹前后浏览。没有侧栏、没有图片库、没有上传。",
    downloadButton: "下载 v1.2.1", sourceButton: "查看源码", compatibility: "macOS 13+ · Apple Silicon · 完全本地处理", heroCaption: "真实运行截图 · 使用原创测试图", heroImageAlt: "LumaView 正在深色界面中浏览测试图片，顶部有上一个、下一个、缩放和旋转操作", welcomeImageAlt: "LumaView 深色欢迎界面，中央只保留打开文件按钮",
    proofOne: "打开即看，不建立图库", proofTwo: "方向键快速前后浏览", proofThree: "图片始终留在你的 Mac",
    experienceEyebrow: "为看图而存在", experienceTitle: "少一点界面，<br />多一点画面。", welcomeCaption: "真实运行截图 · 欢迎界面",
    featureOneTitle: "文件夹里的上一张 / 下一张", featureOneBody: "直接从访达或“打开文件”进入。LumaView 先显示当前图，再轻量索引同级文件，工具栏和方向键都能自然切换。",
    featureTwoTitle: "大图按屏幕而生", featureTwoBody: "适合窗口、连续缩放、平移与旋转围绕画布本身设计；状态栏显示相对于原图的真实百分比。",
    featureThreeTitle: "不止 PNG 和 JPG", featureThreeBody: "JPEG、PNG、HEIC、GIF、TIFF、WebP、PDF、许多系统 RAW 格式与 Sketch 文档预览，都在本地完成。",
    localEyebrow: "私密是默认行为", localTitle: "图像不离开<br />你的设备。", localBody: "LumaView 不创建图片库，不复制源文件，不要求账户，也不上传你的图像。可选更新检查只读取公开版本元数据。", localOne: "无账户、无广告、无遥测", localTwo: "内存缓存有严格上限", localThree: "原生 Finder、打印与快捷键习惯",
    readyEyebrow: "准备好只看图片了吗？", downloadTitle: "打开一张图。<br />剩下的，交给方向键。", downloadNote: "macOS 13+ · Apple Silicon (arm64)", securityNote: "当前为公开预览版，采用 ad-hoc 签名，尚未经过 Apple 公证。若首次启动出现验证提示，请在“应用程序”中 Control 点按 LumaView → “打开” → 再次“打开”；无需关闭系统级安全设置。", footerTagline: "本地原生图片浏览器 · 由 ixiehao 制作", footerIssues: "反馈", footerReleases: "版本"
  },
  en: {
    navExperience: "Experience", navLocal: "Local first", navDownload: "Download", eyebrow: "Built for Apple Silicon Macs",
    heroTitle: "Let the image<br /><em>take your attention.</em>", heroLede: "LumaView is a minimal, native image viewer. Open one image and move through its folder immediately. No sidebar, no library, no uploads.",
    downloadButton: "Download v1.2.1", sourceButton: "View source", compatibility: "macOS 13+ · Apple Silicon · Local by default", heroCaption: "Real application screenshot · original test art", heroImageAlt: "LumaView browsing original test artwork in its dark interface, with previous, next, zoom, and rotate controls", welcomeImageAlt: "LumaView dark welcome screen with a single Open File action",
    proofOne: "Open an image, not a library", proofTwo: "Arrow-key folder browsing", proofThree: "Images stay on your Mac",
    experienceEyebrow: "Made to view", experienceTitle: "Less interface.<br />More image.", welcomeCaption: "Real application screenshot · welcome screen",
    featureOneTitle: "Previous / next in the folder", featureOneBody: "Open from Finder or choose a file. LumaView shows it first, then lightly indexes sibling files for natural toolbar and arrow-key navigation.",
    featureTwoTitle: "Large images meet the screen", featureTwoBody: "Fit, continuous zoom, pan, and rotation are designed around the canvas; the status bar reports an honest percentage of the source image.",
    featureThreeTitle: "More than PNG and JPG", featureThreeBody: "JPEG, PNG, HEIC, GIF, TIFF, WebP, PDF, many system RAW formats, and Sketch document previews all stay local.",
    localEyebrow: "Private by default", localTitle: "Your image never<br />leaves your device.", localBody: "LumaView creates no library, copies no source file, asks for no account, and uploads no images. Its optional update check only reads public release metadata.", localOne: "No accounts, ads, or telemetry", localTwo: "Strict in-memory cache limits", localThree: "Native Finder, printing, and shortcuts",
    readyEyebrow: "Ready to just view?", downloadTitle: "Open one image.<br />Let the arrow keys do the rest.", downloadNote: "macOS 13+ · Apple Silicon (arm64)", securityNote: "This public preview is ad-hoc signed and not Apple-notarized. If macOS shows a verification prompt on first launch, Control-click LumaView in Applications → Open → Open once more. Do not disable system-wide security.", footerTagline: "A local native image viewer · by ixiehao", footerIssues: "Feedback", footerReleases: "Releases"
  }
};

let language = "zh";
const switcher = document.querySelector(".language-switch");

function setLanguage(next) {
  language = next;
  document.documentElement.lang = next === "zh" ? "zh-CN" : "en";
  document.querySelectorAll("[data-i18n]").forEach((node) => { node.innerHTML = content[next][node.dataset.i18n]; });
  document.querySelectorAll("[data-i18n-alt]").forEach((node) => { node.alt = content[next][node.dataset.i18nAlt]; });
  document.querySelector(".language-label").textContent = next === "zh" ? "EN" : "中文";
  switcher.setAttribute("aria-pressed", String(next === "en"));
  switcher.setAttribute("aria-label", next === "zh" ? "Switch to English" : "切换到中文");
  document.title = next === "zh" ? "LumaView · 极简的本地原生看图软件" : "LumaView · Minimal native image viewing";
}

switcher.addEventListener("click", () => setLanguage(language === "zh" ? "en" : "zh"));

const observer = new IntersectionObserver(
  (entries) => entries.forEach((entry) => { if (entry.isIntersecting) entry.target.classList.add("visible"); }),
  { threshold: 0.12 }
);
document.querySelectorAll(".reveal").forEach((node) => observer.observe(node));
setLanguage(language);
