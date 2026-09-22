# Сайт проекта structured_log

*Read in [English](README.md).*

Сайт документации проекта — построен на [Astro](https://astro.build) и
[Starlight](https://starlight.astro.build), билингвальный
(английский/русский).

Это самостоятельный npm-проект вне Dart/Flutter Melos workspace: он не
перечислен в [`melos.yaml`](../melos.yaml) и не имеет собственных
Dart-зависимостей.

## Контент

Бо́льшая часть содержимого сайта генерируется из [`docs/`](../docs/) и
`README.md` каждого пакета в [`emb/`](../emb/) в корне репозитория — оно
**не** пишется вручную здесь. Чтобы изменить содержимое страницы,
отредактируйте соответствующий файл в `docs/` или
`emb/<пакет>/README(.ru).md` и заново прогоните скрипт миграции:

```bash
python3 scripts/migrate_docs.py   # из этой директории
```

Скрипт:

- Конвертирует каждый `docs/**/*.md` (английский) и `docs/**/*.ru.md`
  (русский) файл в страницу Starlight под `src/content/docs/` (английский
  — в корне, русский — под `src/content/docs/ru/`).
- Конвертирует каждый `emb/<пакет>/README.md`/`README.ru.md` в страницу
  под `src/content/docs/packages/<пакет>.md` (и `ru/packages/...`) — по
  одной странице на встраиваемую библиотеку, дословно её README.
- Для обоих источников: добавляет frontmatter Starlight, убирает ручной
  заголовок `# Title`/строку переключения языка (переключатель языка
  предоставляет сам Starlight) и переписывает внутренние ссылки в
  маршруты Starlight.
- Переписывает ссылки, ведущие за пределы переносимого источника (на
  `openspec/`, исходники других пакетов, `AGENTS.md`, example-приложение,
  ...), в ссылки на `github.com/pese-git/structured_log`.
- Копирует скриншоты руководства пользователя из
  `docs/guides/assets/user-guide/` в `public/images/user-guide/`.

Главная страница (`src/content/docs/index.mdx` / `ru/index.mdx`),
оглавление пакетов (`src/content/docs/packages/index.md` /
`ru/packages/index.md`) и конфигурация сайдбара/локалей
(`astro.config.mjs`) написаны вручную и скриптом не затрагиваются — см.
`PROTECTED` в `scripts/migrate_docs.py`, с которым нужно синхронизировать
исключения `site/.gitignore` для `src/content/docs/`.

## Команды

Запускаются из этой директории (`site/`):

| Команда | Действие |
| --- | --- |
| `npm install` | Установить зависимости |
| `npm run dev` | Запустить локальный dev-сервер на `localhost:4321` |
| `npm run build` | Собрать статический сайт в `dist/` |
| `npm run preview` | Просмотреть собранный сайт локально |

Из корня репозитория тот же dev-сервер запускается через `.claude/launch.json`
(запись `site-docs`).

## Диаграммы

Страницы архитектуры используют code-fence ` ```mermaid `, рендерящиеся
на клиенте через [`astro-mermaid`](https://github.com/wei/astro-mermaid) —
без build-time зависимости (Playwright/Chromium).
