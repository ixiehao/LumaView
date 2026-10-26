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
LOCALES = {'zh': ('zh-CN', 'zh_CN', '', 'en/', 'EN', 'Switch to English', 'README.zh-CN.md#首次打开被系统拦截时'),
           'en': ('en', 'en_US', 'en/', '../ja/', '日本語', 'Switch to Japanese', 'README.md#if-macos-blocks-the-first-launch'),
           'ja': ('ja', 'ja_JP', 'ja/', '../', '中文', '中国語に切り替え', 'README.ja.md#初回起動がブロックされる場合')}

def generate(source, copy, language):
    code, og, path, next_path, label, switch_label, guide = LOCALES[language]
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
    text = re.sub(r'<html lang="[^"]+">', f'<html lang="{code}">', text)
    text = re.sub(r'<title>.*?</title>', lambda _: '<title>' + html.escape(copy['seoTitle']) + '</title>', text)
    metadata = {'meta-description':copy['seoDescription'], 'og-title':copy['seoTitle'], 'twitter-title':copy['seoTitle'],
                'og-description':copy['seoSocialDescription'], 'twitter-description':copy['seoSocialDescription'],
                'og-image-alt':copy['heroImageAlt'], 'twitter-image-alt':copy['heroImageAlt'], 'og-locale':og, 'og-url':url}
    for key, value in metadata.items():
        text = re.sub(r'(<meta id="' + key + r'"[^>]*content=")[^"]*', lambda m:m[1]+html.escape(value,quote=True), text)
    text = re.sub(r'(<link id="canonical-url"[^>]*href=")[^"]*', lambda m:m[1]+url, text)
    text = re.sub(r'<meta property="og:locale:alternate"[^>]*>\s*', '', text)
    alternates = '\n    '.join(f'<meta property="og:locale:alternate" content="{data[1]}" />' for key,data in LOCALES.items() if key != language)
    text = text.replace('    <meta property="og:image"', '    '+alternates+'\n    <meta property="og:image"', 1)
    schema_match = re.search(r'(<script id="software-schema"[^>]*>)([\s\S]*?)(</script>)', text)
    schema = json.loads(schema_match[2]);schema.update(url=url, description=copy['seoDescription'], inLanguage=code)
    text = text[:schema_match.start()] + schema_match[1]+'\n'+json.dumps(schema,ensure_ascii=False,indent=2)+'\n    '+schema_match[3]+text[schema_match.end():]
    text = re.sub(r'(<a class="language-switch"[^>]*href=")[^"]*',lambda m:m[1]+next_path,text)
    text = re.sub(r'(<a class="language-switch"[^>]*aria-label=")[^"]*',lambda m:m[1]+switch_label,text)
    text = re.sub(r'(<span class="language-label">).*?(</span>)',lambda m:m[1]+label+m[2],text)
    text = re.sub(r'(<a class="install-guide"[^>]*href=")[^"]*',lambda m:m[1]+'https://github.com/ixiehao/LumaView/blob/main/'+guide,text)
    if path:
        text = re.sub(r'((?:src|href)=")(assets/|styles.css|app.js|manifest.webmanifest)',r'\1../\2',text)
    return text

def main():
    check=argparse.ArgumentParser();check.add_argument('--check',action='store_true');args=check.parse_args()
    source=(SITE/'index.html').read_text()
    content=json.loads((SITE/'content.json').read_text())
    stale=[]
    for language,data in LOCALES.items():
        target=SITE/data[2]/'index.html';output=generate(source,content[language],language)
        if args.check:
            if not target.exists() or target.read_text()!=output:stale.append(str(target.relative_to(ROOT)))
        else:
            target.parent.mkdir(parents=True,exist_ok=True);target.write_text(output)
    if stale:raise SystemExit('Run python3 Scripts/build-website.py: '+', '.join(stale))
    print('Static locale pages checked.' if args.check else 'Generated zh, en, ja pages.')

if __name__=='__main__': main()
