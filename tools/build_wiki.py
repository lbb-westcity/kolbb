#!/usr/bin/env python3
"""Build the wiki: python3 tools/build_wiki.py (requires Python-Markdown)."""
from html import escape
from pathlib import Path
import re
import shutil
from urllib.parse import quote

import markdown

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'docs/wiki'
OUTPUT = ROOT / 'build/wiki'
PAGES = ['README', 'getting-started', 'rajerwei', 'ju-guai', 'little-black', 'combat', 'food', 'moves', 'online']
LABELS = ['百科首页', '新手入门', 'RajerWei', 'JU GUAI', 'little black', '战斗系统', '食物与召唤', '完整招式数据', '联机与问题']


def page_name(stem):
    return 'index.html' if stem == 'README' else stem + '.html'


def build():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(SOURCE / 'wiki.css', OUTPUT / 'wiki.css')
    for stem, label in zip(PAGES, LABELS):
        source = SOURCE / (stem + '.md')
        content = markdown.markdown(source.read_text(), extensions=['tables', 'fenced_code', 'toc'])

        def rewrite(match):
            attribute, target = match.groups()
            if target.startswith(('#', 'http://', 'https://', 'mailto:')):
                return match.group(0)
            path, _, fragment = target.partition('#')
            resolved = (SOURCE / path).resolve()
            relative = resolved.relative_to(ROOT)
            if not resolved.is_file():
                raise FileNotFoundError(resolved)
            if resolved.parent == SOURCE and resolved.stem in PAGES:
                target = page_name(resolved.stem) + ('#' + fragment if fragment else '')
            elif attribute == 'src':
                destination = OUTPUT / relative
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(resolved, destination)
                target = relative.as_posix()
            else:
                target = 'https://github.com/lbb-westcity/kolbb/blob/main/' + quote(relative.as_posix())
                if fragment:
                    target += '#' + fragment
            return f'{attribute}="{escape(target, quote=True)}"'

        content = re.sub(r'(href|src)="([^"]+)"', rewrite, content)
        content = content.replace('<table>', '<div class="table-scroll" tabindex="0" role="region" aria-label="数据表格，可横向滚动"><table>').replace('</table>', '</table></div>')
        nav = ''.join(f'<a href="{page_name(p)}"' + (' aria-current="page"' if p == stem else '') + f'>{escape(n)}</a>' for p, n in zip(PAGES, LABELS))
        headings = re.findall(r'<h2 id="([^"]+)">(.*?)</h2>', content)
        toc = ''.join(f'<a href="#{anchor}">{title}</a>' for anchor, title in headings)
        html = f'''<!doctype html>
<html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>{escape(label)} · KOLBB 下班百科</title><meta name="description" content="KOLBB 中文游戏百科：角色、出招表、战斗机制与互联网对战指南。">
<link rel="stylesheet" href="wiki.css"></head><body>
<a class="skip" href="#content">跳到正文</a>
<header><a class="brand" href="index.html">KOLBB <span>下班百科</span></a><span class="edition">AFTER HOURS / WIKI</span></header>
<div class="layout"><aside><p class="eyebrow">办公室生存手册</p><nav aria-label="百科栏目">{nav}</nav><p class="sidebar-note">3 位角色 · 13 个技能<br>今天的班，就上到这里。</p></aside>
<main id="content"><div class="article-meta">KOLBB / 玩家百科</div><article>{content}</article><footer>依据游戏 0.1.2 实现整理 · 2026.09.11 · <a href="index.html">返回百科首页</a></footer></main>
<aside class="contents"><p class="eyebrow">本页目录</p><nav aria-label="本页目录">{toc}</nav></aside></div></body></html>'''
        (OUTPUT / page_name(stem)).write_text(html)
    print(f'Built {len(PAGES)} pages in {OUTPUT}')


if __name__ == '__main__':
    build()
