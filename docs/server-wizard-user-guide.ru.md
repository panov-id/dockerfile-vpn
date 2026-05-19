# Визард на VPS: как пользоваться (`server-setup-wizard.sh`)

**Скрипт:** `scripts/server-setup-wizard.sh` — только **на сервере** после `git clone`.  
**Не путать** с `scripts/interactive-setup.sh` на ноутбуке (меню; пункт **8** — launchpad).

**Рекомендуемая первичная настройка с ноутбука:** [`docs/launchpad.md`](launchpad.md) — `./scripts/launchpad-run.sh` и `.env.platform`. Этот визард нужен, если настраиваешь **только VPS вручную** или донастраиваешь один стенд.

Язык подсказок в терминале: **русский**, если `LANG` начинается с `ru`, или явно `WIZARD_LANGUAGE=ru`. Иначе — английский (`WIZARD_LANGUAGE=en`).

---

## Где это в общем процессе (5 шагов)

| Шаг | Где | Что делаешь |
|-----|-----|-------------|
| **1** | Ноутбук | Разработка, опционально локальный `docker compose` |
| **2** | GitHub | PR в **`dev`** (MR preview); для prod позже — merge **`dev` → `main`** (сам merge в `main` **не** деплоит) |
| **3** | Ноутбук + VPS | Обычно **`./scripts/launchpad-run.sh`**; альтернатива на VPS — **`server-setup-wizard.sh`** ← этот документ |
| **4** | GitHub | Тег на **`main`** + **опубликовать Release** → Actions |
| **5** | VPS | Checkout тега + `docker compose up` (автоматически из workflow) |

После шага **3:** фичи **1 → PR в `dev` → merge**; production **merge `dev`→`main` → 4 → 5**.

В начале визард печатает эту же схему. В конце — чеклист для шагов **4–5**.

---

## Запуск

```bash
git clone git@github.com:panov-id/dockerfile-vpn.git
cd dockerfile-vpn
chmod +x scripts/server-setup-wizard.sh
./scripts/server-setup-wizard.sh
# или явно:
WIZARD_LANGUAGE=ru ./scripts/server-setup-wizard.sh
```

**Нужно заранее:** Git на VPS, `sudo` при установке Docker/ufw, UDP-порт в панели провайдера.

---

## Этапы визарда (6 блоков в терминале)

Каждый блок помечен `[Визард N/6]`. Ниже — **описание**, **примеры ответов** и что происходит.

---

### [Визард 1/6] Каталог деплоя (`DEPLOY_DIRECTORY`)

**Зачем:** GitHub Actions по SSH заходит в **один каталог** и выполняет `git fetch --tags`, `git checkout <тег Release>`, `docker compose up`. Путь копируется в GitHub → Environment → **`DEPLOY_DIRECTORY`**.

#### Вопрос: «Использовать ЭТОТ clone как каталог деплоя? [Y/n]»

| Ответ | Пример ситуации | Результат |
|--------|-----------------|-----------|
| **Enter / Y** | Клонировал в `/home/deploy/dockerfile-vpn` и хочешь деплоить оттуда | `DEPLOY_DIRECTORY` = этот путь |
| **n** | Production в `/srv/vpn/production`, а визард запустил из временного clone | Спросят URL, путь, ветку, shallow |

#### Если ответили **n** — дополнительные вопросы

**URL для git clone**

| Пример | Когда |
|--------|--------|
| `git@github.com:panov-id/dockerfile-vpn.git` | SSH-ключ на сервере уже настроен |
| `https://github.com/panov-id/dockerfile-vpn.git` | HTTPS + token (реже на VPS) |

**Абсолютный путь каталога**

| Пример | Когда |
|--------|--------|
| `/srv/vpn/production` | Один стек production |
| `/srv/vpn/uat` | Второй стек UAT на том же VPS |
| `/opt/stacks/vpn` | Своя иерархия каталогов |

**Ветка Git [main]**

| Пример | Когда |
|--------|--------|
| `main` | Почти всегда |
| `develop` | Только если осознанно трекаешь другую ветку на сервере |

**Shallow clone [y/N]**

