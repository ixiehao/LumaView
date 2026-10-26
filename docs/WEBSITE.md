# LumaView website maintenance

[Documentation index](README.md) · [Development](DEVELOPMENT.md)

## Source and public URL

- Source: [`website/`](../website/), not the repository root or `docs/`.
- Public URL: https://ixiehao.github.io/LumaView/
- Deployment: [`.github/workflows/deploy-pages.yml`](../.github/workflows/deploy-pages.yml).
- Languages: Simplified Chinese at `/`, English at `/en/`, Japanese at `/ja/`.
- Copy: `website/content.json`; layout: `website/index.html`. Run `python3 Scripts/build-website.py` after changing either. Commit the generated locale pages together.
- Every locale includes its own text, title, description, canonical, language tags and structured data in the initial HTML. Language links work without JavaScript; the small script only redirects old `?lang=` links.

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

## Deployment

The workflow uploads `website/` and deploys it as the site root. It runs on relevant changes to `main` and supports manual dispatch. Pages should be configured to use **GitHub Actions**; moving the source directory must be accompanied by the matching workflow path update.

Only publish when authorized. After deployment, read the public URL back and verify resources, navigation and downloads. A successful local preview is not proof that the public site has updated.
