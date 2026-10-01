## 1. Сверка с репозиторием

- [x] 1.1 Сверить каждое требование `openspec/specs/monorepo-workspace/spec.md` с репозиторием: раскладка (`melos.yaml`, корень), история переездов `structured_log` (decision 23 `add-structured-log-server`), формат `CHANGELOG.md` (`emb/structured_log_material/CHANGELOG.md`), линия тегов (`git tag`), состав скриптов `test`/`test:e2e`/`lint` в `melos.yaml`. Расхождение — во всех четырёх.
- [x] 1.2 Убедиться, что ни одна дельта не трогала `monorepo-workspace` после `add-structured-log-flutter`: у `add-structured-log-server` и архивных изменений `specs/monorepo-workspace/` нет.

## 2. Дельта

- [x] 2.1 `RENAMED` для двух требований, чьё название перестало быть правдой (плоская раскладка; перенос `structured_log/`), `MODIFIED` — для всех четырёх, заголовки `MODIFIED` совпадают с `TO`/базой посимвольно.
- [x] 2.2 `openspec validate align-monorepo-workspace-spec` проходит.

## 3. Архивация

- [ ] 3.1 Архивировать изменение с синхронизацией спеки (`openspec archive align-monorepo-workspace-spec`) и проверить, что `openspec/specs/monorepo-workspace/spec.md` содержит четыре требования, без дубликатов от переименования.