| Ответ | Рекомендация |
|--------|----------------|
| **N** (по умолчанию) | Нормальный clone с тегами для Release |
| **Y** | Только если понимаешь, что теги могут не подтянуться |

---

### [Визард 2/6] Docker Engine + Compose

**Зачем:** без `docker compose` не поднять WireGuard и не отработает деплой на шаге 5.

Если Compose уже есть — блок только сообщает об этом и идёт дальше.

#### Вопрос (если Compose нет): «Установить Docker через apt? [Y/n]»

| Ответ | Когда |
|--------|--------|
| **Y** | Debian/Ubuntu, чистый VPS |
| **n** | Ставишь Docker вручную → потом **снова** запусти визард |

---

### [Визард 3/6] Группа docker (если не root)

**Зачем:** чтобы `docker compose` работал от твоего SSH-пользователя без sudo (и чтобы тот же пользователь подходил для deploy key в Actions).

**Не показывается**, если визард запущен от **root**.

#### Вопрос: «Добавить '<логин>' в группу docker? [Y/n]»

| Ответ | После |
|--------|--------|
| **Y** | Перелогинься по SSH или `newgrp docker` |
| **n** | На шаге `compose up` может использоваться sudo |

---

### [Визард 4/6] История Git для тегов (только shallow clone)

**Зачем:** деплой Release делает `git checkout v1.2.0` — нужны **теги** в clone.

**Пропускается**, если clone не shallow.

#### Вопрос: «Выполнить git fetch --unshallow? [Y/n]»

| Ответ | Когда |
|--------|--------|
| **Y** | Первый раз настраиваешь сервер после shallow clone |
| **n** | Риск: при Release checkout тега может не быть |

---

### [Визард 5/6] WireGuard / Compose (`.env`)

**Зачем:** параметры стека на этом VPS; файл **не коммитится** в Git.

#### Подраздел: профиль стека `[production/uat/custom]`

(внутри этапа 5/6, сразу после заголовка «WireGuard / Compose»)

Задаёт **значения по умолчанию** для порта, подсети и имени проекта.

| Профиль | `COMPOSE_PROJECT_NAME` | UDP-порт | Подсеть |
|---------|------------------------|----------|---------|
| **production** (Enter) | `vpn-production` | 51820 | 10.13.13.0 |
| **uat** | `vpn-uat` | 51821 | 10.13.14.0 |
| **custom** | спросит всё вручную (дефолты как production) |

**Примеры на одном VPS:**

- Production: профиль **production**, путь `/srv/vpn/production`, порт **51820**
- UAT: профиль **uat**, путь `/srv/vpn/uat`, порт **51821**, в GitHub Environment **uat** и свой `DEPLOY_DIRECTORY`

#### Если `.env` уже есть: «перенастроить поля? [Y/n]»

| Ответ | Когда |
|--------|--------|
| **Y** | Меняешь IP, порт или имя проекта |
| **n** | Только проверить Docker / firewall, `.env` не трогать |

#### `WIREGUARD_SERVER_PUBLIC_HOST`

| Пример | Когда |
|--------|--------|
| `vpn.example.com` | Есть DNS на IP VPS |
| `203.0.113.10` | Только IP |
| `wg.company.net` | Поддомен |

Пустое значение — **предупреждение**: клиенты не подключатся, пока не задашь хост в `.env`.

#### `WIREGUARD_SERVER_PORT` [дефолт из профиля]

| Пример | Когда |
|--------|--------|
| Enter | Устраивает дефолт профиля (51820 / 51821) |
| `51830` | 51820 занят другим сервисом |
| `41194` | Нестандартный порт по политике |

#### `WIREGUARD_INTERNAL_SUBNET` [дефолт из профиля]

| Пример | Когда |
|--------|--------|
| `10.13.13.0` | Production |
| `10.13.14.0` | UAT на том же хосте |
| `10.8.0.0` | Своя схема адресации |

#### `COMPOSE_PROJECT_NAME` [дефолт из профиля]

| Пример | Когда |
|--------|--------|
| `vpn-production` | Production |
| `vpn-uat` | UAT |
| `vpn-test-51822` | Тестовый стек с уникальным портом |

---

### [Визард 6/6] Фаервол ufw (если установлен `ufw`)

