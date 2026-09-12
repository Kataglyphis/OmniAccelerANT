#!/usr/bin/env python3
"""Render staged Markdown guides into a `dart doc` site and wire its navigation.

LOCAL STAND-IN for ANTfrastructure's linux/scripts/lib/dartdoc-guides.py. It is a
byte-for-byte copy of that file except for this docstring and one function,
inject_sidebar_nav; keeping the divergence that small is the point, because
retiring this file is `git diff` against upstream, deleting it, and calling
dartdoc_build_render_guides instead. Do not "improve" anything else here.

WHY IT EXISTS: upstream's inject_sidebar_nav treats "no bare `<ol>` after
`<div id="dartdoc-sidebar-left"`" as a fatal change in dart doc's page shell. It
is not. dartdoc 9.0.4 emits two page shapes, and on this repo's tree 1030 of
1459 pages are the second kind: their left sidebar is
`<div id="dartdoc-sidebar-left-content"></div>`, filled at runtime from one of
232 `*-sidebar.html` fragments, so there is nothing static to hang a nav on.
Upstream aborts on the first of them; the guide navigation never lands anywhere
and the docs lane cannot finish.

WHAT PROTECTS THE GATE INSTEAD: main()'s end-of-run vacuity check, unchanged
from upstream - a run in which NOT ONE page ended up navigated still fails. That
is what separates this from the silent no-op the predecessor of this file had.
Every other landmark check stays HARD, also unchanged: they all read index.html,
the single page shell every guide is built from, where a miss means a
successful-looking build with unrendered guide pages.
"""

from __future__ import annotations

import html
import os
import pathlib
import re
import sys

from markdown_it import MarkdownIt

RENDERER = MarkdownIt(
    "commonmark", {"html": False, "linkify": True, "typographer": True}
).enable("table")

MAIN_START = '<div id="dartdoc-main-content" class="main-content">'
MAIN_END = "  </div> <!-- /.main-content -->"
RIGHT_START = '<div id="dartdoc-sidebar-right" class="sidebar sidebar-offcanvas-right">'
RIGHT_END = "  </div>\n</main>"
LEFT_START = '<div id="dartdoc-sidebar-left"'
NAV_MARKER = "kg-md-nav-section"
FOOTER_MARKER = "kg-doc-footer-links"


def load_config(path):
    """Parse the tab-separated config: title_suffix, footer_title, guide, footer."""
    config = {"title_suffix": "", "footer_title": "", "guides": [], "footer": []}
    text = pathlib.Path(path).read_text(encoding="utf-8")
    for lineno, raw in enumerate(text.splitlines(), 1):
        if not raw.strip():
            continue
        fields = raw.split("\t")
        key = fields[0]
        if key in ("title_suffix", "footer_title") and len(fields) == 2:
            config[key] = fields[1]
        elif key in ("guide", "footer") and len(fields) == 3:
            config["guides" if key == "guide" else "footer"].append((fields[1], fields[2]))
        else:
            raise SystemExit(f"{path}:{lineno}: unrecognised config row: {raw!r}")
    return config


def slugify(value: str) -> str:
    cleaned = re.sub(r"[^a-zA-Z0-9\s-]", "", value).strip().lower()
    return re.sub(r"[\s-]+", "-", cleaned) or "section"


def rewrite_md_links(rendered_html: str, guide_map: dict) -> str:
    """Point every relative `*.md` link at the guide page rendered from that file."""

    def repl(match):
        prefix, href, suffix = match.group(1), match.group(2), match.group(3)
        if href.startswith(("http://", "https://", "#", "mailto:")):
            return match.group(0)
        path = pathlib.Path(href)
        if path.suffix.lower() != ".md":
            return match.group(0)
        return f"{prefix}{guide_map.get(path.name, f'guide-{path.stem}.html')}{suffix}"

    return re.sub(r'(href\s*=\s*["\'])([^"\']+)(["\'])', repl, rendered_html)


def extract_headings(markdown_text: str):
    headings = []
    tokens = RENDERER.parse(markdown_text)
    for i, token in enumerate(tokens):
        if token.type != "heading_open":
            continue
        inline = tokens[i + 1] if i + 1 < len(tokens) else None
        title = (inline.content if inline and inline.type == "inline" else "").strip()
        if title:
            headings.append((int(token.tag[1]), title, slugify(title)))
    return headings


