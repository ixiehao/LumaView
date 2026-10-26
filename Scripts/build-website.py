#!/usr/bin/env python3
"""Generate crawlable locale pages from the root HTML and the shared copy file.

No third-party packages. Use --check in CI to detect stale generated pages.
"""
import argparse
import html
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parent.parent
SITE = ROOT / 'website'
BASE = 'https://ixiehao.github.io/LumaView/'
LOCALES = {
    'en': ('en', 'en_US', 'en/', 'English'),
    'zh': ('zh-CN', 'zh_CN', '', '中文'),
    'fr': ('fr', 'fr_FR', 'fr/', 'Français'),
    'ru': ('ru', 'ru_RU', 'ru/', 'Русский'),
    'es': ('es', 'es_ES', 'es/', 'Español'),
    'ja': ('ja', 'ja_JP', 'ja/', '日本語'),
    'ko': ('ko', 'ko_KR', 'ko/', '한국어'),
}

def generate(source, copy, language):
    code, og, path, label = LOCALES[language]
    url = BASE + path
    text = source
    for key, value in copy.items():
        pattern = r'(<([\w-]+)\b[^>]*\bdata-i18n="' + re.escape(key) + r'"[^>]*>)[\s\S]*?(</\2>)'
        text = re.sub(pattern, lambda m: m[1] + value + m[3], text)
    def alt(m):
        tag = m[0]
        key = re.search(r'data-i18n-alt="([^"]+)"', tag)[1]
        return re.sub(r'(?<!-)\balt="[^"]*"', lambda _: 'alt="' + html.escape(copy[key], quote=True) + '"', tag)
    text = re.sub(r'<img\b[^>]*data-i18n-alt="[^"]+"[^>]*>', alt, text)
    def aria(m):
        tag = m[0]
        key = re.search(r'data-i18n-aria="([^"]+)"', tag)[1]
        return re.sub(r'aria-label="[^"]*"', lambda _: 'aria-label="' + html.escape(copy[key], quote=True) + '"', tag)
    text = re.sub(r'<[\w-]+\b[^>]*data-i18n-aria="[^"]+"[^>]*>', aria, text)
    text = re.sub(r'<html lang="[^"]+">', f'<html lang="{code}">', text)
    text = re.sub(r'<title>.*?</title>', lambda _: '<title>' + html.escape(copy['seoTitle']) + '</title>', text)
    metadata = {'meta-description':copy['seoDescription'], 'og-title':copy['seoTitle'], 'twitter-title':copy['seoTitle'],
                'og-description':copy['seoSocialDescription'], 'twitter-description':copy['seoSocialDescription'],
                'og-image-alt':copy['heroImageAlt'], 'twitter-image-alt':copy['heroImageAlt'], 'og-locale':og, 'og-url':url}
    for key, value in metadata.items():
        text = re.sub(r'(<meta id="' + key + r'"[^>]*content=")[^"]*', lambda m:m[1]+html.escape(value,quote=True), text)
    text = re.sub(r'(<link id="canonical-url"[^>]*href=")[^"]*', lambda m:m[1]+url, text)
    text = re.sub(r'    <link rel="alternate"[^>]*>\n', '', text)
    links = '\n'.join(f'    <link rel="alternate" hreflang="{data[0]}" href="{BASE + data[2]}" />' for data in LOCALES.values())
    links += f'\n    <link rel="alternate" hreflang="x-default" href="{BASE}" />'
    text = re.sub(r'(    <link id="canonical-url"[^>]*>)', lambda m: m[0]+'\n'+links, text)
    text = re.sub(r'<meta property="og:locale:alternate"[^>]*>\s*', '', text)
    alternates = '\n    '.join(f'<meta property="og:locale:alternate" content="{data[1]}" />' for key,data in LOCALES.items() if key != language)
    text = text.replace('    <meta property="og:image"', '    '+alternates+'\n    <meta property="og:image"', 1)
    schema_match = re.search(r'(<script id="software-schema"[^>]*>)([\s\S]*?)(</script>)', text)
    schema = json.loads(schema_match[2]);schema.update(url=url, description=copy['seoDescription'], inLanguage=code)
    text = text[:schema_match.start()] + schema_match[1]+'\n'+json.dumps(schema,ensure_ascii=False,indent=2)+'\n    '+schema_match[3]+text[schema_match.end():]
    prefix = '../' if path else './'
    options = '\n'.join(
        f'          <li><a href="{prefix + data[2]}" data-language="{key}" lang="{data[0]}" hreflang="{data[0]}"' +
        (' aria-current="page"' if key == language else '') + f'><span>{data[3]}</span>' +
        '<svg aria-hidden="true"><use href="assets/tabler-icons.svg?v=20261026-language-menu#check"></use></svg></a></li>'
        for key, data in LOCALES.items())
    text = re.sub(r'(<ul id="language-options"[^>]*>)[\s\S]*?(</ul>)', lambda m:m[1]+'\n'+options+'\n        '+m[2], text)
    text = re.sub(r'<span id="current-language"[^>]*>.*?</span>',
                  lambda _: f'<span id="current-language" lang="{code}">{label}</span>', text)
    if path:
        text = re.sub(r'((?:src|href)=")(assets/|styles.css|app.js|manifest.webmanifest)',r'\1../\2',text)
    return text

def sitemap():
    links = ''.join(f'    <xhtml:link rel="alternate" hreflang="{data[0]}" href="{BASE + data[2]}" />\n' for data in LOCALES.values())
    links += f'    <xhtml:link rel="alternate" hreflang="x-default" href="{BASE}" />\n'
    urls = ''.join(f'  <url>\n    <loc>{BASE + data[2]}</loc>\n'+links+'  </url>\n' for data in LOCALES.values())
    return '<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" xmlns:xhtml="http://www.w3.org/1999/xhtml">\n'+urls+'</urlset>\n'

def main():
    check=argparse.ArgumentParser();check.add_argument('--check',action='store_true');args=check.parse_args()
    source=(SITE/'index.html').read_text()
    content=json.loads((SITE/'content.json').read_text())
    if set(content) != set(LOCALES) or any(set(copy) != set(content['en']) for copy in content.values()):
        raise SystemExit('Every website language must provide the same content keys.')
    stale=[]
    for language,data in LOCALES.items():
        target=SITE/data[2]/'index.html';output=generate(source,content[language],language)
        if args.check:
            if not target.exists() or target.read_text()!=output:stale.append(str(target.relative_to(ROOT)))
        else:
            target.parent.mkdir(parents=True,exist_ok=True);target.write_text(output)
    target = SITE/'sitemap.xml'; output = sitemap()
    if args.check:
        if target.read_text() != output: stale.append('website/sitemap.xml')
    else: target.write_text(output)
    if stale:raise SystemExit('Run python3 Scripts/build-website.py: '+', '.join(stale))
    print('Seven static locale pages checked.' if args.check else 'Generated seven locale pages and sitemap.')

if __name__=='__main__': main()
