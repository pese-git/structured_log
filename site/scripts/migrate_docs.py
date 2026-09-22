#!/usr/bin/env python3
"""Migrate the repository's docs/ and each emb/ package's README into
site/src/content/docs (Astro Starlight).

Run from anywhere; paths are resolved relative to this script's location
(site/scripts/migrate_docs.py), so `site/`, `docs/`, and `emb/` are found
relative to `<repo_root>` regardless of the working directory this is
invoked from.

Re-run this whenever docs/**/*.md or an emb/*/README(.ru).md changes — it
fully regenerates site/src/content/docs/ (except the hand-authored landing
pages and packages index, see `PROTECTED`) and
site/public/images/user-guide/ from scratch, so it is always safe to
re-run and never accumulates stale output.
"""
import os
import re
import shutil

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
SITE_DIR = os.path.dirname(SCRIPT_DIR)
REPO_ROOT = os.path.dirname(SITE_DIR)
DOCS_DIR = os.path.join(REPO_ROOT, "docs")
EMB_DIR = os.path.join(REPO_ROOT, "emb")
SITE_CONTENT = os.path.join(SITE_DIR, "src", "content", "docs")
SITE_PUBLIC_IMAGES = os.path.join(SITE_DIR, "public", "images", "user-guide")
GITHUB_BASE = "https://github.com/pese-git/structured_log/blob/master"
GITHUB_TREE_BASE = "https://github.com/pese-git/structured_log/tree/master"

# Hand-authored files this script must never touch, as paths relative to
# each locale root (SITE_CONTENT for English, SITE_CONTENT/ru for Russian).
PROTECTED = {"index.mdx", "packages/index.md"}

# --- docs/ ---------------------------------------------------------------

docs_md_files = []
for root, _dirs, files in os.walk(DOCS_DIR):
    for fn in files:
        if fn.endswith(".md"):
            full = os.path.join(root, fn)
            rel = os.path.relpath(full, DOCS_DIR)  # e.g. "api/errors.md" or "README.md"
            docs_md_files.append(rel)

docs_md_set = set(docs_md_files)


def docs_slug_for(rel):
    """Compute the Starlight slug (no locale prefix, no leading/trailing
    slash) for a docs/-relative markdown path."""
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


# --- emb/ (one page per package, from its README) -------------------------

emb_pkg_names = sorted(
    name
    for name in os.listdir(EMB_DIR)
    if os.path.isdir(os.path.join(EMB_DIR, name))
    and os.path.isfile(os.path.join(EMB_DIR, name, "README.md"))
)

emb_readme_files = []  # "<pkg>/README.md" / "<pkg>/README.ru.md"
for pkg in emb_pkg_names:
    for fn in ("README.md", "README.ru.md"):
        if os.path.isfile(os.path.join(EMB_DIR, pkg, fn)):
            emb_readme_files.append(f"{pkg}/{fn}")


def emb_slug_for(rel):
    """Compute the Starlight slug for an emb/-relative README path, e.g.
    "structured_log_http/README.ru.md" -> ("packages/structured_log_http", True)."""
    is_ru = rel.endswith(".ru.md")
    pkg = rel.split("/", 1)[0]
    return f"packages/{pkg}", is_ru


# --- shared slug -> URL / filesystem path helpers -------------------------


def url_for(slug, is_ru):
    if slug.endswith("/index"):
        slug = slug[: -len("/index")]
    prefix = "/ru/" if is_ru else "/"
    return f"{prefix}{slug}/" if slug else prefix


def target_path(slug, is_ru):
    locale_dir = "ru" if is_ru else ""
    return (
        os.path.join(SITE_CONTENT, locale_dir, slug + ".md")
        if locale_dir
        else os.path.join(SITE_CONTENT, slug + ".md")
    )


LINK_RE = re.compile(r"(!?)\[([^\]]*)\]\(([^)\s]+)(?:\s+\"[^\"]*\")?\)")


def split_anchor(href):
    if "#" in href:
        path_part, anchor = href.split("#", 1)
        return path_part, "#" + anchor
    return href, ""


