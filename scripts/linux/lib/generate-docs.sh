#!/usr/bin/env bash
set -euo pipefail

# Generiert die Dart-Dokumentation und setzt die Besitzrechte

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/container-steps.sh"

source_bashrc_and_add_flutter_to_path

# Zielverzeichnis für Doku und Besitzrechte bestimmen
if [[ -d "/workspace" ]]; then
	DOC_ROOT="/workspace/doc"
else
	DOC_ROOT="$(pwd)/doc"
fi


flutter clean
dart doc

# --- Styling und Struktur verbessern ---
DOC_API_DIR="$DOC_ROOT/api"
DOC_CSS_FILE="$DOC_API_DIR/static-assets/styles.css"
OVERRIDE_CSS_FILE="docs/source/_static/css/dartdoc-theme-overrides.css"
PROJECT_IMAGES_DIR="images"

# 1. Eigenes CSS-Theme einbinden (falls vorhanden)
if [[ -f "$OVERRIDE_CSS_FILE" && -f "$DOC_CSS_FILE" ]]; then
	echo "[Info] Wende Theme-Overrides auf die Doku an."
	# Vorherige Overrides entfernen
	if grep -q "Sphinx press theme overrides for Dartdoc START" "$DOC_CSS_FILE"; then
		awk '/\/\* Sphinx press theme overrides for Dartdoc START \*\//{exit} {print}' "$DOC_CSS_FILE" > "${DOC_CSS_FILE}.tmp"
		mv "${DOC_CSS_FILE}.tmp" "$DOC_CSS_FILE"
	fi
	cat "$OVERRIDE_CSS_FILE" >> "$DOC_CSS_FILE"
fi

# 2. Dark Mode als Standard setzen
if [[ -d "$DOC_API_DIR" ]]; then
	echo "[Info] Setze Dark Mode als Standard in der Doku."
	find "$DOC_API_DIR" -type f -name "*.html" -print0 | while IFS= read -r -d '' html_file; do
		sed -i 's/class="light-theme"/class="dark-theme"/g' "$html_file"
	done
fi

# 3. Alle Bilder rekursiv in die Doku kopieren (inkl. Unterordner)
if [[ -d "$PROJECT_IMAGES_DIR" && -d "$DOC_API_DIR" ]]; then
	echo "[Info] Kopiere alle Bilder rekursiv in die Doku."
	mkdir -p "$DOC_API_DIR/images"
	cp -a "$PROJECT_IMAGES_DIR"/. "$DOC_API_DIR/images/"
fi

# 3b. Eigene Markdown-Guides für Sidebar-Navigation veröffentlichen
if [[ -d "$DOC_API_DIR" ]]; then
	echo "[Info] Veröffentliche eigene Markdown-Guides unter doc/api/md."
	mkdir -p "$DOC_API_DIR/md"
	rm -f "$DOC_API_DIR"/guide-*.html

	declare -a MD_GUIDE_MAP=(
		"docs/INTRODUCTION.md:introduction.md"
		"docs/source/README.md:docs-readme.md"
		"docs/source/overview.md:overview.md"
		"docs/source/getting-started.md:getting-started.md"
		"docs/source/platforms.md:platforms.md"
		"docs/source/camera-streaming.md:camera-streaming.md"
		"docs/source/readmes.md:readmes.md"
		"docs/source/project-operations.md:project-operations.md"
		"docs/source/roadmap.md:roadmap.md"
		"docs/source/upgrade-guide.md:upgrade-guide.md"
	)

	for mapping in "${MD_GUIDE_MAP[@]}"; do
		src="${mapping%%:*}"
		dst="${mapping##*:}"
		if [[ -f "$src" ]]; then
			cp "$src" "$DOC_API_DIR/md/$dst"
		fi
	done
fi

# 4. Footer mit Projekt-Navigation und README-Links ergänzen
if [[ -d "$DOC_API_DIR" ]]; then
	echo "[Info] Ergänze Custom Footer und Sidebar-MD-Navigation in der Doku."
	python3 - "$DOC_API_DIR" <<'PY'
