const content = {
  zh: {
    navExperience: "体验", navPrinciples: "优势", navDownload: "下载", eyebrow: "支持 Intel 与 Apple Silicon Mac",
    seoTitle: "LumaView · 极简的Mac原生看图软件", seoDescription: "一款极简的Mac原生看图软件。", seoSocialDescription: "一款极简的Mac原生看图软件。",
    heroTitle: "让图片，<br /><em>占满注意力。</em>", heroLede: "一款极简的Mac原生看图软件。",
    downloadButton: "下载 v1.2.2", sourceButton: "查看源码", compatibility: "macOS 13+ · Intel + Apple Silicon · 完全本地处理", heroCaption: "真实运行截图 · 文件夹浏览", heroImageAlt: "LumaView 在原生窗口中浏览图片，顶部有上一张、下一张、缩放和旋转操作", welcomeImageAlt: "LumaView 原生欢迎界面，中央保留一个打开文件操作",
    proofOne: "打开即看，画面居中", proofTwo: "方向键快速前后浏览", proofThree: "Intel + Apple Silicon 通用版",
    experienceEyebrow: "为看图而存在", experienceTitle: "少一点界面，<br />多一点画面。", welcomeCaption: "真实运行截图 · 欢迎界面",
    featureOneTitle: "文件夹里的上一张 / 下一张", featureOneBody: "直接从访达或“打开文件”进入。LumaView 先显示当前图，再轻量索引同级文件，工具栏和方向键都能自然切换。",
    featureTwoTitle: "大图按屏幕而生", featureTwoBody: "适合窗口、连续缩放、平移与旋转围绕画布本身设计；状态栏显示相对于原图的真实百分比。",
    featureThreeTitle: "不止 PNG 和 JPG", featureThreeBody: "JPEG、PNG、HEIC、GIF、TIFF、WebP、PDF、许多系统 RAW 格式与 Sketch 文档预览，都在本地完成。",
    principlesEyebrow: "为顺畅浏览而做", principlesTitle: "极简。极速。<br />极致轻量化。", principleOneTitle: "极简", principleOneBody: "一个浏览框，一组常用操作。打开即看，让画面保持中心。", principleTwoTitle: "极速", principleTwoBody: "迅捷浏览图片；上一张/下一张/放大/缩小/旋转...工具栏自然衔接。", principleThreeTitle: "极致轻量化", principleThreeBody: "安装包仅2M，将代码轻量化到极致。",
    readyEyebrow: "准备好只看图片了吗？", downloadTitle: "打开一张图。<br />剩下的，交给方向键。", downloadNote: "macOS 13+ · Universal (arm64 + x86_64)", securityNote: "当前为公开预览版，采用 ad-hoc 签名，尚未经过 Apple 公证。若首次启动出现验证提示，请在“应用程序”中 Control 点按 LumaView → “打开” → 再次“打开”；无需关闭系统级安全设置。", footerTagline: "本地原生图片浏览器 · 由 ixiehao 制作", footerIssues: "反馈", footerReleases: "版本"
  },
  en: {
    navExperience: "Experience", navPrinciples: "Principles", navDownload: "Download", eyebrow: "For Intel and Apple Silicon Macs",
    seoTitle: "LumaView · Minimal native image viewer for Mac", seoDescription: "A minimal native image viewer for Mac.", seoSocialDescription: "A minimal native image viewer for Mac.",
    heroTitle: "Let the image<br /><em>take your attention.</em>", heroLede: "A minimal native image viewer for Mac.",
    downloadButton: "Download v1.2.2", sourceButton: "View source", compatibility: "macOS 13+ · Intel + Apple Silicon · Local by default", heroCaption: "Real application screenshot · folder browsing", heroImageAlt: "LumaView browsing an image in its native window, with previous, next, zoom, and rotate controls", welcomeImageAlt: "LumaView native welcome screen with a single Open File action",
    proofOne: "Open and view immediately", proofTwo: "Arrow-key folder browsing", proofThree: "Universal for Intel + Apple Silicon",
    experienceEyebrow: "Made to view", experienceTitle: "Less interface.<br />More image.", welcomeCaption: "Real application screenshot · welcome screen",
    featureOneTitle: "Previous / next in the folder", featureOneBody: "Open from Finder or choose a file. LumaView shows it first, then lightly indexes sibling files for natural toolbar and arrow-key navigation.",
    featureTwoTitle: "Large images meet the screen", featureTwoBody: "Fit, continuous zoom, pan, and rotation are designed around the canvas; the status bar reports an honest percentage of the source image.",
    featureThreeTitle: "More than PNG and JPG", featureThreeBody: "JPEG, PNG, HEIC, GIF, TIFF, WebP, PDF, many system RAW formats, and Sketch document previews all stay local.",
    principlesEyebrow: "Built for fluid viewing", principlesTitle: "Minimal.<br />Fast. Lightweight.", principleOneTitle: "Minimal", principleOneBody: "One viewer and one set of essential controls. Open an image and let it remain the center.", principleTwoTitle: "Fast", principleTwoBody: "Browse swiftly; previous, next, zoom, and rotation flow naturally through the toolbar.", principleThreeTitle: "Extremely lightweight", principleThreeBody: "A 2 MB installer, with the code made as lightweight as possible.",
    readyEyebrow: "Ready to just view?", downloadTitle: "Open one image.<br />Let the arrow keys do the rest.", downloadNote: "macOS 13+ · Universal (arm64 + x86_64)", securityNote: "This public preview is ad-hoc signed and not Apple-notarized. If macOS shows a verification prompt on first launch, Control-click LumaView in Applications → Open → Open once more. Do not disable system-wide security.", footerTagline: "A local native image viewer · by ixiehao", footerIssues: "Feedback", footerReleases: "Releases"
  }
};

let language = "zh";
const switcher = document.querySelector(".language-switch");

function setLanguage(next) {
  language = next;
  const localized = content[next];
  document.documentElement.lang = next === "zh" ? "zh-CN" : "en";
  document.querySelectorAll("[data-i18n]").forEach((node) => { node.innerHTML = localized[node.dataset.i18n]; });
  document.querySelectorAll("[data-i18n-alt]").forEach((node) => { node.alt = localized[node.dataset.i18nAlt]; });
  document.querySelector(".language-label").textContent = next === "zh" ? "EN" : "中文";
  switcher.setAttribute("aria-pressed", String(next === "en"));
  switcher.setAttribute("aria-label", next === "zh" ? "Switch to English" : "切换到中文");
  document.title = localized.seoTitle;
  document.querySelector("#meta-description").content = localized.seoDescription;
  document.querySelector("#og-title").content = localized.seoTitle;
  document.querySelector("#twitter-title").content = localized.seoTitle;
  document.querySelector("#og-description").content = localized.seoSocialDescription;
  document.querySelector("#twitter-description").content = localized.seoSocialDescription;
  document.querySelector("#og-locale").content = next === "zh" ? "zh_CN" : "en_US";
}

switcher.addEventListener("click", () => setLanguage(language === "zh" ? "en" : "zh"));

const observer = new IntersectionObserver(
  (entries) => entries.forEach((entry) => { if (entry.isIntersecting) entry.target.classList.add("visible"); }),
  { threshold: 0.12 }
);
document.querySelectorAll(".reveal").forEach((node) => observer.observe(node));
setLanguage(language);
