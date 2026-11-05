#!/usr/bin/env python3
"""Generate and validate search/AI reading files from the real static website.

Python standard library only. No browser dependencies, analytics or login data.
"""
import argparse
from html.parser import HTMLParser
import json
from pathlib import Path
import re
import sys
import unittest
from urllib.parse import urljoin, urlsplit
from urllib.request import Request, urlopen
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parent.parent
LANGUAGE_NAMES = {'en': 'English', 'zh': '简体中文', 'fr': 'Français', 'ru': 'Русский', 'es': 'Español', 'ja': '日本語', 'ko': '한국어'}
VOID = {'area', 'base', 'br', 'col', 'embed', 'hr', 'img', 'input', 'link', 'meta', 'param', 'source', 'track', 'wbr'}
SKIP = { 'nav', 'script', 'style', 'svg', 'noscript', 'template', 'button', 'input', 'select'}

class Node:
    def __init__(self, tag='', attrs=(), parent=None):
        self.tag, self.attrs, self.children, self.parent = tag, dict(attrs), [], parent

    def nodes(self):
        yield self
        for child in self.children:
            if isinstance(child, Node):
                yield from child.nodes()

    def text(self):
        return ''.join(child.text() if isinstance(child, Node) else child for child in self.children)

class Document(HTMLParser):
    def __init__(self, html):
        super().__init__(convert_charrefs=True)
        self.root = Node()
        self.stack = [self.root]
        self.feed(html)

    def handle_starttag(self, tag, attrs):
        node = Node(tag, attrs, self.stack[-1])
        self.stack[-1].children.append(node)
        if tag not in VOID:
            self.stack.append(node)

    def handle_endtag(self, tag):
        for index in range(len(self.stack)-1, 0, -1):
            if self.stack[index].tag == tag:
                self.stack = self.stack[:index]
                return

    def handle_data(self, data):
        self.stack[-1].children.append(data)

    def find(self, tag, **attrs):
        return next((node for node in self.root.nodes() if node.tag == tag and all(node.attrs.get(k) == v for k, v in attrs.items())), None)

def require(condition, message):
    if not condition:
        raise ValueError(message)

def markdown(node, canonical):
    if isinstance(node, str):
        return re.sub(r'\s+', ' ', node).replace('\\', '\\\\').replace('[', '\\[').replace(']', '\\]')
    if node.tag == 'header' and ('site-header' in node.attrs.get('class', '').split() or node.parent.tag == 'body'):
        return ''
    if node.tag in SKIP or node.attrs.get('aria-hidden') == 'true' or 'skip-link' in node.attrs.get('class', '').split():
        return ''
    if node.tag == 'pre':
        text = node.text().strip()
        fence = '````' if '```' in text else '```'
        return '\n\n' + fence + '\n' + text + '\n' + fence + '\n\n'
    content = ''.join(markdown(child, canonical) for child in node.children)
    if node.tag == 'br':
        return '\n'
    if node.tag == 'img':
        ancestor = node.parent
        while ancestor:
            if ancestor.tag == 'a':
                return ''
            ancestor = ancestor.parent
        alt, src = node.attrs.get('alt', ''), node.attrs.get('src', '')
        return f'\n\n![{alt}]({urljoin(canonical, src)})\n\n' if alt and src else ''
    if node.tag == 'a':
        href = urljoin(canonical, node.attrs.get('href', ''))
        label = re.sub(r'\s+', ' ', content).strip()
        if not label:
            label = ' '.join(item.attrs.get('alt', '') for item in node.nodes() if item.tag == 'img').strip()
        return f'[{label}]({href})' if label and urlsplit(href).scheme in ('http', 'https', 'mailto') else label
    if re.fullmatch(r'h[1-6]', node.tag):
        return '\n\n' + '#' * min(6, int(node.tag[1])+1) + ' ' + re.sub(r'\s+', ' ', content).strip() + '\n\n'
    if node.tag == 'li':
        prefix = '- '
        if node.parent.tag == 'ol':
            items = [child for child in node.parent.children if isinstance(child, Node) and child.tag == 'li']
            prefix = f'{items.index(node)+1}. '
        return '\n' + prefix + re.sub(r'\s+', ' ', content).strip() + '\n'
    if node.tag in ('strong', 'b'):
        return f' **{content.strip()}** '
    if node.tag == 'code':
        return f'`{node.text()}`'
    if node.tag == 'summary':
        return '\n\n**' + content.strip() + '**\n\n'
    if node.tag in ('p', 'div', 'section', 'article', 'aside', 'figure', 'figcaption', 'footer', 'dialog', 'ul', 'ol', 'dl', 'dt', 'dd'):
        return '\n\n' + content.strip() + '\n\n'
    return content

