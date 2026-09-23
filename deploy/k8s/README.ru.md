# Развёртывание в Kubernetes

Самостоятельный `structured_log` в Kubernetes: те же два образа, что
[`deploy/`](../) собирает для Docker Compose, только манифестами
[Kustomize](https://kustomize.io/) вместо compose-файла — `base/`,
общий для обоих backend'ов хранения, и по одному overlay на backend
(`overlays/sqlite/`, `overlays/postgres/`). Без Helm, без отдельного
языка шаблонов — `kubectl` понимает Kustomize нативно.

За обоснованием неочевидных частей этой настройки (почему сервер может
работать только в одной реплике, две реальные ловушки, найденные при
сборке этого) — см.
[docs/guides/admin-guide.ru.md#kubernetes](../../docs/guides/admin-guide.ru.md#kubernetes).
Этот файл — короткий практический спутник, вручную проверенный на
локальном кластере (`minikube`, ingress-nginx) при написании, а не
просто написанный по прочтении конфига.

## Быстрый старт

```bash
cd deploy/k8s

# Собрать оба образа и сразу загрузить в локальный кластер для проверки
# — за всем остальным см. «Сборка для настоящего кластера» ниже.
./build-images.sh --load minikube        # или: --load kind

./create-secrets.sh                      # генерирует JWT-секрет подписи
kubectl apply -k overlays/sqlite         # или: overlays/postgres

kubectl -n structured-log rollout status deployment/structured-log-server
kubectl -n structured-log logs deploy/structured-log-server | grep -i 'temporary password'
```

Последняя строка — сгенерированный пароль первого администратора,
напечатанный один раз — захватите его, пока он не пролистался. Его
нужно сменить при первом входе, как и в любом другом пути
развёртывания.

Для быстрой локальной проверки достаточно `kubectl -n structured-log
port-forward svc/web 8080:80`; для чего-то настоящего — настройте
поставляемый `Ingress` как следует (ниже).

## Что здесь

```
base/                    # общее для обоих backend'ов: namespace,
                          # Service "server", Deployment/Service web,
                          # Ingress
overlays/sqlite/          # + PVC, Deployment сервера (на SQLite,
                          # strategy: Recreate)
overlays/postgres/        # + минимальный PostgreSQL внутри кластера
                          # (StatefulSet), Deployment сервера
                          # (на PostgreSQL)
build-images.sh           # собирает/пушит/загружает оба образа
create-secrets.sh         # генерирует Secret'ы, которые ждут манифесты
```

Выбирайте ровно один overlay — `kubectl apply -k overlays/sqlite`
**или** `overlays/postgres`, никогда оба сразу в один namespace.

## Сборка для настоящего кластера

`build-images.sh` без флагов просто собирает и тегирует локально
(`structured-log-server:local` / `structured-log-web:local`) — этого
достаточно для `--load minikube`/`--load kind`, но не для остального.
kubelet многоузлового кластера тянет образы из registry; он не видит
Docker-демон вашего ноутбука:

```bash
./build-images.sh --push registry.example.com/structured-log --tag v1.2.3
```

затем направьте overlay на то, что реально запушено — либо
отредактируйте строки `image:` напрямую в
`overlays/*/server-deployment.yaml` и `base/web-deployment.yaml`, либо
воспользуйтесь собственным механизмом Kustomize для этого вместо ручной
правки:

```bash
cd overlays/sqlite   # или overlays/postgres
kustomize edit set image \
  structured-log-server:local=registry.example.com/structured-log/structured-log-server:v1.2.3 \
  structured-log-web:local=registry.example.com/structured-log/structured-log-web:v1.2.3
```

## Секреты

```bash
./create-secrets.sh              # только JWT-секрет подписи (overlay sqlite)
./create-secrets.sh --postgres   # + сгенерированный пароль PostgreSQL
```

Безопасно перезапускать — существующий секрет остаётся нетронутым, пока
не передан явный `--rotate`, ровно затем, чтобы нельзя было по привычке
разлогинить все сессии в кластере. Если у вас уже есть
PostgreSQL и вы пропустили
`overlays/postgres/postgres-statefulset.yaml`, задайте
`STRUCTURED_LOG_DB_POSTGRES_PASSWORD` из своего собственного секрета —
`postgres-secrets`/`postgres-password` здесь только для встроенного
инстанса внутри кластера.

## Ingress

`base/ingress.yaml` поставляется с placeholder-хостом
(`logs.example.com`) и двумя правилами по пути — `/v1` напрямую на
Service `server`, всё остальное — на `web`. Образ `web` сам ничего не
проксирует (в отличие от пути через Docker Compose, которому для
такого же разделения нужен собственный контейнер `proxy` — см.
[`deploy/proxy/`](../proxy/)); Ingress уже делает это сам, ничего
дополнительного запускать не нужно. Отредактируйте поле `host:` под
свой домен, либо переопределите его для каждого overlay отдельно
небольшим Kustomize-патчем, если
нужны разные хосты для окружений `sqlite`/`postgres`. Требует уже
установленного в кластере ingress-контроллера (`ingressClassName:
nginx` — замените на тот, что реально есть); этот репозиторий его за
вас не устанавливает.

## Удаление

```bash
kubectl delete -k overlays/sqlite        # или overlays/postgres
kubectl -n structured-log delete secret structured-log-secrets postgres-secrets --ignore-not-found
kubectl delete namespace structured-log  # удаляет и PVC — данные уходят вместе с ним
```

## См. также

- [docs/guides/admin-guide.ru.md](../../docs/guides/admin-guide.ru.md) —
  полное руководство оператора: выбор backend'а хранения,
  retention/квоты, резервное копирование, безопасность, обновление,
  диагностика — включая Kubernetes.
- [../](../) — путь через Docker Compose, для развёртывания на одном
  сервере, которому оркестратор вообще не нужен.
