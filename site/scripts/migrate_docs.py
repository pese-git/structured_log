#!/usr/bin/env python3
"""Migrate the repository's docs/ into site/src/content/docs (Astro Starlight).

Run from anywhere; paths are resolved relative to this script's location
(site/scripts/migrate_docs.py), so `site/` and `docs/` are found as
`<repo_root>/site` and `<repo_root>/docs` regardless of the working
directory this is invoked from.

Re-run this whenever docs/**/*.md changes — it fully regenerates
site/src/content/docs/ and site/public/images/user-guide/ from scratch, so
it is always safe to re-run and never accumulates stale output.
"""
import os
import re
import shutil

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
SITE_DIR = os.path.dirname(SCRIPT_DIR)
REPO_ROOT = os.path.dirname(SITE_DIR)
DOCS_DIR = os.path.join(REPO_ROOT, "docs")
SITE_CONTENT = os.path.join(SITE_DIR, "src", "content", "docs")
SITE_PUBLIC_IMAGES = os.path.join(SITE_DIR, "public", "images", "user-guide")
GITHUB_BASE = "https://github.com/pese-git/structured_log/blob/master"
GITHUB_TREE_BASE = "https://github.com/pese-git/structured_log/tree/master"

# 1. Collect all markdown files under docs/
md_files = []
for root, _dirs, files in os.walk(DOCS_DIR):
    for fn in files:
        if fn.endswith(".md"):
            full = os.path.join(root, fn)
            rel = os.path.relpath(full, DOCS_DIR)  # e.g. "api/errors.md" or "README.md"
            md_files.append(rel)

md_set = set(md_files)


def slug_for(rel):
    """Compute the Starlight slug (no locale prefix, no leading/trailing slash)
    for a docs/-relative markdown path."""
    is_ru = rel.endswith(".ru.md")
    core = rel[: -len(".ru.md")] if is_ru else rel[: -len(".md")]
    parts = core.split(os.sep)
    base = parts[-1]
    dirparts = parts[:-1]
    if base == "README":
        if not dirparts:
            # docs/README.md -> top-level "overview" page
            slug_parts = ["overview"]
        else:
            # docs/<folder>/README.md -> folder index page
            slug_parts = dirparts + ["index"]
    else:
        slug_parts = dirparts + [base]
    return "/".join(slug_parts), is_ru


def url_for(rel):
    slug, is_ru = slug_for(rel)
    if slug.endswith("/index"):
        slug = slug[: -len("/index")]
    prefix = "/ru/" if is_ru else "/"
    if slug:
        return f"{prefix}{slug}/"
    return prefix


def target_path(rel):
    slug, is_ru = slug_for(rel)
    locale_dir = "ru" if is_ru else ""
    target = (
        os.path.join(SITE_CONTENT, locale_dir, slug + ".md")
        if locale_dir
        else os.path.join(SITE_CONTENT, slug + ".md")
    )
    return target


LINK_RE = re.compile(r"(!?)\[([^\]]*)\]\(([^)\s]+)(?:\s+\"[^\"]*\")?\)")


def resolve_link(src_rel_dir, href):
    """href as written in a markdown file located at docs/<src_rel_dir>/....
    Returns a rewritten href string."""
    if href.startswith(("http://", "https://", "mailto:", "#")):
        return href
    if "#" in href:
        path_part, anchor = href.split("#", 1)
        anchor = "#" + anchor
    else:
        path_part, anchor = href, ""

    if path_part == "":
        return href

    # Image asset reference (relative, inside docs/guides/assets/...)
    norm = os.path.normpath(os.path.join(src_rel_dir, path_part))
    norm = norm.replace(os.sep, "/")

    if norm.startswith("guides/assets/user-guide/"):
        fname = norm.split("/")[-1]
        return f"/images/user-guide/{fname}"

    if norm in md_set:
        return url_for(norm) + anchor

    # Not a known docs markdown file -> link out to GitHub.
    repo_rel = os.path.normpath(os.path.join("docs", src_rel_dir, path_part)).replace(os.sep, "/")
    is_dir_link = path_part.endswith("/") or "." not in os.path.basename(path_part.rstrip("/"))
    base_url = GITHUB_TREE_BASE if is_dir_link else GITHUB_BASE
    return f"{base_url}/{repo_rel}{anchor}"


def rewrite_links(text, src_rel_dir):
    def _sub(m):
        bang, label, href = m.group(1), m.group(2), m.group(3)
        new_href = resolve_link(src_rel_dir, href)
        return f"{bang}[{label}]({new_href})"

    return LINK_RE.sub(_sub, text)


def convert(rel):
    src_path = os.path.join(DOCS_DIR, rel)
    with open(src_path, "r", encoding="utf-8") as f:
        lines = f.read().split("\n")

    # Uniform header convention across docs/: line0 "# Title", line1 "",
    # line2 the language-switch line ("*Read in [English](...)*" /
    # "*Читать на [русском](...)*"), line3 "". Starlight renders the title
    # from frontmatter and provides its own language switcher, so both are
    # dropped rather than translated.
    assert lines[0].startswith("# "), f"{rel}: unexpected first line: {lines[0]!r}"
    title = lines[0][2:].strip()
    body_lines = lines[4:] if (len(lines) > 3 and lines[3] == "") else lines[1:]
    body = "\n".join(body_lines)

    src_rel_dir = os.path.dirname(rel)
    body = rewrite_links(body, src_rel_dir)

    safe_title = title.replace('"', '\\"')
    frontmatter = f'---\ntitle: "{safe_title}"\n---\n'

    out = frontmatter + "\n" + body.lstrip("\n") + ("\n" if not body.endswith("\n") else "")

    tgt = target_path(rel)
    os.makedirs(os.path.dirname(tgt), exist_ok=True)
    with open(tgt, "w", encoding="utf-8") as f:
        f.write(out)
    return tgt


def main():
    if os.path.isdir(SITE_CONTENT):
        for entry in os.listdir(SITE_CONTENT):
            full = os.path.join(SITE_CONTENT, entry)
            # index.mdx / ru/index.mdx are the hand-authored landing pages —
            # not generated from docs/, so never touched by this script.
            if entry in ("index.mdx",):
                continue
            if os.path.isdir(full):
                if entry == "ru":
                    for sub in os.listdir(full):
                        if sub == "index.mdx":
                            continue
                        subfull = os.path.join(full, sub)
                        shutil.rmtree(subfull) if os.path.isdir(subfull) else os.remove(subfull)
                else:
                    shutil.rmtree(full)
            else:
                os.remove(full)
    os.makedirs(SITE_CONTENT, exist_ok=True)

    for rel in sorted(md_files):
        tgt = convert(rel)
        print("wrote", os.path.relpath(tgt, SITE_CONTENT))

    src_assets = os.path.join(DOCS_DIR, "guides", "assets", "user-guide")
    if os.path.isdir(src_assets):
        os.makedirs(SITE_PUBLIC_IMAGES, exist_ok=True)
        for fn in os.listdir(src_assets):
            shutil.copy2(os.path.join(src_assets, fn), os.path.join(SITE_PUBLIC_IMAGES, fn))
        print(f"copied {len(os.listdir(src_assets))} images to public/images/user-guide/")


if __name__ == "__main__":
    main()