def github_fallback(repo_rel_path, path_part, anchor):
    repo_rel_path = repo_rel_path.replace(os.sep, "/")
    is_dir_link = path_part.endswith("/") or "." not in os.path.basename(path_part.rstrip("/"))
    base_url = GITHUB_TREE_BASE if is_dir_link else GITHUB_BASE
    return f"{base_url}/{repo_rel_path}{anchor}"


def resolve_docs_link(src_rel_dir, href):
    """href as written in a markdown file located at docs/<src_rel_dir>/...."""
    if href.startswith(("http://", "https://", "mailto:", "#")):
        return href
    path_part, anchor = split_anchor(href)
    if path_part == "":
        return href

    norm = os.path.normpath(os.path.join(src_rel_dir, path_part)).replace(os.sep, "/")

    # Image asset reference (relative, inside docs/guides/assets/...)
    if norm.startswith("guides/assets/user-guide/"):
        fname = norm.split("/")[-1]
        return f"/images/user-guide/{fname}"

    if norm in docs_md_set:
        slug, is_ru = docs_slug_for(norm)
        return url_for(slug, is_ru) + anchor

    # Not a known docs markdown file -> link out to GitHub.
    repo_rel = os.path.normpath(os.path.join("docs", src_rel_dir, path_part))
    return github_fallback(repo_rel, path_part, anchor)


def resolve_emb_link(src_pkg, src_is_ru, href):
    """href as written in emb/<src_pkg>/README(.ru).md."""
    if href.startswith(("http://", "https://", "mailto:", "#")):
        return href
    path_part, anchor = split_anchor(href)
    if path_part == "":
        return href

    norm = os.path.normpath(os.path.join(src_pkg, path_part)).replace(os.sep, "/")
    parts = norm.split("/")
    target_pkg, rest = parts[0], parts[1:]

    # Screenshot, inside the same package's own doc/screenshots/.
    if target_pkg == src_pkg and rest[:2] == ["doc", "screenshots"] and len(rest) == 3:
        return f"/images/packages/{src_pkg}/{rest[2]}"

    if target_pkg in emb_pkg_names:
        if not rest:
            # Bare package reference (e.g. "../structured_log") -> that
            # package's page, in the linking document's own language.
            slug, _ = emb_slug_for(f"{target_pkg}/README.md")
            return url_for(slug, src_is_ru) + anchor
        if rest == ["README.md"]:
            slug, _ = emb_slug_for(f"{target_pkg}/README.md")
            return url_for(slug, False) + anchor
        if rest == ["README.ru.md"]:
            slug, _ = emb_slug_for(f"{target_pkg}/README.md")
            return url_for(slug, True) + anchor

    # Anything else (example/, pubspec.yaml, doc/ARCHITECTURE.md, LICENSE,
    # or reaching outside emb/ entirely) -> link out to GitHub.
    repo_rel = os.path.normpath(os.path.join("emb", src_pkg, path_part))
    return github_fallback(repo_rel, path_part, anchor)


def rewrite_links(text, resolver):
    def _sub(m):
        bang, label, href = m.group(1), m.group(2), m.group(3)
        return f"{bang}[{label}]({resolver(href)})"

    return LINK_RE.sub(_sub, text)


# --- header stripping (shared) --------------------------------------------

# Every docs/ and emb/ README follows the same convention: an H1 title,
# then (only in emb/'s structured_log and structured_log_http) an optional
# CI badge, then the language-switch line ("*Read in [English](...)*" /
# "*Читать на [русском](...)*", sometimes "*Read this in [English](...)*").
# Starlight renders the title from frontmatter and provides its own
# language switcher, so all of this is dropped rather than translated.
BADGE_RE = re.compile(r"^\[!\[.*?\]\(.*?\)\]\(.*?\)\s*$")
LANGSWITCH_RE = re.compile(r"^\*(Read( this)? in \[English\]|Читать на \[русском\])\([^)]*\)\.\*\s*$")


def strip_header(lines, rel):
    assert lines[0].startswith("# "), f"{rel}: unexpected first line: {lines[0]!r}"
    title = lines[0][2:].strip()
    idx = 1
    while idx < len(lines) and (
        lines[idx].strip() == "" or BADGE_RE.match(lines[idx]) or LANGSWITCH_RE.match(lines[idx])
    ):
        idx += 1
    body = "\n".join(lines[idx:])
    return title, body


