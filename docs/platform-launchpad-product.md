# Platform Launchpad — отдельный продукт

**Platform Launchpad** — версионируемый продукт для bootstrap GitHub Environments, секретов и VPS под любое приложение.  
**Приложение** (например `dockerfile-vpn`) — центральный репозиторий со своим Compose, стендами, workflow и **своей** observability (Grafana/Loki) на VPS.

| Репозиторий | Роль |
|-------------|------|
| [panov-id/platform-launchpad](https://github.com/panov-id/platform-launchpad) | Продукт: launchpad-контейнер, generic-скрипты, semver, `ghcr.io/panov-id/platform-launchpad:X.Y.Z` |
| [panov-id/dockerfile-vpn](https://github.com/panov-id/dockerfile-vpn) | Приложение: WireGuard, стенды, GHA, Grafana/Loki **в этом репо** |

Пока отдельный репозиторий `platform-launchpad` поднимается вручную, в приложении лежит зеркало **`export/platform-launchpad/`** и режим **`embedded`** в `.platform.yaml`.

---

## Версионирование

- Продукт следует **[Semantic Versioning](https://semver.org/)** (`MAJOR.MINOR.PATCH`).
- Тег Git `v1.0.0` ↔ образ **`ghcr.io/panov-id/platform-launchpad:1.0.0`** (без префикса `v` в теге образа).
- В приложении поле **`platform_launchpad.version`** в `.platform.yaml` должно совпадать с образом при `source: registry`.
- Changelog продукта — в репозитории launchpad (`CHANGELOG.md`); приложение фиксирует **какую версию launchpad использует** в `.platform.yaml`.

Обновление launchpad в приложении:

1. Выпустить релиз `platform-launchpad` (тег + образ).
2. В приложении: `platform_launchpad.version: "1.1.0"`, при необходимости обновить `export/platform-launchpad/`.
3. Прогнать `./scripts/launchpad-run.sh` (идемпотентно для GitHub/VPS bootstrap).

---

## Подключение приложения

### 1. Манифест (в git)

```bash
cp .platform.yaml.example .platform.yaml
```

Минимальный проект (**dev + production**, один VPS):

```yaml
platform_launchpad:
  source: embedded   # или registry после публикации образа
  image: ghcr.io/panov-id/platform-launchpad
  version: "1.0.0"

platform_environments:
  - production
  - dev

application:
  repository_slug: your-org/your-app
  compose_file: docker-compose.yml

observability_stand_enabled: true   # опционально
```

### 2. Секреты (не в git)

```bash
cp .env.platform.example .env.platform
```

Только блоки `PRODUCTION_*`, `DEV_*` (без UAT/TEST/MR, если не нужны).

### 3. Запуск

```bash
./scripts/launchpad-run.sh
```

Читает `.platform.yaml` + `.env.platform`, поднимает launchpad (`embedded` — compose из репо; `registry` — `docker pull` + `docker run`).

---

## Observability — в каждом приложении

Grafana, Loki и Promtail **не** входят в platform-launchpad. Они живут в репозитории приложения:

- `docker-compose.observability.yml`
- `observability/` — конфиги
- стенд **`observability`** в `scripts/stand-layout.sh`

На VPS один раз на сервер (в `BOOTSTRAP_STANDS` **одного** environment-блока):

```env
PRODUCTION_BOOTSTRAP_STANDS=production,observability
```

DNS: `grafana.<STAND_DNS_ZONE>`. Логи контейнеров с метками `logging.app` / `logging.stand` (см. `docker-compose.yml`).

Локально:

```bash
docker compose -f docker-compose.observability.yml --env-file .env.observability.example up -d
```

---

## Режимы launchpad

| `source` | Когда |
|----------|--------|
| `embedded` | Разработка, пока нет опубликованного образа; скрипты из `export/platform-launchpad` или fallback `docker/` в приложении |
| `registry` | CI/команда: фиксированный образ по semver |

---

## Мягкий деплой стендов

На VPS: `docker compose up -d --pull always` **без** `down` — минимальный простой при обновлении. Первый деплой поднимает стенд с нуля.

---

## Следующий шаг (отдельный репозиторий)

Содержимое `export/platform-launchpad/` переносится в `github.com/panov-id/platform-launchpad`, публикуется GHCR, приложения переключаются на `source: registry`.
