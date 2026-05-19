# Пользовательский опыт (User Experience)

Как этот репозиторий **ощущается** для разработчика и владельца VPS: что делаешь ты, что делает автоматика, что видишь в GitHub и на сервере.

Технические детали: [README](../README.md), [github-workflow.md](github-workflow.md), [stands-on-one-vps.md](stands-on-one-vps.md), [server-wizard-user-guide.ru.md](server-wizard-user-guide.ru.md).

---

## Роли

| Роль | Обычно кто | Главная цель |
|------|-----------|--------------|
| **Разработчик** | Ты на ноутбуке | Написать код, проверить на стенде, смержить в `dev`, потом в `main` |
| **Владелец платформы** | Ты же, один раз | Поднять VPS, DNS, секреты GitHub — без ручного копипаста в UI |
| **Пользователь VPN** | Ты или команда | Подключиться по WireGuard к нужному стенду (dev / MR / production) |

Сейчас все стенды **на одном VPS**; позже можно разнести по серверам без смены привычного процесса.

---

## Первая настройка (один раз)

### Что ты делаешь

1. Клонируешь репозиторий на ноутбук.
2. Копируешь шаблон: `cp .env.platform.example .env.platform`.
3. Заполняешь **`.env.platform`**: VPS, deploy-ключ (**без passphrase**), PAT, DNS — см. **[deploy-ssh-key.md](deploy-ssh-key.md)** и чеклист в `.env.platform.example`.
4. Проверяешь ключ: **`./scripts/verify-deploy-ssh-key.sh`** (опционально; `launchpad-run.sh` вызывает сам).
5. Запускаешь: **`./scripts/launchpad-run.sh`** — на хосте только **Docker**.

Контейнер **launchpad** сам ставит внутри себя `gh`/`git`/`ssh` и выполняет настройку.

### Как создать PAT (`GITHUB_TOKEN`)

Токен нужен **один раз** для launchpad: через него внутри контейнера вызываются `gh` (секреты, environments, ветки `dev`/`test`) и при необходимости `git push` по HTTPS.

**Куда вставить:** строка `GITHUB_TOKEN=...` в **`.env.platform`** на ноутбуке. Файл в `.gitignore` — **никогда** не коммить токен.

#### Где живёт репозиторий (веб и PAT)

Этот проект на **GitHub.com** — не путай с произвольным hostname в своём `git remote` по SSH: для launchpad и PAT всегда **github.com**.

| Что | Адрес |
|-----|--------|
| Репозиторий | **https://github.com/panov-id/dockerfile-vpn** |
| PAT (fine-grained) | **https://github.com/settings/personal-access-tokens** |
| PAT (classic) | **https://github.com/settings/tokens** |

В **`.env.platform`** для обычного GitHub.com **не задавай** `GH_HOST` / `GITHUB_API_URL` (оставь закомментированными в `.env.platform.example`). Они нужны только для **корпоративного** GitHub Enterprise Server с отдельным доменом.

#### Вариант A — Fine-grained PAT (предпочтительно)

1. Открой **https://github.com** → аватар (правый верх) → **Settings**.
2. Слева внизу: **Developer settings** → **Personal access tokens** → **Fine-grained tokens**.
3. **Generate new token**.
4. Заполни:
   - **Token name** — например `dockerfile-vpn-launchpad` (по имени поймёшь, зачем токен).
   - **Expiration** — 90 дней или Custom; поставь напоминание обновить до истечения.
   - **Resource owner** — организация **`panov-id`** (или свой user, если репо под личным аккаунтом).
   - **Repository access** — **Only select repositories** → выбери **`dockerfile-vpn`**.
5. **Repository permissions** (минимум для launchpad):

   | Permission | Уровень | Зачем |
   |------------|---------|--------|
   | **Contents** | Read and write | push веток `dev` / `test`, clone по HTTPS |
   | **Metadata** | Read-only | обычно обязателен по умолчанию |
   | **Actions** | Read and write | workflows, environment **Variables** |
   | **Administration** | Read and write | создать **Environments** |
   | **Secrets** | Read and write | `SSH_*` в environments (`403` на `public-key` без этого) |

   Если после запуска launchpad падает на **«failed to create environment»** — добавь права на administration или используй classic PAT (вариант B).

   Если при создании веток **`403 Resource not accessible by personal access token`** — у токена нет **Contents: Read and write** (или не нажат **Configure SSO → Authorize** для организации `panov-id` на странице токена).

