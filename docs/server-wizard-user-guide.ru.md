# Визард на VPS (`server-setup-wizard.sh`) — только CI

> **Установка платформы** (GitHub Environments, секреты, стенды dev/test/MR, несколько VPS) — **только** с ноутбука:  
> **`./scripts/launchpad-run.sh`** + **`.env.platform`**. См. [launchpad.md](launchpad.md), [user-experience.md](user-experience.md).

Скрипт **`server-setup-wizard.sh`** оставлен для **автотеста в Docker** (`wizard-docker-test.yml`). Интерактивный запуск на VPS **отключён** (скрипт завершится с подсказкой про launchpad).

Для повседневной работы после launchpad см. [debian-wireguard-client.ru.md](debian-wireguard-client.ru.md), [stands-on-one-vps.md](stands-on-one-vps.md), [github-workflow.md](github-workflow.md).

---

## Общий процесс (5 шагов)

| Шаг | Где | Что делаешь |
|-----|-----|-------------|
| **1** | Ноутбук | Разработка, опционально локальный `docker compose` |
| **2** | GitHub | PR в **`dev`** (MR preview); для prod — merge **`dev` → `main`** |
| **3** | Ноутбук | **`./scripts/launchpad-run.sh`** — GitHub + VPS |
| **4** | GitHub | Тег на **`main`** + **Release** |
| **5** | VPS | Checkout тега + `docker compose up` (Actions) |

---

## Локальные помощники на ноутбуке

| Задача | Команда |
|--------|---------|
| Платформа | `./scripts/launchpad-run.sh` |
| Меню (smoke / compose) | `./scripts/interactive-setup.sh` |
| Убрать стенды с VPS | `TEARDOWN_CONFIRM=yes ./scripts/teardown-platform-run.sh` |

---

## DNS для стендов

| Стенд | Пример hostname |
|--------|-----------------|
| dev | `dev.vpn.example.com` |
| test | `test.vpn.example.com` |
| MR #42 | `mr-42.vpn.example.com` |

Wildcard **`*.ваша-зона`** → IP соответствующего `{PREFIX}_SSH_HOST`. Подробно: [stands-on-one-vps.md](stands-on-one-vps.md), [multi-server-deployment.md](multi-server-deployment.md).

---

## См. также

- [README.md](../README.md)
- [docs/github-workflow.md](github-workflow.md)
