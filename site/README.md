# structured_log project website

*Читать на [русском](README.ru.md).*

The project's documentation website — built with [Astro](https://astro.build)
and [Starlight](https://starlight.astro.build), bilingual (English/Russian).

This is a standalone npm project, outside the Dart/Flutter Melos workspace:
it is not listed in [`melos.yaml`](../melos.yaml) and has no Dart
dependencies of its own.

## Content

Most of the site's content is generated from [`docs/`](../docs/) and each
[`emb/`](../emb/) package's `README.md` at the repository root — it is
**not** hand-authored here. To change a page's content, edit the
corresponding file under `docs/` or `emb/<package>/README(.ru).md` and
re-run the migration script:

```bash
python3 scripts/migrate_docs.py   # from this directory
```

The script:

- Converts every `docs/**/*.md` (English) and `docs/**/*.ru.md` (Russian)
  file into a Starlight content page under `src/content/docs/` (English at
  the root, Russian under `src/content/docs/ru/`).
- Converts every `emb/<package>/README.md` / `README.ru.md` into a page
  under `src/content/docs/packages/<package>.md` (and `ru/packages/...`)
  — one page per embeddable library, its README verbatim.
- For both sources: adds Starlight frontmatter and drops the manual
  `# Title` / language-switch header (Starlight's own UI provides the
  language switcher), and rewrites internal links into Starlight routes.
- Rewrites links that point outside the mirrored source (to `openspec/`,
  other package sources, `AGENTS.md`, an example app, ...) into
  `github.com/pese-git/structured_log` links.
- Copies the User Guide's screenshots from `docs/guides/assets/user-guide/`
  into `public/images/user-guide/`.

The landing page (`src/content/docs/index.mdx` / `ru/index.mdx`), the
packages index (`src/content/docs/packages/index.md` / `ru/packages/index.md`),
and the sidebar/locale configuration (`astro.config.mjs`) are hand-authored
and untouched by the script — see `PROTECTED` in
`scripts/migrate_docs.py`, which `site/.gitignore`'s exceptions for
`src/content/docs/` must be kept in sync with.

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