def language_ids(config):
    source = config.get('language_source')
    if source and source.endswith('.json') and '*' not in source:
        ids = list(json.loads((ROOT/source).read_text()))
    elif source:
        ids = [path.stem for path in sorted(ROOT.glob(source))]
    else:
        ids = config['languages']
    require(len(ids) == len(set(ids)) and 'en' in ids and all(isinstance(item, str) and re.fullmatch(r'[a-z]{2,3}(?:-[A-Za-z0-9]{2,8})*', item) for item in ids), 'Invalid language source')
    return ['en'] + [item for item in ids if item != 'en']

def page_url(config, language):
    return config['site_url'] + ('' if language == 'en' else language + '/')

def inspect_page(html, canonical, language, urls):
    doc = Document(html)
    root, main, title = doc.find('html'), doc.find('main'), doc.find('title')
    require(root is not None and root.attrs.get('lang', '').split('-')[0] == language, f'{canonical}: wrong HTML language')
    require(main is not None and len(re.sub(r'\s+', '', main.text())) > 80, f'{canonical}: missing static body')
    require(title is not None and title.text().strip(), f'{canonical}: missing title')
    require(len([node for node in doc.root.nodes() if node.tag == 'h1']) == 1, f'{canonical}: expected one H1')
    require(not re.search(r'\{\{\s*\w+\s*\}\}', main.text()), f'{canonical}: unresolved template')
    link = doc.find('link', rel='canonical')
    require(link is not None and link.attrs.get('href') == canonical, f'{canonical}: wrong canonical')
    description = doc.find('meta', name='description')
    require(description is not None and description.attrs.get('content', '').strip(), f'{canonical}: missing description')
    for key in ('og:title', 'og:description', 'og:locale', 'og:image'):
        value = doc.find('meta', property=key)
        require(value is not None and value.attrs.get('content', '').strip(), f'{canonical}: missing {key}')
    sharing = doc.find('meta', property='og:url')
    require(sharing is not None and sharing.attrs.get('content') == canonical, f'{canonical}: wrong sharing URL')
    for key, href in urls.items():
        candidates = [node for node in doc.root.nodes() if node.tag == 'link' and node.attrs.get('hreflang', '').split('-')[0] == key]
        require(any(node.attrs.get('href') == href for node in candidates), f'{canonical}: missing hreflang {key}')
    fallback = doc.find('link', hreflang='x-default')
    require(fallback is not None and fallback.attrs.get('href') == urls['en'], f'{canonical}: wrong x-default')
    md = doc.find('link', type='text/markdown')
    require(md is not None and urljoin(canonical, md.attrs.get('href', '')) == canonical+'index.md', f'{canonical}: missing Markdown alternate')
    descriptor = doc.find('link', rel='describedby')
    require(descriptor is not None and urljoin(canonical, descriptor.attrs.get('href', '')) == urls['en']+'llms.txt', f'{canonical}: missing AI reading index')
    schemas = [json.loads(node.text()) for node in doc.root.nodes() if node.tag == 'script' and node.attrs.get('type') == 'application/ld+json']
    require(schemas, f'{canonical}: missing structured data')
    graphs = [entry for schema in schemas for entry in schema.get('@graph', [schema])]
    require(any(node.get('@type') in ('SoftwareApplication', 'WebSite', 'ProfilePage') for node in graphs), f'{canonical}: missing page/application schema')
    for node in graphs:
        if node.get('@type') == 'SoftwareApplication':
            require(node.get('url') == canonical and node.get('description') == description.attrs['content'], f'{canonical}: application facts differ from metadata')
    body = markdown(doc.find('body'), canonical)
    text = '# ' + title.text().strip() + '\n\n> ' + description.attrs['content'].strip() + '\n\n<' + canonical + '>\n\n' + body
    text = re.sub(r'[\t ]+\n', '\n', text)
    text = re.sub(r'\n{3,}', '\n\n', text).strip() + '\n'
    return text, description.attrs['content']

def compare_or_write(path, value, check):
    if check:
        require(path.is_file() and path.read_text() == value, f'Stale or missing {path.name}: run npm run build:website')
    else:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(value)

def ownership_key(config):
    value = (ROOT/config['key_file']).read_text().strip()
    require(re.fullmatch(r'[a-f0-9]{32}', value) is not None, 'Invalid project-specific IndexNow ownership key')
    return value