6. **Generate token** → **скопируй сразу** (второй раз не покажут). Вставь в `.env.platform`:

   ```bash
   GITHUB_TOKEN=github_pat_xxxxxxxx
   ```

#### Вариант B — Classic PAT (проще, шире права)

1. **https://github.com/settings/tokens** → **Generate new token** → **Tokens (classic)** (или сразу classic из Developer settings).
2. **Generate new token (classic)**.
3. **Note:** `dockerfile-vpn-launchpad`.
4. **Expiration** — по политике (90d / custom).
5. Отметь scope **`repo`** (полный доступ к приватным репозиториям) и **`workflow`** (если просит для Actions).
6. **Generate token** → скопируй в `GITHUB_TOKEN=ghp_...` в `.env.platform`.

Classic даёт больше прав, чем нужно — удобно для отладки; для продакшн-аккаунта лучше fine-grained с узким списком репозиториев.

#### Проверка, что токен подходит

После сохранения `.env.platform`:

```bash
./scripts/launchpad-diagnose-git.sh
```

Ожидаешь в выводе:

- `gh auth status` — **github.com**, не «hostname not found»;
- список веток с **`main`** (и позже **`dev`**, **`test`**);
- без `401` / `403` / `Resource not accessible`.

Создать ветки принудительно:

```bash
./scripts/launchpad-diagnose-git.sh --try-create
```

Подробнее: [launchpad.md](launchpad.md).

#### Безопасность

- Токен = пароль к репозиторию и секретам CI — не отправляй в чат, не вставляй в issue/PR.
- Срок действия истёк → сгенерируй новый, обнови `.env.platform`, снова `./scripts/launchpad-run.sh`.
- Утечка → **Revoke** токен в GitHub Settings и выпусти новый.

### Что происходит без твоего участия

- На origin появляются ветки **`dev`** и **`test`**, если их ещё не было (сразу в начале прогона).
- В GitHub создаются **Environments** и заливаются **секреты/переменные** для `production`, `uat`, `dev`, `test`, `mr-preview`.
- По SSH на VPS: при необходимости **Docker + Compose** (apt на Debian/Ubuntu), затем каталоги стендов, clone, `.env`, `docker compose up` (`dev`, `test`, `uat`, `production` по умолчанию).
- Локально (если есть Docker): проверка `docker compose config`.

### Что остаётся только у тебя (вне скриптов)