def add_heading_ids(rendered_html: str, headings) -> str:
    """Give each heading the anchor the table of contents links to."""
    cursor = 0
    for level, _title, anchor in headings:
        tag = f"<h{level}>"
        idx = rendered_html.find(tag, cursor)
        if idx == -1:
            continue
        replacement = f'<h{level} id="{anchor}">'
        rendered_html = rendered_html[:idx] + replacement + rendered_html[idx + len(tag) :]
        cursor = idx + len(replacement)
    return rendered_html


def build_toc(headings) -> str:
    if not headings:
        return ""
    items = [
        f'<li class="{"section-subitem" if level > 2 else "section-title"}">'
        f'<a href="#{anchor}">{html.escape(title)}</a></li>'
        for level, title, anchor in headings
    ]
    return "\n".join(
        ['<h5 class="hidden-xs">Guide Contents</h5>', '<ol class="kg-guide-toc">', *items, "</ol>"]
    )


def _splice(page: str, start: str, end: str, replacement: str, where: str) -> str:
    """Replace the region between two literal landmarks.

    A landmark this cannot find is a HARD failure. `dart doc`'s HTML is not a
    stable contract, so the day the shell changes these strings stop matching --
    and returning the page untouched made that day look like a successful build
    with every guide page silently unrendered.
    """
    start_idx = page.find(start)
    end_idx = page.find(end, start_idx) if start_idx != -1 else -1
    if start_idx == -1 or end_idx <= start_idx:
        missing = start if start_idx == -1 else end
        raise SystemExit(
            f"{where}: dart doc's page shell no longer contains {missing!r}. "
            "The renderer's landmarks must be updated to match the generator; "
            "it will not report a rendered page it did not render."
        )
    return page[:start_idx] + replacement + page[end_idx:]


def render_guide_page(shell, nav_title: str, suffix: str, md_text: str, guide_map, slug) -> str:
    headings = extract_headings(md_text)
    body = add_heading_ids(rewrite_md_links(RENDERER.render(md_text), guide_map), headings)
    title = f"{nav_title} - {suffix}" if suffix else nav_title
    page, n = re.subn(
        r"<title>.*?</title>", f"<title>{html.escape(title)}</title>", shell, count=1, flags=re.S
    )
    if n != 1:
        raise SystemExit(f"guide-{slug}.html: no <title> in the index.html page shell.")
    main = f'{MAIN_START}\n<section class="desc markdown kg-guide-content">\n{body}\n</section>\n'
    page = _splice(page, MAIN_START, MAIN_END, main, f"guide-{slug}.html (main content)")
    return _splice(page, RIGHT_START, RIGHT_END, f"{RIGHT_START}\n{build_toc(headings)}\n",
                   f"guide-{slug}.html (right sidebar)")


def sidebar_nav(root: pathlib.Path, page_path: pathlib.Path, guides) -> str:
    """The 'Markdown Guides' block, with every href relative to the page holding it."""
    items = []
    for slug, label in guides:
        target = root / f"guide-{slug}.html"
        if not target.exists():
            continue
        href = os.path.relpath(target, page_path.parent).replace(os.sep, "/")
        items.append(
            f'      <li class="section-subitem kg-md-nav-item"><a href="{href}">{label}</a></li>'
        )
    if not items:
        return ""
    return "\n".join([f'      <li class="section-title {NAV_MARKER}">Markdown Guides</li>', *items])


def inject_sidebar_nav(text: str, nav_html: str, _where) -> str:
    """Hang the guide navigation off the left sidebar's first `<ol>`.

    THE ONE DIVERGENCE FROM UPSTREAM - see this module's docstring. Already
    injected pages and an empty nav are no-ops, as upstream. So is a page whose
    sidebar is the JS-filled `dartdoc-sidebar-left-content` div: there is no
    static list in it to inject into, and 1030 of this site's 1459 pages are
    that shape. main()'s vacuity check is what keeps the skip honest.
    """
    if NAV_MARKER in text or not nav_html:
        return text
    sidebar = text.find(LEFT_START)
    ol_start = text.find("<ol>", sidebar) if sidebar != -1 else -1
    if ol_start == -1:
        return text
    at = text.find("\n", ol_start)
    at = ol_start + len("<ol>") if at == -1 else at
    return text[: at + 1] + nav_html + "\n" + text[at + 1 :]


