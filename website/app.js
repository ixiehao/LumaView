// Preserve previously shared query-language links; visible content is static HTML.
const requested = new URLSearchParams(location.search).get("lang");
if (["zh", "en", "ja"].includes(requested)) {
  const root = document.querySelector("link[hreflang='zh-CN']").href;
  const target = new URL(requested === "zh" ? "./" : requested + "/", root);
  target.hash = location.hash;
  location.replace(target.href);
}

// One native dialog serves both installation buttons without leaving the page.
const installDialog = document.querySelector("#install-dialog");
let installTrigger;
for (const button of document.querySelectorAll("[data-install-guide]")) {
  button.addEventListener("click", () => {
    installTrigger = button;
    installDialog.showModal();
    document.body.classList.add("modal-open");
  });
}
installDialog.querySelector("[data-close-dialog]").addEventListener("click", () => installDialog.close());
installDialog.addEventListener("click", (event) => {
  if (event.target !== installDialog) return;
  const bounds = installDialog.getBoundingClientRect();
  if (event.clientX < bounds.left || event.clientX > bounds.right ||
      event.clientY < bounds.top || event.clientY > bounds.bottom) installDialog.close();
});
installDialog.addEventListener("close", () => {
  document.body.classList.remove("modal-open");
  installTrigger?.focus({ preventScroll: true });
});
