// Language links remain usable without JavaScript.
const languageSwitch = document.querySelector("#language-switch");
const languageTrigger = languageSwitch.querySelector("summary");
const languageLinks = Array.from(languageSwitch.querySelectorAll("a[data-language]"));
const requested = new URLSearchParams(location.search).get("lang");
const requestedLink = languageLinks.find(link => link.dataset.language === requested);
if (requestedLink) {
  const target = new URL(requestedLink.href);
  target.hash = location.hash;
  location.replace(target.href);
}
for (const link of languageLinks) {
  link.addEventListener("click", () => { link.hash = location.hash; });
}
languageSwitch.addEventListener("keydown", event => {
  if (event.key === "Escape" && languageSwitch.open) {
    event.preventDefault();
    languageSwitch.open = false;
    languageTrigger.focus();
  } else if (["ArrowDown", "ArrowUp", "Home", "End"].includes(event.key)) {
    event.preventDefault();
    languageSwitch.open = true;
    const index = languageLinks.indexOf(document.activeElement);
    const next = event.key === "Home" ? 0 : event.key === "End" ? languageLinks.length - 1 :
      event.key === "ArrowDown" ? (index + 1) % languageLinks.length :
      (index < 0 ? languageLinks.length - 1 : (index - 1 + languageLinks.length) % languageLinks.length);
    languageLinks[next].focus();
  }
});
document.addEventListener("pointerdown", event => {
  if (!languageSwitch.contains(event.target)) languageSwitch.open = false;
});
languageSwitch.addEventListener("focusout", event => {
  if (!languageSwitch.contains(event.relatedTarget)) languageSwitch.open = false;
});

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
