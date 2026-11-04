# LumaView website maintenance

[Documentation index](README.md) · [Development](DEVELOPMENT.md)

## Source and public URL

- Source: [`website/`](../website/), not the repository root or `docs/`.
- Public URL: https://ixiehao.github.io/LumaView/
- Deployment: [`.github/workflows/deploy-pages.yml`](../.github/workflows/deploy-pages.yml).
- Languages, in menu order: English `/` (default), 简体中文 `/zh/`, Français `/fr/`, Русский `/ru/`, Español `/es/`, 日本語 `/ja/`, 한국어 `/ko/`. Arabic is not included. The legacy `/en/` address remains an English page with `/` as its canonical URL. The default page does not depend on browser language or JavaScript.
- Copy: `website/content.json`; layout: `website/index.html`. Run `python3 Scripts/build-website.py` after changing either. Commit the generated locale pages together.
- Every locale includes its own text, title, description, canonical, language tags and structured data in the initial HTML. The language disclosure uses native HTML details and links, works without JavaScript, and marks the current language. JavaScript adds arrow-key navigation, Escape/outside dismissal and old `?lang=` redirects. Each language has a localized installation dialog; both installation buttons open it without navigation.

`website/` is a source directory, not part of the public URL. Keep the public address and existing external links unchanged.

## Local preview

Run from the repository root:

```sh
python3 -m http.server 8000 --bind 127.0.0.1 --directory website
```

Open <http://127.0.0.1:8000/>. Use HTTP rather than opening files directly, especially when testing fetched resources.

## Validation

```sh
python3 Scripts/build-website.py --check
node --check website/app.js
git diff --check
```

Check images, favicon, navigation, official download destinations, desktop and narrow layouts, keyboard focus, language switching, localized metadata and download/signing wording. Check canonical and share URLs, robots and sitemap where present. A path-only migration should preserve site content.

## Automated responsive checks

Website changes and pull requests run Playwright before Pages deployment. CI reads the actual language list from `website-test.config.mjs`, runs Chromium and WebKit for each language, and publishes only when every matrix job passes. Pull requests never deploy; a failure keeps the existing public site.

From the repository root:

```sh
npm ci --ignore-scripts
npx playwright install chromium webkit
npm run check:website
npm run test:website
# Reproduce one CI job (choose a language supported by this website):
SITE_TEST_LANGUAGE=en npm run test:website -- --project=webkit
npm run test:website:report
```

The checks cover phone portrait/landscape, tablet and desktop sizes, both sides of this site's CSS breakpoints, actual mobile viewport width, local image decoding and aspect ratios, content overflow, overlapping controls, component bounds and column counts. They also check static HTML without JavaScript, language navigation and installation-dialog bounds, scrolling, Escape and focus restoration. Test fixtures deliberately inject overflow to verify that the guard rejects broken layouts. Intentional horizontal navigation/code scrolling and text ellipses are treated separately from unintended clipping.

The test server uses the public URL prefix and starts/stops with Playwright. Set `SITE_TEST_PORT` if port 4173 is occupied. External requests are blocked for deterministic layout checks; upstream download availability still needs separate verification. Mobile browser emulation does not replace real-device review.

Download `website-report-*` from the workflow run's **Artifacts**; each browser/language report is retained for 7 days. The HTML report includes failure screenshots, traces and geometry attachments; `test-results/report.json` provides counts. Run `npx playwright show-report <downloaded-playwright-report-directory>` to inspect a downloaded report. Test dependencies and reports are excluded from the published site. Local shared maintenance documents stay outside this repository.

## Deployment

The workflow uploads `website/` and deploys it as the site root. It runs on relevant changes to `main` and supports manual dispatch. Pages should be configured to use **GitHub Actions**; moving the source directory must be accompanied by the matching workflow path update.

Only publish when authorized. After deployment, read the public URL back and verify resources, navigation and downloads. A successful local preview is not proof that the public site has updated.