import os
import pathlib
import re
import sys
import html
from markdown_it import MarkdownIt

root = pathlib.Path(sys.argv[1])

md_guides = [
	("introduction.md", "Introduction", "guide-introduction.html"),
	("docs-readme.md", "Docs README", "guide-docs-readme.html"),
	("overview.md", "Overview", "guide-overview.html"),
	("getting-started.md", "Getting Started", "guide-getting-started.html"),
	("platforms.md", "Platforms", "guide-platforms.html"),
	("camera-streaming.md", "Camera Streaming", "guide-camera-streaming.html"),
	("readmes.md", "Readmes", "guide-readmes.html"),
	("project-operations.md", "Project Operations", "guide-project-operations.html"),
	("roadmap.md", "Roadmap", "guide-roadmap.html"),
	("upgrade-guide.md", "Upgrade Guide", "guide-upgrade-guide.html"),
]

guide_map = {name: out for name, _, out in md_guides}
markdown_renderer = MarkdownIt("commonmark", {"html": False, "linkify": True, "typographer": True}).enable("table")


def slugify(value: str) -> str:
	cleaned = re.sub(r"[^a-zA-Z0-9\s-]", "", value).strip().lower()
	return re.sub(r"[\s-]+", "-", cleaned) or "section"


def rewrite_md_links(rendered_html: str) -> str:
	def repl(match):
		prefix = match.group(1)
		href = match.group(2)
		suffix = match.group(3)
		if href.startswith(("http://", "https://", "#", "mailto:")):
			return match.group(0)
		path = pathlib.Path(href)
		if path.suffix.lower() == ".md":
			replacement = guide_map.get(path.name, f"guide-{path.stem}.html")
			return f'{prefix}{replacement}{suffix}'
		return match.group(0)

	return re.sub(r'(href\s*=\s*["\'])([^"\']+)(["\'])', repl, rendered_html)


def extract_headings(markdown_text: str):
	headings = []
	tokens = markdown_renderer.parse(markdown_text)
	for i, token in enumerate(tokens):
		if token.type == "heading_open":
			level = int(token.tag[1])
			inline = tokens[i + 1] if i + 1 < len(tokens) else None
			title = (inline.content if inline and inline.type == "inline" else "").strip()
			if not title:
				continue
			anchor = slugify(title)
			headings.append((level, title, anchor))
	return headings


def add_heading_ids(rendered_html: str, headings):
	cursor = 0
	for level, _title, anchor in headings:
		tag = f"<h{level}>"
		idx = rendered_html.find(tag, cursor)
		if idx == -1:
			continue
		replacement = f'<h{level} id="{anchor}">'
		rendered_html = rendered_html[:idx] + replacement + rendered_html[idx + len(tag):]
		cursor = idx + len(replacement)
	return rendered_html


index_template = (root / "index.html").read_text(encoding="utf-8", errors="ignore")


def build_toc(headings):
	if not headings:
		return ""
	items = []
	for level, title, anchor in headings:
		item_class = "section-subitem" if level > 2 else "section-title"
		items.append(f'<li class="{item_class}"><a href="#{anchor}">{html.escape(title)}</a></li>')
	return "\n".join([
		'<h5 class="hidden-xs">Guide Contents</h5>',
		'<ol class="kg-guide-toc">',
		*items,
		'</ol>',
	])