def build(config, check=False):
    directory = ROOT/config['directory']
    ids = language_ids(config)
    urls = {language: page_url(config, language) for language in ids}
    site = config['site_url']
    sitemap = ET.fromstring((directory/'sitemap.xml').read_text())
    locations = [node.text for node in sitemap.findall('{*}url/{*}loc')]
    require(len(locations) == len(urls) and set(locations) == set(urls.values()), 'Sitemap does not match actual canonical languages')
    summaries = {}
    for language, canonical in urls.items():
        folder = directory/('' if language == 'en' else language)
        text, description = inspect_page((folder/'index.html').read_text(), canonical, language, urls)
        summaries[language] = description
        compare_or_write(folder/'index.md', text, check)
    lines = ['# '+config['name'], '', '> '+summaries['en'], '', '## Pages', '']
    lines += [f'- [{LANGUAGE_NAMES.get(language, language)}]({canonical}index.md)' for language, canonical in urls.items()]
    if config.get('projects'):
        lines += ['', '## Projects', '']
        lines += [f'- [{project["name"]}]({project["url"]}): {project["description"]}' for project in config['projects']]
    lines += ['', '## Optional', '', f'- [Source and project documentation]({config["source_url"]})', '']
    compare_or_write(directory/'llms.txt', '\n'.join(lines), check)
    compare_or_write(directory/'indexnow-key.txt', ownership_key(config)+'\n', check)
    for url in config.get('root_sitemaps', []):
        require('Sitemap: '+url in (directory/'robots.txt').read_text(), 'Domain-root robots is missing '+url)
    return len(ids)

def notification(config):
    base = config['site_url']
    origin = urlsplit(base)
    require(origin.scheme == 'https' and base.endswith('/') and not origin.query and not origin.fragment, 'Use the production HTTPS directory')
    urls = [page_url(config, language) for language in language_ids(config)]
    require(all(url.startswith(base) and not urlsplit(url).query for url in urls), 'URLs must stay in this project scope')
    return {'host': origin.netloc, 'key': ownership_key(config), 'keyLocation': base+'indexnow-key.txt', 'urlList': urls}

def notify(config):
    payload = notification(config)
    with urlopen(payload['keyLocation'], timeout=20) as response:
        require(response.status == 200 and response.read().decode().strip() == payload['key'], 'Published ownership key is not ready; retry after propagation')
    request = Request('https://api.indexnow.org/indexnow', data=json.dumps(payload).encode(), headers={'Content-Type': 'application/json; charset=utf-8'}, method='POST')
    with urlopen(request, timeout=20) as response:
        require(response.status in (200, 202), f'IndexNow HTTP {response.status}')
        print(f'IndexNow HTTP {response.status}: {len(payload["urlList"])} URLs received'+('; key verification pending' if response.status == 202 else '')+'. Indexing and AI citations are not confirmed.')

class SelfTests(unittest.TestCase):
    def test_markdown_preserves_real_text_links_and_commands(self):
        doc = Document('<body><header>Menu</header><main><h1>日本語</h1><p>说明 <a href="download/">下载</a></p><pre>brew install ffmpeg</pre><script>tracking()</script></main></body>')
        text = markdown(doc.find('body'), 'https://example.com/app/')
        self.assertIn('日本語', text)
        self.assertIn('[下载](https://example.com/app/download/)', text)
        self.assertIn('brew install ffmpeg', text)
        self.assertNotIn('tracking()', text)
        self.assertNotIn('Menu', text)

    def test_linked_product_cards_keep_readable_labels(self):
        doc = Document('<a href="app/"><img alt="App icon" src="icon.png"><strong>App</strong><span>Browse images</span></a>')
        self.assertEqual(markdown(doc.find('a'), 'https://example.com/'), '[**App** Browse images](https://example.com/app/)')

    def test_language_paths_cannot_escape_the_project(self):
        with self.assertRaisesRegex(ValueError, 'Invalid language'):
            language_ids({'languages': ['en', '../other-project']})

    def test_preview_and_insecure_urls_cannot_be_submitted(self):
        with self.assertRaisesRegex(ValueError, 'production HTTPS'):
            notification({'site_url': 'http://localhost:8000/'})

    def test_missing_body_is_rejected(self):
        with self.assertRaisesRegex(ValueError, 'missing static body'):
            inspect_page('<html lang="en"><body><main></main></body></html>', 'https://example.com/', 'en', {'en': 'https://example.com/'})

    def test_stale_generated_file_is_rejected_without_rewriting(self):
        import tempfile
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp)/'index.md'
            path.write_text('old')
            with self.assertRaisesRegex(ValueError, 'Stale'):
                compare_or_write(path, 'new', True)
            self.assertEqual(path.read_text(), 'old')

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--check', action='store_true')
    parser.add_argument('--notify', action='store_true')
    parser.add_argument('--self-test', action='store_true')
    args = parser.parse_args()
    if args.self_test:
        result = unittest.TextTestRunner().run(unittest.defaultTestLoader.loadTestsFromTestCase(SelfTests))
        return 0 if result.wasSuccessful() else 1
    config = json.loads((ROOT/'search-content.config.json').read_text())
    if args.notify:
        notify(config)
    else:
        count = build(config, args.check)
        print(f'{config["name"]}: {"checked" if args.check else "generated"} {count} Markdown editions, llms.txt, metadata and canonical routes.')
    return 0

if __name__ == '__main__':
    try:
        sys.exit(main())
    except (ValueError, OSError, ET.ParseError) as error:
        print(f'Search content error: {error}', file=sys.stderr)
        sys.exit(1)
