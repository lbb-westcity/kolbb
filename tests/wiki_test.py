"""Run after python3 tools/build_wiki.py; no browser or server required."""
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import unquote, urlsplit

ROOT = Path(__file__).resolve().parents[1] / 'build/wiki'


class Page(HTMLParser):
    def __init__(self, path):
        super().__init__()
        self.ids, self.links, self.active = set(), [], 0
        self.feed(path.read_text())

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if 'id' in attrs:
            assert attrs['id'] not in self.ids, attrs['id']
            self.ids.add(attrs['id'])
        self.active += attrs.get('aria-current') == 'page'
        for attr in ('href', 'src'):
            if attr in attrs:
                self.links.append(attrs[attr])


pages = {p: Page(p) for p in ROOT.glob('*.html')}
assert len(pages) == 9
for path, page in pages.items():
    assert page.active == 1, path
    for link in page.links:
        url = urlsplit(link)
        if url.scheme or url.netloc:
            continue
        target = (path.parent / unquote(url.path)).resolve() if url.path else path
        assert target.is_relative_to(ROOT), link
        assert target.is_file(), (path.name, link)
        if url.fragment and target in pages:
            assert unquote(url.fragment) in pages[target].ids, (path.name, link)
assert '40 × 5' in (ROOT / 'moves.html').read_text()
assert '服务器地址' in (ROOT / 'online.html').read_text()
print('PASS: 9 pages, navigation, local links, images and heading anchors')

assert '露出鸡脚' in (ROOT / 'little-black.html').read_text()
