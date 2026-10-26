// Preserve previously shared query-language links; visible content is static HTML.
const requested = new URLSearchParams(location.search).get("lang");
if (["zh", "en", "ja"].includes(requested)) {
  const root = document.querySelector("link[hreflang='zh-CN']").href;
  const target = new URL(requested === "zh" ? "./" : requested + "/", root);
  target.hash = location.hash;
  location.replace(target.href);
}