def write_page(slug, is_ru, title, body):
    safe_title = title.replace('"', '\\"')
    frontmatter = f'---\ntitle: "{safe_title}"\n---\n'
    out = frontmatter + "\n" + body.lstrip("\n") + ("\n" if not body.endswith("\n") else "")
    tgt = target_path(slug, is_ru)
    os.makedirs(os.path.dirname(tgt), exist_ok=True)
    with open(tgt, "w", encoding="utf-8") as f:
        f.write(out)
    return tgt


def convert_docs(rel):
    with open(os.path.join(DOCS_DIR, rel), "r", encoding="utf-8") as f:
        lines = f.read().split("\n")
    title, body = strip_header(lines, rel)
    body = rewrite_links(body, lambda href: resolve_docs_link(os.path.dirname(rel), href))
    slug, is_ru = docs_slug_for(rel)
    return write_page(slug, is_ru, title, body)


def convert_emb(rel):
    with open(os.path.join(EMB_DIR, rel), "r", encoding="utf-8") as f:
        lines = f.read().split("\n")
    title, body = strip_header(lines, rel)
    pkg, is_ru = rel.split("/", 1)[0], rel.endswith(".ru.md")
    body = rewrite_links(body, lambda href: resolve_emb_link(pkg, is_ru, href))
    slug, _ = emb_slug_for(rel)
    return write_page(slug, is_ru, title, body)


# --- cleanup, preserving hand-authored files -------------------------------


def clean_locale_root(root_dir, protected):
    """Remove everything under root_dir except the paths in `protected`
    (relative to root_dir) and any directory that contains one of them."""
    protected_dirs = set()
    for p in protected:
        parts = p.split("/")
        for i in range(1, len(parts)):
            protected_dirs.add("/".join(parts[:i]))

    def _clean(dir_path, rel_prefix):
        for entry in os.listdir(dir_path):
            full = os.path.join(dir_path, entry)
            rel = f"{rel_prefix}/{entry}" if rel_prefix else entry
            if rel in protected:
                continue
            if os.path.isdir(full):
                if rel in protected_dirs:
                    _clean(full, rel)
                else:
                    shutil.rmtree(full)
            else:
                os.remove(full)

    _clean(root_dir, "")


def main():
    if os.path.isdir(SITE_CONTENT):
        # "ru" holds a whole separate locale tree, cleaned by its own call
        # right below — the top-level pass must leave it alone entirely
        # (not descend into it as an ordinary "protected dir", and
        # certainly not rmtree it as an unprotected one).
        clean_locale_root(SITE_CONTENT, PROTECTED | {"ru"})
        ru_root = os.path.join(SITE_CONTENT, "ru")
        if os.path.isdir(ru_root):
            clean_locale_root(ru_root, PROTECTED)
    os.makedirs(SITE_CONTENT, exist_ok=True)

    for rel in sorted(docs_md_files):
        tgt = convert_docs(rel)
        print("wrote", os.path.relpath(tgt, SITE_CONTENT))

    for rel in sorted(emb_readme_files):
        tgt = convert_emb(rel)
        print("wrote", os.path.relpath(tgt, SITE_CONTENT))

    src_assets = os.path.join(DOCS_DIR, "guides", "assets", "user-guide")
    if os.path.isdir(src_assets):
        os.makedirs(SITE_PUBLIC_IMAGES, exist_ok=True)
        for fn in os.listdir(src_assets):
            shutil.copy2(os.path.join(src_assets, fn), os.path.join(SITE_PUBLIC_IMAGES, fn))
        print(f"copied {len(os.listdir(src_assets))} images to public/images/user-guide/")

    for pkg in emb_pkg_names:
        src_shots = os.path.join(EMB_DIR, pkg, "doc", "screenshots")
        if os.path.isdir(src_shots):
            dst = os.path.join(SITE_DIR, "public", "images", "packages", pkg)
            os.makedirs(dst, exist_ok=True)
            for fn in os.listdir(src_shots):
                shutil.copy2(os.path.join(src_shots, fn), os.path.join(dst, fn))
            print(f"copied {len(os.listdir(src_shots))} images to public/images/packages/{pkg}/")


if __name__ == "__main__":
    main()
