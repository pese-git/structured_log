# structured_log project website

*Читать на [русском](README.ru.md).*

The project's documentation website — built with [Astro](https://astro.build)
and [Starlight](https://starlight.astro.build), bilingual (English/Russian).

This is a standalone npm project, outside the Dart/Flutter Melos workspace:
it is not listed in [`melos.yaml`](../melos.yaml) and has no Dart
dependencies of its own.

## Content

The site's content is generated from [`docs/`](../docs/) at the repository
root — it is **not** hand-authored here. To change a page's content, edit
the corresponding file under `docs/` and re-run the migration script:

```bash
python3 scripts/migrate_docs.py   # from this directory
```

The script:

- Converts every `docs/**/*.md` (English) and `docs/**/*.ru.md` (Russian)
  file into a Starlight content page under `src/content/docs/` (English at
  the root, Russian under `src/content/docs/ru/`), adding Starlight
  frontmatter and dropping the manual `# Title` / language-switch header
  (Starlight's own UI provides the language switcher).
- Rewrites internal links between docs into Starlight routes.
- Rewrites links that point outside `docs/` (to `openspec/`, package
  sources, `AGENTS.md`, ...) into `github.com/pese-git/structured_log`
  links, since only `docs/` is mirrored onto the site.
- Copies the User Guide's screenshots from `docs/guides/assets/user-guide/`
  into `public/images/user-guide/`.

The landing page (`src/content/docs/index.mdx` / `ru/index.mdx`) and the
sidebar/locale configuration (`astro.config.mjs`) are hand-authored and
untouched by the script.

## Commands

Run from this directory (`site/`):

| Command | Action |
| --- | --- |
| `npm install` | Install dependencies |
| `npm run dev` | Start the local dev server at `localhost:4321` |
| `npm run build` | Build the static site to `dist/` |
| `npm run preview` | Preview the built site locally |

From the repository root, `melos run` (via `.claude/launch.json`'s
`site-docs` entry) starts the same dev server.

## Diagrams

Architecture pages use ` ```mermaid ` code fences, rendered client-side by
[`astro-mermaid`](https://github.com/wei/astro-mermaid) — no build-time
dependency (Playwright/Chromium) required.