for md_file, nav_title, guide_file in md_guides:
	source = root / "md" / md_file
	if not source.exists():
		continue

	md_text = source.read_text(encoding="utf-8", errors="ignore")
	headings = extract_headings(md_text)
	body_html = rewrite_md_links(markdown_renderer.render(md_text))
	body_html = add_heading_ids(body_html, headings)
	toc_html = build_toc(headings)

	page = index_template
	page = re.sub(r"<title>.*?</title>", f"<title>{html.escape(nav_title)} - Kataglyphis Docs</title>", page, count=1, flags=re.S)

	main_start = '<div id="dartdoc-main-content" class="main-content">'
	main_end = '  </div> <!-- /.main-content -->'
	main_start_idx = page.find(main_start)
	main_end_idx = page.find(main_end)
	if main_start_idx != -1 and main_end_idx != -1 and main_end_idx > main_start_idx:
		replacement = (
			main_start
			+ '\n<section class="desc markdown kg-guide-content">\n'
			+ body_html
			+ '\n</section>\n'
		)
		page = page[:main_start_idx] + replacement + page[main_end_idx:]

	right_start = '<div id="dartdoc-sidebar-right" class="sidebar sidebar-offcanvas-right">'
	right_end = '  </div>\n</main>'
	right_start_idx = page.find(right_start)
	right_end_idx = page.find(right_end, right_start_idx)
	if right_start_idx != -1 and right_end_idx != -1 and right_end_idx > right_start_idx:
		right_replacement = right_start + '\n' + toc_html + '\n'
		page = page[:right_start_idx] + right_replacement + page[right_end_idx:]

	(root / guide_file).write_text(page, encoding="utf-8")

footer_html = """
  <div class=\"kg-doc-footer-links\">
	<strong>Kataglyphis Docs</strong>
	<a href=\"https://github.com/Kataglyphis/Kataglyphis-Inference-Engine\">Repository</a>
	<a href=\"https://github.com/Kataglyphis/Kataglyphis-Inference-Engine/blob/develop/README.md\">README</a>
	<a href=\"https://github.com/Kataglyphis/Kataglyphis-Inference-Engine/tree/develop/docs/source\">Guides</a>
  </div>
""".strip("\n")

for html_file in root.rglob("*.html"):
	text = html_file.read_text(encoding="utf-8", errors="ignore")

	if "kg-md-nav-section" not in text:
		sidebar_start = text.find('<div id="dartdoc-sidebar-left"')
		if sidebar_start != -1:
			ol_start = text.find("<ol>", sidebar_start)
			ol_end = text.find("</ol>", ol_start)
			if ol_start != -1 and ol_end != -1:
				items = []
				for file_name, label, guide_file in md_guides:
					target = root / guide_file
					if not target.exists():
						continue
					rel_href = os.path.relpath(target, html_file.parent).replace(os.sep, "/")
					items.append(f'      <li class="section-subitem kg-md-nav-item"><a href="{rel_href}">{label}</a></li>')
				if items:
					nav_html = "\n".join([
						'      <li class="section-title kg-md-nav-section">Markdown Guides</li>',
						*items,
					])
					insert_at = text.find("\n", ol_start)
					if insert_at == -1:
						insert_at = ol_start + len("<ol>")
					text = text[:insert_at + 1] + nav_html + "\n" + text[insert_at + 1:]

	if "kg-doc-footer-links" in text:
		pass
	elif "</footer>" in text:
		text = text.replace("</footer>", f"{footer_html}\n</footer>")
	elif "</body>" in text:
		text = text.replace("</body>", f"<footer>\n{footer_html}\n</footer>\n</body>")
	else:
		pass

	html_file.write_text(text, encoding="utf-8")
PY
fi

# Besitzrechte nur im CI setzen
if [[ "${CI:-}" == "true" ]]; then
	if command -v stat >/dev/null 2>&1 && command -v chown >/dev/null 2>&1 && [[ -d "$DOC_ROOT" ]]; then
		owner_uid=$(stat -c "%u" "$(pwd)")
		owner_gid=$(stat -c "%g" "$(pwd)")
		echo "[CI] Fixing ownership of $DOC_ROOT to ${owner_uid}:${owner_gid}"
		chown -R "${owner_uid}:${owner_gid}" "$DOC_ROOT" || true
	fi
else
	echo "[Info] Überspringe chown/stat (kein CI-Workflow)."
fi