def inject_footer(text: str, footer_html: str, where) -> str:
    """Attach the project footer to a page.

    DIVERGENCE TWO FROM UPSTREAM, same root cause as inject_sidebar_nav: main()
    walks `*.html`, and 232 of this site's files are `*-sidebar.html` FRAGMENTS -
    a bare `<ol>` list dartdoc fetches into a page's left sidebar at runtime.
    A fragment has no `</footer>` and no `</body>` because it is not a document,
    and upstream aborts on the first one. Detected by content, not by name: a
    file carrying `<html` is a document and a missing attach point in it is
    still FATAL. main() additionally refuses a run that footered nothing.
    """
    if FOOTER_MARKER in text or not footer_html:
        return text
    if "</footer>" in text:
        return text.replace("</footer>", f"{footer_html}\n</footer>")
    if "</body>" in text:
        return text.replace("</body>", f"<footer>\n{footer_html}\n</footer>\n</body>")
    if "<html" in text.lower():
        raise SystemExit(f"{where}: neither '</footer>' nor '</body>' to attach the footer to.")
    return text


def build_footer(title: str, links) -> str:
    if not title and not links:
        return ""
    anchors = [f'    <a href="{html.escape(url)}">{html.escape(label)}</a>' for label, url in links]
    return "\n".join(
        [
            f'  <div class="{FOOTER_MARKER}">',
            f"    <strong>{html.escape(title)}</strong>",
            *anchors,
            "  </div>",
        ]
    )


def main(argv) -> int:
    if len(argv) != 3:
        raise SystemExit(f"usage: {argv[0]} <doc/api dir> <config file>")
    root = pathlib.Path(argv[1])
    config = load_config(argv[2])
    guides = config["guides"]
    guide_map = {f"{slug}.md": f"guide-{slug}.html" for slug, _label in guides}
    shell = (root / "index.html").read_text(encoding="utf-8", errors="ignore")

    for slug, label in guides:
        source = root / "md" / f"{slug}.md"
        if not source.exists():
            raise SystemExit(f"Staged guide is missing: {source}")
        md_text = source.read_text(encoding="utf-8", errors="ignore")
        page = render_guide_page(shell, label, config["title_suffix"], md_text, guide_map, slug)
        (root / f"guide-{slug}.html").write_text(page, encoding="utf-8")

    footer_html = build_footer(config["footer_title"], config["footer"])
    navigated = 0
    footered = 0
    pages = 0
    for page_path in sorted(root.rglob("*.html")):
        pages += 1
        rel = page_path.relative_to(root)
        text = page_path.read_text(encoding="utf-8", errors="ignore")
        nav_html = sidebar_nav(root, page_path, guides)
        after = inject_sidebar_nav(text, nav_html, rel)
        # Carrying the marker, not "was edited this run": a second pass over an
        # already-navigated tree is a no-op, not a failure.
        navigated += NAV_MARKER in after
        final = inject_footer(after, footer_html, rel)
        footered += FOOTER_MARKER in final
        page_path.write_text(final, encoding="utf-8")
    # Counted, not assumed: "Rendered N" over an untouched tree is exactly the
    # failure this file's landmark checks exist to make impossible.
    if guides and not navigated:
        raise SystemExit(
            f"{len(guides)} guide page(s) rendered but not one of the {pages} page(s) "
            f"under {root} carries the guide navigation; the site would not link them."
        )
    # The counterpart guard for divergence two: the fragment skip in
    # inject_footer must never become "no page got a footer".
    if footer_html and not footered:
        raise SystemExit(
            f"a footer was configured but not one of the {pages} page(s) under {root} "
            "carries it; every file was treated as a fragment."
        )
    print(
        f"Rendered {len(guides)} guide page(s), navigated {navigated}/{pages} and "
        f"footered {footered}/{pages} under {root}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