| Действие | Где | Зачем |
|----------|-----|--------|
| DNS `*.vpn.example.com` → IP VPS | Панель регистратора / Cloudflare | Чтобы `mr-42.vpn.example.com` и `dev.vpn.example.com` резолвились |
| UDP-порты в firewall облака | Hetzner, DO, … | WireGuard ходит по UDP (51820–51823, 51900+ для MR) |
| `GITHUB_TOKEN` в `.env.platform` | Файл на диске | PAT — см. [Как создать PAT](#как-создать-pat-github_token) |

После этого **повторять setup-platform** нужно только если сменился VPS, ключ или зона DNS.

---

## Ежедневная работа: новая фича

Путь, который задуман как «нормальный день разработчика».

```text
ноутбук                    GitHub                         VPS (один сервер)
────────                   ──────                         ────────────────

правки кода
    │
    ├─ опционально: local-compose-up / smoke
    │                 (только твой ПК, config.local)
    │
    v
git push feature/xyz
    │
    v
открываешь PR ──────────►  CI: compose-validate
    в ветку dev            (и wizard-test при изменении визарда)
    │
    │                      deploy-mr-preview
    │                           │
    │                           v
    │                      стенд mr-<N>
    │                      pull/N/merge
    │                      mr-42.vpn.example.com:51942
    │
    ◄──────────────────  комментарий в PR:
                         host, port, каталог на VPS

ты подключаешься WireGuard
к mr-42.vpn.example.com
и «щупаешь» результат
ДО нажатия Merge

    │
    v
Merge в dev ───────────►  push dev
                               │
                               v
                          стенд dev обновился
                          dev.vpn.example.com:51823

    │
    v (когда готово к prod)
merge dev → main
    │
    v
тег v1.2.0 + Release ──►  deploy-release
    (pre-release → uat)         │
    (stable → production)       v
                          checkout тега
                          vpn.example.com:51820
```

### Что ты **не** делаешь вручную

- Не SSH на сервер ради каждого деплоя feature-ветки.
- Не создаёшь отдельный DNS на каждый MR (достаточно wildcard `*.vpn.example.com`).
- Не поднимаешь контейнеры для MR-preview — workflow сам checkout merge-ref и `compose up`.

### Что ты **видишь**

| Место | Обратная связь |
|-------|----------------|
| **PR → Checks** | Зелёный/красный `compose-validate`, при необходимости `wizard-docker-test` |
| **PR → Comment** | Блок «MR preview stand»: DNS, UDP-порт, путь на VPS |
| **Actions** | Логи `Deploy merge request preview`, `Deploy dev stand`, … |
| **После Merge в dev** | Workflow на push в `dev` — обновление постоянного dev-стенда |

### Если PR не мержится в `dev`

Конфликты → GitHub **не отдаёт** `pull/N/merge` → preview-деплой **падает**. Ты видишь красный job; после разрешения конфликтов — новый push в PR → preview пересобирается.

---

## Стенды с точки зрения пользователя

Один физический сервер, **разные «виртуальные» VPN** — разный адрес и порт в клиенте.

| Стенд | Когда живёт | Как подключиться (пример) | Смысл |
|-------|-------------|-----------------------------|--------|
| **mr-42** | Пока PR открыт | `mr-42.vpn.example.com:51942` | «Как будет после merge в dev» |
| **dev** | Постоянно | `dev.vpn.example.com:51823` | Интеграция после merge |
| **test** | После push в `test` | `test.vpn.example.com:51822` | Отдельная линия для test-ветки |
| **uat** | Pre-release | `uat.vpn.example.com:51821` | Как prod, но из pre-release |
| **production** | Stable Release | `vpn.example.com:51820` | Боевой |

Конфиги пиров лежат в `config/` **внутри каталога стенда** на VPS (не в git).

### Подключение с Debian / GNOME (постоянный профиль)

Один раз импорт в **NetworkManager** (`nmcli`), дальше вкл/выкл из меню сети — без `wg-quick` при каждом входе:

**[debian-wireguard-client.ru.md](debian-wireguard-client.ru.md)** — скачать `peer1.conf`, `nmcli connection import`, переключатель VPN на панели GNOME, автоподключение, безопасность.

---

## Путь в production (релиз)

1. Код в **`main`** (часто через merge из `dev`).
2. Ты создаёшь **тег** и **публикуешь Release** на GitHub.
3. **Merge в `main` сам по себе VPS не трогает** — только Release.
4. Actions заходят на production-каталог, `git checkout` тега, `docker compose up`.
5. Ты проверяешь: клиент на `vpn.example.com`, или `docker compose ps` по SSH.

**Pre-release** → окружение **uat** (тот же механизм, другой каталог/порт/DNS).

---

## Локальная разработка (ноутбук)

Отдельный мир: **не бьёт по VPS**.

| Действие | Команда | Ощущение |
|----------|---------|----------|
| Поднять стек | `./scripts/local-compose-up.sh` | WireGuard в Docker, порт из `.env.local` (часто 51830) |
| Smoke | `./scripts/local-smoke-check.sh` | «Порт слушает, wg0.conf есть» |
| Два стека сразу | `./scripts/local-two-stacks-test.sh` | Репетиция двух VPS на одной машине |

Файлы: `.env.local`, `config.local/` — в `.gitignore`.

---

## Альтернативные входы (если не setup-platform)

| Сценарий | Инструмент | Когда |
|----------|------------|--------|
| Полная автоматика | `./scripts/launchpad-run.sh` + `.env.platform` | **Рекомендуется** |
| Интерактивное меню на ноутбуке | `interactive-setup.sh` | Пункт 8 → launchpad |
| Первый VPS вручную по SSH | `server-setup-wizard.sh` | Уже на сервере после `git clone`, пошаговые вопросы |
| Без вопросов на VPS | `vps-bootstrap.sh` | Root + env vars, один прогон |

Визард на VPS и `setup-platform` **не дублируют** друг друга: platform — с ноутбука «всё сразу»; визард — если настраиваешь сервер отдельно.

---

## Карта «кто за что отвечает»

```mermaid
flowchart TB
  subgraph user [Ты]
    CODE[Код и PR]
    SECRETS[.env.platform]
    DNS[DNS у регистратора]
    FW[Firewall облака]
  end

  subgraph laptop [Ноутбук]
    SETUP[launchpad-run.sh]
    LOCAL[local-compose / smoke]
  end

  subgraph github [GitHub]
    CI[compose-validate]
    MR[deploy-mr-preview]
    DEV[deploy-dev-stand]
    REL[deploy-release]
  end

  subgraph vps [VPS]
    MRST[mr-N stand]
    DEVST[dev stand]
    PROD[production stand]
  end

  SECRETS --> SETUP
  SETUP --> github
  CODE --> CI
  CODE --> MR
  MR --> MRST
  CODE --> DEV
  DEV --> DEVST
  CODE --> REL
  REL --> PROD
  DNS --> MRST
  DNS --> DEVST
  DNS --> PROD
  FW --> vps
  LOCAL --> CODE
```

---

## Ожидания и ограничения (честно)

| Ожидание | Реальность |
|----------|------------|
| «Запушил в feature — сразу на prod» | **Нет.** Prod только через **Release** с `main`. |
| «MR preview = моя ветка как есть» | **Нет.** Это **merge в dev** (`pull/N/merge`), не tip feature-ветки. |
| «Один hostname на всё» | Только без `STAND_DNS_ZONE`. С зоной — **отдельный DNS на стенд**. |
| «Ничего не трогать в DNS» | Нужен хотя бы **wildcard** на VPS IP. |
| «1000 открытых MR одновременно» | Порты MR: 51900+N, лимит ~1099 по формуле. |

---

## Краткая шпаргалка команд

| Задача | Команда |
|--------|---------|
| Deploy-ключ (без passphrase) | [deploy-ssh-key.md](deploy-ssh-key.md), `verify-deploy-ssh-key.sh` |
| Всё настроить с ноутбука | `./scripts/launchpad-run.sh` |
| PAT / ветки | `./scripts/launchpad-diagnose-git.sh` |
| Алиас | `source scripts/platform-aliases.sh` → `vpn-setup` |
| Локальный VPN | `./scripts/local-compose-up.sh` |
| Проверить compose | `./scripts/compose-config-check.sh` |
| Hostname стенда | `STAND_DNS_ZONE=vpn.example.com ./scripts/stand-resolve-public-host.sh mr 42` |
| Клиент Debian/GNOME | [debian-wireguard-client.ru.md](debian-wireguard-client.ru.md) |
| Визард на VPS (ручной) | `./scripts/server-setup-wizard.sh` |

---

## Связанные документы

| Документ | Содержание |
|----------|------------|
| [README.md](../README.md) | Цели, 5 шагов, layout репозитория |
| [CONTRIBUTING.md](../CONTRIBUTING.md) | Куда смотреть новому участнику |
| [github-workflow.md](github-workflow.md) | Ветки, CI, Release (EN) |
| [stands-on-one-vps.md](stands-on-one-vps.md) | Порты, DNS, variables |
| [server-wizard-user-guide.ru.md](server-wizard-user-guide.ru.md) | Каждый вопрос визарда на VPS |
| [deploy-ssh-key.md](deploy-ssh-key.md) | Deploy-ключ без passphrase (EN) |
| [launchpad.md](launchpad.md) | Launchpad (EN) |
| [debian-wireguard-client.ru.md](debian-wireguard-client.ru.md) | Клиент WireGuard на Debian/GNOME (постоянный профиль NM) |