**Зачем:** правило на **хосте**. Порт в **панели Hetzner/DO/…** всё равно открой отдельно.

**Пропускается**, если `ufw` нет.

#### Вопрос: «Открыть UDP <порт> в ufw? [y/N]»

| Ответ | Когда |
|--------|--------|
| **y** | ufw используешь на VPS |
| **N** | Только cloud firewall или nftables |

---

### Первый запуск стека (подблок, без отдельного номера)

#### «Запустить docker compose up -d сейчас? [y/N]»

| Ответ | Когда |
|--------|--------|
| **y** | Хочешь проверить WireGuard до первого Release |
| **N** | Дождёшься Release (шаг 4) или поднимешь вручную |

---

## Финиш: что скопировать в GitHub

Визард печатает:

```text
DEPLOY_DIRECTORY = /абсолютный/путь/к/clone
```

Плюс напоминание: секреты **`SSH_HOST`**, **`SSH_USER`**, **`SSH_PRIVATE_KEY`**, затем **Release** (шаг 4) и проверка **`docker compose ps`** (шаг 5).

---

## Готовые сценарии (шпаргалка)

### A. Первый production на VPS (типичный)

1. `git clone` → `cd dockerfile-vpn`
2. `WIZARD_LANGUAGE=ru ./scripts/server-setup-wizard.sh`
3. **Y** — этот clone  
4. **Y** — Docker apt (если спросит)  
5. **Y** — группа docker  
6. **Y** — unshallow (если спросит)  
7. Профиль **production** (Enter)  
8. Публичный хост: IP или DNS VPS  
9. Остальное Enter  
10. **y** или **N** на ufw / compose up — по желанию  
11. Скопировать `DEPLOY_DIRECTORY` в GitHub → **production**  
12. Release `v1.0.0` → смотреть логи на VPS  

### B. Второй стек UAT на том же сервере

1. Запусти визард снова (можно из другого clone или **n** → путь `/srv/vpn/uat`)  
2. Профиль **uat**  
3. Порт **51821**, подсеть **10.13.14.0**, проект **vpn-uat**  
4. `DEPLOY_DIRECTORY` → GitHub Environment **uat** (другой путь и секреты при необходимости)  
5. Release с галочкой **pre-release** → деплой в UAT  

### C. Только поправить `.env`

1. Запусти визард в том же каталоге деплоя  
2. **Y** на «этот clone»  
3. На «перенастроить .env» → **Y**  
4. Введи новый хост/порт  
5. **N** на compose up, если контейнеры уже крутятся  

### D. Отдельный каталог `/srv/vpn/production`

1. **n** на «этот clone»  
2. URL: `git@github.com:panov-id/dockerfile-vpn.git`  
3. Путь: `/srv/vpn/production`  
4. Ветка: `main`, shallow: **N**  
5. Дальше как в сценарии A  

---

## Автотест в Docker (не для ручной настройки)

`docker/docker-compose.wizard-test.yml` + `scripts/test-wizard-docker.sh` — те же вопросы, ответы подставляются автоматически. Для оператора VPS используй только SSH и **`./scripts/server-setup-wizard.sh`**.

---

## DNS для стендов (dev / test / MR)

Визард настраивает **один** каталог на VPS. Для **нескольких стендов** на одном сервере (dev, test, MR preview) используй GitHub Actions и переменную **`STAND_DNS_ZONE`**:

| Стенд | Пример hostname |
|--------|-----------------|
| dev | `dev.vpn.example.com` |
| test | `test.vpn.example.com` |
| MR #42 | **`mr-42.vpn.example.com`** |

У DNS-провайдера: wildcard **`*.vpn.example.com`** → IP VPS. Подробно: **[docs/stands-on-one-vps.md](stands-on-one-vps.md)**.

Профили **dev** / **test** / **uat** / **production** в визарде совпадают с портами и подсетями из **`scripts/stand-layout.sh`**.

---

## См. также

- [README.md](../README.md) — **Your workflow in five steps**, **Dev, test, and MR preview**
- [docs/github-workflow.md](github-workflow.md) — ветки, PR в `dev`, CI, Release
- [docs/stands-on-one-vps.md](stands-on-one-vps.md) — порты, DNS, GitHub Environments
