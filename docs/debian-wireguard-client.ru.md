# Debian / GNOME: постоянный клиент WireGuard (без `wg-quick` каждый раз)

Как один раз добавить VPN в **NetworkManager** и дальше включать/выключать **из меню GNOME** (верхняя панель или «Параметры → Сеть»).

Сервер в этом репозитории — **linuxserver/wireguard** на VPS; конфиг пира лежит на сервере в `config/peer1/` (не в git).

---

## Что понадобится

| Что | Зачем |
|-----|--------|
| Файл **`peer1.conf`** (или другой peer) | Скачан с VPS, например production |
| **`wireguard`** + **`wireguard-tools`** | Модуль и утилиты |
| **NetworkManager** (`network-manager`) | Уже есть в GNOME на Debian |
| Права **`sudo`** | Один раз при импорте профиля |

На Debian 13 (Trixie) и GNOME 48 отдельный пакет `network-manager-wireguard` **не нужен**: в NetworkManager **1.16+** WireGuard встроен.

Пакеты (если чего-то нет):

```bash
sudo apt update
sudo apt install wireguard wireguard-tools network-manager
```

---

## 1. Скачать конфиг с VPS

Пример для **production** (`vpn.panov.id`, UDP **51820**):

```bash
scp -i ~/.ssh/vpn_deploy_ed25519 \
  root@ВАШ_VPS_IP:/srv/vpn/production/config/peer1/peer1.conf \
  ~/Downloads/vpn-panov-production.conf
```

Другие стенды — тот же путь, другой каталог:

| Стенд | Каталог на VPS | Endpoint (пример) |
|-------|----------------|-------------------|
| production | `/srv/vpn/production` | `vpn.panov.id:51820` |
| uat | `/srv/vpn/uat` | `uat.vpn.panov.id:51821` |
| test | `/srv/vpn/test` | `test.vpn.panov.id:51822` |
| dev | `/srv/vpn/dev` | `dev.vpn.panov.id:51823` |

В файле в секции `[Peer]` должны быть **`Endpoint = ваш-домен:порт`** и ключи — не редактируй вручную без необходимости.

---

## 2. Добавить в NetworkManager (постоянно)

Один раз в терминале — профиль сохранится в  
`/etc/NetworkManager/system-connections/` и переживёт перезагрузку.

```bash
sudo nmcli connection import type wireguard file "$HOME/Downloads/vpn-panov-production.conf"
```

Удобное имя в списке сетей:

```bash
sudo nmcli connection modify peer1 connection.id "VPN panov.id"
```

(Если `nmcli` назвал подключение иначе — подставь имя из `nmcli connection show`.)

Проверка:

```bash
nmcli connection show | grep -i wireguard
```

---

## 3. Включение и выключение без консоли

После импорта **каждый раз** — только GUI:

1. **Верхняя панель** → иконка сети (Wi‑Fi/Ethernet).
2. Раздел **VPN** → выбери **«VPN panov.id»** (или как переименовал).
3. Переключатель **вкл/выкл**.

Альтернатива: **Параметры → Сеть** — то же VPN-подключение.

> **Почему не работает «Параметры → VPN → +»?**  
> В стандартном диалоге GNOME часто нет импорта WireGuard-файла — только OpenVPN. Импорт через **`nmcli`** (шаг 2) как раз и создаёт профиль, который потом виден в меню сети.

---

## 4. Автоподключение при входе в сеанс (по желанию)

```bash
sudo nmcli connection modify "VPN panov.id" connection.autoconnect yes
```

Отключить автоподключение:

```bash
sudo nmcli connection modify "VPN panov.id" connection.autoconnect no
```

---

## 5. Проверка, что туннель поднялся

```bash
nmcli connection show --active
ip a show wg0 2>/dev/null || ip a | grep -A2 wg
```

На сервере (по SSH):

```bash
docker exec wireguard-vpn-production wg show
```

Должен появиться peer с недавним **latest handshake**.

---

## Альтернатива: `wg-quick` и `/etc/wireguard`

Если NetworkManager не нужен — классический «постоянный» вариант:

```bash
sudo cp ~/Downloads/vpn-panov-production.conf /etc/wireguard/wg-panov.conf
sudo chmod 600 /etc/wireguard/wg-panov.conf
sudo systemctl enable --now wg-quick@wg-panov
```

Вкл/выкл тогда через `systemctl` или `sudo wg-quick up/down wg-panov`. В GNOME отдельного переключателя не будет — удобнее вариант с **nmcli** выше.

---

## Отдельное приложение WireGuard (опционально)

Как на Windows — своё окно с большим переключателем:

```bash
sudo apt install flatpak
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
flatpak install flathub com.wireguard.WireGuard
```

Импорт файла `.conf` в приложении → On/Off. Профиль хранит само приложение, не NetworkManager.

---

## Безопасность

- Подключиться могут **только** те, у кого есть файл/QR с **приватным ключом** peer. Знание IP и порта UDP недостаточно.
- **Не коммить** `.conf` в git, не отправлять в мессенджеры.
- Один `peer1` на все устройства — неудобно отзывать доступ; для второго ноутбука лучше **отдельный peer** на сервере (см. [ROADMAP.md](ROADMAP.md)).
- На VPS держи открытыми только нужные **UDP**-порты (51820–51823 и диапазон MR при preview).

---

## Частые проблемы

| Симптом | Что проверить |
|---------|----------------|
| Импорт `nmcli` падает | Целый файл с сервера; `sudo modprobe wireguard` |
| VPN в меню нет | Перелогиниться; `nmcli connection show` |
| Подключилось, нет сети | Строка `DNS` в `.conf`; firewall на VPS (UDP порт стенда) |
| Старый endpoint | После смены `STAND_DNS_ZONE` скачай конфиг заново или перезапусти стенд на VPS |

---

## См. также

| Документ | Содержание |
|----------|------------|
| [user-experience.md](user-experience.md) | Роли, стенды, первый launchpad |
| [stands-on-one-vps.md](stands-on-one-vps.md) | Порты, DNS, firewall |
| [README.md](../README.md) | Обзор репозитория |
