#!/usr/bin/env bash
## Run on the VPS after you cloned this repo (Git is enough to start).
## Interactive server bootstrap (workflow step 3 of 5): deploy directory, Docker, .env,
## optional ufw, optional first `docker compose up`. Prints DEPLOY_DIRECTORY for GitHub.
##
## Typical flow:
##   git clone git@github.com:panov-id/dockerfile-vpn.git
##   cd dockerfile-vpn
##   ./scripts/server-setup-wizard.sh
##
## Language: English by default; Russian help if LANG starts with "ru" or WIZARD_LANGUAGE=ru.
## User guide (Russian): docs/server-wizard-user-guide.ru.md

set -euo pipefail

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd "${script_directory}/.." && pwd)"

# shellcheck source=lib/vps-docker.sh
source "${script_directory}/lib/vps-docker.sh"

wizard_language="${WIZARD_LANGUAGE:-}"
if [[ -z "${wizard_language}" ]] && [[ "${LANG:-}" == ru* ]]; then
  wizard_language="ru"
fi
wizard_language="${wizard_language:-en}"

wizard_stage_total=6
wizard_stage_current=0

print_separator() {
  printf '%s\n' "────────────────────────────────────────"
}

wizard_stage_header() {
  local title_english="$1"
  local title_russian="$2"
  wizard_stage_current=$((wizard_stage_current + 1))
  print_separator
  if [[ "${wizard_language}" == ru ]]; then
    printf '[Визард %s/%s] %s\n' "${wizard_stage_current}" "${wizard_stage_total}" "${title_russian}"
  else
    printf '[Wizard %s/%s] %s\n' "${wizard_stage_current}" "${wizard_stage_total}" "${title_english}"
  fi
}

wizard_print_help() {
  if [[ "${wizard_language}" == ru ]]; then
    printf '  Описание: %s\n' "$1"
    shift
    if [[ $# -gt 0 ]]; then
      printf '  Примеры: %s\n' "$*"
    fi
  else
    printf '  About: %s\n' "$1"
    shift
    if [[ $# -gt 0 ]]; then
      printf '  Examples: %s\n' "$*"
    fi
  fi
}

wizard_print_workflow_overview() {
  print_separator
  if [[ "${wizard_language}" == ru ]]; then
    cat <<'EOF'
Общий процесс в этом репозитории (5 шагов):

  1) Разработка на ноутбуке          — правки, локальный docker compose (опционально)
  2) Git (PR → main)                 — merge сам по себе НЕ деплоит на VPS
  3) Настройка сервера  ← СЕЙЧАС     — этот визард: каталог, Docker, .env, фаервол
  4) Release на GitHub               — тег + опубликовать Release → запуск Actions
  5) Результат на сервере            — checkout тега + docker compose up в DEPLOY_DIRECTORY

Шаги 1–2 ты уже сделал, если код в main. Дальше — подготовка VPS под шаги 4–5.
EOF
  else
    cat <<'EOF'
End-to-end workflow in this repository (5 steps):

  1) Develop locally                 — edit code; optional local docker compose
  2) Git (PR → main)                 — merging to main does NOT deploy to the VPS
  3) Server setup  ← YOU ARE HERE    — this wizard: directory, Docker, .env, firewall
  4) GitHub Release                  — tag + publish Release → Actions deploy job
  5) Result on the server            — checkout tag + docker compose up in DEPLOY_DIRECTORY

You should already have done steps 1–2 before running this on the VPS.
EOF
  fi
  print_separator
}

run_sudo() {
  if [[ "$(id -u)" -eq 0 ]]; then
    "$@"
  else
    sudo "$@"
  fi
}

detect_apt_distro() {
  vps_is_debian_or_ubuntu
}

install_docker_debian() {
  print_separator
  vps_install_docker_via_apt
}

ensure_user_in_docker_group() {
  local unix_user="$1"
  vps_ensure_unix_user_in_docker_group "${unix_user}"
}

apply_env_key_value() {
  local file_path="$1"
  local key="$2"
  local value="$3"
  if [[ ! -f "${file_path}" ]]; then
    echo "Missing ${file_path}" >&2
    return 1
  fi
  if command -v python3 >/dev/null 2>&1; then
    DEPLOY_ENV_FILE="${file_path}" DEPLOY_ENV_KEY="${key}" DEPLOY_ENV_VALUE="${value}" python3 <<'PY'
import os

path = os.environ["DEPLOY_ENV_FILE"]
key = os.environ["DEPLOY_ENV_KEY"]
val = os.environ["DEPLOY_ENV_VALUE"]
with open(path, encoding="utf-8") as handle:
    lines = handle.read().splitlines()
out = []
seen = False
for line in lines:
    if line.startswith(key + "="):
        out.append(key + "=" + val)
        seen = True
    else:
        out.append(line)
if not seen:
    out.append(key + "=" + val)
with open(path, "w", encoding="utf-8") as handle:
    handle.write("\n".join(out) + "\n")
PY
    return
  fi
  echo "python3 not found — set ${key} manually in ${file_path}" >&2
}

prompt_stack_profile() {
  local profile_answer=""
  print_separator
  local layout_script="${repository_root}/scripts/stand-layout.sh"
  if [[ "${wizard_language}" == ru ]]; then
    echo "Профиль стека (production / uat / test / dev / свой)"
  else
    echo "Stack profile (production / uat / test / dev / custom)"
  fi

  if [[ "${wizard_language}" == ru ]]; then
    wizard_print_help \
      "Соответствует стендам на одном VPS — см. docs/stands-on-one-vps.md. Задаёт порт, подсеть и имя compose-проекта." \
      "production → 51820, uat → 51821, test → 51822, dev → 51823" \
      "custom → ввести поля вручную"
    read -r -p "Профиль [production/uat/test/dev/custom] (Enter = production): " profile_answer
  else
    wizard_print_help \
      "Matches stands on one VPS — see docs/stands-on-one-vps.md. Sets port, subnet, and Compose project name." \
      "production → 51820, uat → 51821, test → 51822, dev → 51823" \
      "custom → enter fields manually"
    read -r -p "Profile [production/uat/test/dev/custom] (Enter = production): " profile_answer
  fi

  profile_answer="$(echo "${profile_answer:-production}" | tr '[:upper:]' '[:lower:]')"
  local use_stand_layout_script=true
  case "${profile_answer}" in
    custom|c|own)
      use_stand_layout_script=false
      WIZARD_SUGGESTED_COMPOSE_PROJECT_NAME="vpn-production"
      WIZARD_SUGGESTED_SERVER_PORT="51820"
      WIZARD_SUGGESTED_INTERNAL_SUBNET="10.13.13.0"
      ;;
    dev|development|d)
      profile_answer="dev"
      ;;
    test|t)
      profile_answer="test"
      ;;
    uat|u)
      profile_answer="uat"
      ;;
    production|prod|p)
      profile_answer="production"
      ;;
    *)
      profile_answer="production"
      ;;
  esac

  if [[ "${use_stand_layout_script}" == true ]]; then
    if [[ -f "${layout_script}" ]]; then
      # shellcheck source=/dev/null
      eval "$("${layout_script}" "${profile_answer}")"
      WIZARD_SUGGESTED_COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME}"
      WIZARD_SUGGESTED_SERVER_PORT="${WIREGUARD_SERVER_PORT}"
      WIZARD_SUGGESTED_INTERNAL_SUBNET="${WIREGUARD_INTERNAL_SUBNET}"
    else
      WIZARD_SUGGESTED_COMPOSE_PROJECT_NAME="vpn-production"
      WIZARD_SUGGESTED_SERVER_PORT="51820"
      WIZARD_SUGGESTED_INTERNAL_SUBNET="10.13.13.0"
    fi
  fi
}

resolve_deploy_directory() {
  wizard_stage_header \
    "Deploy directory (DEPLOY_DIRECTORY)" \
    "Каталог деплоя (DEPLOY_DIRECTORY)"

  if [[ "${wizard_language}" == ru ]]; then
    echo "Сюда GitHub Actions зайдёт по SSH: git fetch --tags, checkout тега Release, docker compose up."
    echo "Текущий clone: ${repository_root}"
    wizard_print_help \
      "Один каталог = один стек на VPS. Путь скопируешь в GitHub → Environment → переменная DEPLOY_DIRECTORY." \
      "Y → /home/deploy/dockerfile-vpn (если клонировал сюда)" \
      "n → /srv/vpn/production (отдельный clone под production)"
    read -r -p "Использовать ЭТОТ clone как каталог деплоя? [Y/n]: " use_this
  else
    echo "GitHub Actions will run here: git fetch --tags, checkout Release tag, docker compose up."
    echo "Current clone: ${repository_root}"
    wizard_print_help \
      "One directory = one stack on the VPS. You will paste this path into GitHub Environment variable DEPLOY_DIRECTORY." \
      "Y → /home/deploy/dockerfile-vpn (when you cloned here)" \
      "n → /srv/vpn/production (separate clone for production)"
    read -r -p "Use THIS clone as the deploy directory? [Y/n]: " use_this
  fi

  use_this="${use_this:-Y}"
  if [[ "${use_this}" =~ ^[yY] ]]; then
    deploy_directory="$(cd "${repository_root}" && pwd)"
    echo "Deploy directory: ${deploy_directory}"
    return
  fi

  if [[ "${wizard_language}" == ru ]]; then
    wizard_print_help \
      "URL должен открываться с этого сервера (SSH deploy key или HTTPS с токеном)." \
      "git@github.com:panov-id/dockerfile-vpn.git" \
      "https://github.com/panov-id/dockerfile-vpn.git"
    read -r -p "URL для git clone: " clone_url
    wizard_print_help \
      "Абсолютный путь на диске VPS. Каталог создастся или обновится." \
      "/srv/vpn/production" \
      "/opt/stacks/vpn-uat"
    read -r -p "Абсолютный путь каталога деплоя: " deploy_directory
    wizard_print_help \
      "Ветка для первого clone/pull. Деплой релизов идёт по тегам, не по ветке." \
      "main (обычно)" \
      "develop (редко на сервере)"
    read -r -p "Ветка Git [main]: " git_branch
    git_branch="${git_branch:-main}"
    wizard_print_help \
      "Shallow clone без тегов ломает checkout при Release. Оставь N, если не уверен." \
      "N → полный clone (рекомендуется)" \
      "Y → --depth 1 (только если понимаешь риск)"
    read -r -p "Shallow clone (--depth 1)? [y/N]: " shallow_answer
  else
    wizard_print_help \
      "Clone URL must work from this server (deploy SSH key or HTTPS credentials)." \
      "git@github.com:panov-id/dockerfile-vpn.git" \
      "https://github.com/panov-id/dockerfile-vpn.git"
    read -r -p "Git clone URL: " clone_url
    wizard_print_help \
      "Absolute path on the VPS disk. Directory will be created or updated." \
      "/srv/vpn/production" \
      "/opt/stacks/vpn-uat"
    read -r -p "Absolute deploy directory path: " deploy_directory
    wizard_print_help \
      "Branch for initial clone/pull. Releases deploy by tag, not by branch." \
      "main (typical)" \
      "develop (rare on server)"
    read -r -p "Git branch to track [main]: " git_branch
    git_branch="${git_branch:-main}"
    wizard_print_help \
      "Shallow clones often miss release tags. Choose N unless you know you need shallow." \
      "N → full clone (recommended)" \
      "Y → --depth 1 (only if you accept the risk)"
    read -r -p "Shallow clone (--depth 1)? [y/N]: " shallow_answer
  fi

  if [[ -z "${clone_url}" ]]; then
    echo "Clone URL is required." >&2
    exit 1
  fi
  if [[ -z "${deploy_directory}" ]]; then
    echo "Path is required." >&2
    exit 1
  fi
  deploy_directory="${deploy_directory%/}"
  shallow_clone=false
  if [[ "${shallow_answer:-}" =~ ^[yY] ]]; then
    shallow_clone=true
  fi

  parent_directory="$(dirname "${deploy_directory}")"
  mkdir -p "${parent_directory}"
  if [[ -d "${deploy_directory}/.git" ]]; then
    echo "Already a repo at ${deploy_directory}; pulling ${git_branch} …"
    git -C "${deploy_directory}" fetch origin
    git -C "${deploy_directory}" checkout "${git_branch}"
    git -C "${deploy_directory}" pull --ff-only origin "${git_branch}"
  elif [[ -e "${deploy_directory}" ]]; then
    echo "Path exists but is not a git repo: ${deploy_directory}" >&2
    exit 1
  else
    if [[ "${shallow_clone}" == true ]]; then
      git clone --depth 1 --branch "${git_branch}" "${clone_url}" "${deploy_directory}"
    else
      git clone --branch "${git_branch}" "${clone_url}" "${deploy_directory}"
    fi
  fi
  deploy_directory="$(cd "${deploy_directory}" && pwd)"
  echo "Deploy directory: ${deploy_directory}"
}

ensure_docker_available() {
  wizard_stage_header \
    "Docker Engine + Compose" \
    "Docker Engine + Compose"

  if vps_docker_compose_is_available; then
    if [[ "${wizard_language}" == ru ]]; then
      echo "Docker Compose уже доступен."
    else
      echo "Docker Compose is already available."
    fi
    return
  fi

  if [[ "${wizard_language}" == ru ]]; then
    echo "Docker Compose не найден."
  else
    echo "Docker Compose not found."
  fi

  if detect_apt_distro; then
    if [[ "${wizard_language}" == ru ]]; then
      wizard_print_help \
        "Нужен для шага 5 (compose up) и для GitHub Actions на этом сервере." \
        "Y → apt install docker.io docker-compose-plugin" \
        "n → выход; поставь Docker вручную и запусти визард снова"
      read -r -p "Установить Docker через apt? [Y/n]: " install_answer
    else
      wizard_print_help \
        "Required for step 5 (compose up) and for GitHub Actions deploy on this host." \
        "Y → apt install docker.io docker-compose-plugin" \
        "n → exit; install Docker manually and re-run this wizard"
      read -r -p "Install Docker via apt now? [Y/n]: " install_answer
    fi
    install_answer="${install_answer:-Y}"
    if [[ "${install_answer}" =~ ^[yY] ]]; then
      install_docker_debian
    else
      if [[ "${wizard_language}" == ru ]]; then
        echo "Установи Docker вручную и запусти визард снова." >&2
      else
        echo "Install Docker manually, then re-run this wizard." >&2
      fi
      exit 1
    fi
  else
    if [[ "${wizard_language}" == ru ]]; then
      echo "Автоустановка только для Debian/Ubuntu. Поставь Docker + Compose plugin и запусти визард снова." >&2
    else
      echo "Automatic Docker install is only implemented for Debian/Ubuntu. Install Docker + Compose plugin, then re-run." >&2
    fi
    exit 1
  fi
}

configure_git_safe_directory() {
  local directory_path="$1"
  git config --global --add safe.directory "${directory_path}" 2>/dev/null || true
}

offer_unshallow() {
  local directory_path="$1"
  if [[ "$(git -C "${directory_path}" rev-parse --is-shallow-repository 2>/dev/null)" != "true" ]]; then
    return
  fi
  wizard_stage_header \
    "Git history for release tags" \
    "История Git для тегов релизов"
  if [[ "${wizard_language}" == ru ]]; then
    echo "Clone shallow — для Release нужны теги; лучше подтянуть полную историю."
    wizard_print_help \
      "Без тегов git checkout <release-tag> на шаге 5 не сработает." \
      "Y → git fetch --unshallow" \
      "n → оставить shallow (риск при деплое)"
    read -r -p "Выполнить git fetch --unshallow? [Y/n]: " unshallow_answer
  else
    echo "This clone is shallow. Release deploys need tags; fetching full history is safer."
    wizard_print_help \
      "Without tags, git checkout <release-tag> in step 5 will fail." \
      "Y → git fetch --unshallow" \
      "n → keep shallow (deploy risk)"
    read -r -p "Run: git fetch --unshallow ? [Y/n]: " unshallow_answer
  fi
  unshallow_answer="${unshallow_answer:-Y}"
  if [[ "${unshallow_answer}" =~ ^[yY] ]]; then
    git -C "${directory_path}" fetch --unshallow || git -C "${directory_path}" fetch --depth=2147483647
  fi
}

configure_environment_file() {
  local directory_path="$1"
  local environment_example="${directory_path}/.env.example"
  local environment_target="${directory_path}/.env"
  local public_host=""
  local server_port=""
  local internal_subnet=""
  local compose_project_name=""

  wizard_stage_header \
    "WireGuard / Compose (.env)" \
    "WireGuard / Compose (.env)"

  prompt_stack_profile

  if [[ ! -f "${environment_example}" ]]; then
    echo "Missing .env.example in ${directory_path}" >&2
    exit 1
  fi
  if [[ ! -f "${environment_target}" ]]; then
    cp "${environment_example}" "${environment_target}"
    if [[ "${wizard_language}" == ru ]]; then
      echo "Создан ${environment_target}"
    else
      echo "Created ${environment_target}"
    fi
  else
    if [[ "${wizard_language}" == ru ]]; then
      wizard_print_help \
        "Файл уже есть — можно обновить отдельные ключи, не затирая остальное." \
        "Y → переспросить host/port/subnet/project" \
        "n → оставить .env как есть"
      read -r -p ".env есть — перенастроить поля ниже? [Y/n]: " reconfigure
    else
      wizard_print_help \
        "File already exists — update selected keys without wiping the whole file." \
        "Y → re-ask host/port/subnet/project" \
        "n → leave .env unchanged"
      read -r -p ".env exists — reconfigure keys below? [Y/n]: " reconfigure
    fi
    reconfigure="${reconfigure:-Y}"
    if [[ ! "${reconfigure}" =~ ^[yY] ]]; then
      if [[ "${wizard_language}" == ru ]]; then
        echo ".env не изменён."
      else
        echo "Leaving .env unchanged."
      fi
      return
    fi
  fi

  print_separator
  if [[ "${wizard_language}" == ru ]]; then
    echo "Параметры для клиентов WireGuard и изоляции стека на VPS."
  else
    echo "Settings for WireGuard clients and stack isolation on this VPS."
  fi

  if [[ "${wizard_language}" == ru ]]; then
    wizard_print_help \
      "Публичный IP или DNS VPS — попадает в конфиги пиров. Должен совпадать с тем, куда клиент стучится по UDP." \
      "vpn.example.com" \
      "203.0.113.10" \
      "wg.my-vps.example.net"
    read -r -p "WIREGUARD_SERVER_PUBLIC_HOST: " public_host
    wizard_print_help \
      "UDP-порт на хосте. Уникальный для каждого стека на одном VPS. Открой в панели провайдера и в ufw." \
      "51820 (production)" \
      "51821 (uat на том же сервере)" \
      "51830 (если 51820 занят)"
    read -r -p "WIREGUARD_SERVER_PORT [${WIZARD_SUGGESTED_SERVER_PORT}]: " server_port
    server_port="${server_port:-${WIZARD_SUGGESTED_SERVER_PORT}}"
    wizard_print_help \
      "Подсеть туннеля linuxserver/wireguard. Разная для production и uat на одном хосте." \
      "10.13.13.0" \
      "10.13.14.0 (второй стек)" \
      "10.8.0.0"
    read -r -p "WIREGUARD_INTERNAL_SUBNET [${WIZARD_SUGGESTED_INTERNAL_SUBNET}]: " internal_subnet
    internal_subnet="${internal_subnet:-${WIZARD_SUGGESTED_INTERNAL_SUBNET}}"
    wizard_print_help \
      "Имя проекта docker compose (-p). Разделяет контейнеры и сети на одном сервере." \
      "vpn-production" \
      "vpn-uat" \
      "vpn-test-51822"
    read -r -p "COMPOSE_PROJECT_NAME [${WIZARD_SUGGESTED_COMPOSE_PROJECT_NAME}]: " compose_project_name
    compose_project_name="${compose_project_name:-${WIZARD_SUGGESTED_COMPOSE_PROJECT_NAME}}"
  else
    wizard_print_help \
      "Public VPS IP or DNS — written into peer configs. Must match where clients send UDP traffic." \
      "vpn.example.com" \
      "203.0.113.10" \
      "wg.my-vps.example.net"
    read -r -p "WIREGUARD_SERVER_PUBLIC_HOST: " public_host
    wizard_print_help \
      "Host UDP port. Must be unique per stack on one VPS. Open in cloud firewall and ufw." \
      "51820 (production)" \
      "51821 (uat on same host)" \
      "51830 (if 51820 is taken)"
    read -r -p "WIREGUARD_SERVER_PORT [${WIZARD_SUGGESTED_SERVER_PORT}]: " server_port
    server_port="${server_port:-${WIZARD_SUGGESTED_SERVER_PORT}}"
    wizard_print_help \
      "Tunnel subnet for linuxserver/wireguard. Use a different /24 per stack on one host." \
      "10.13.13.0" \
      "10.13.14.0 (second stack)" \
      "10.8.0.0"
    read -r -p "WIREGUARD_INTERNAL_SUBNET [${WIZARD_SUGGESTED_INTERNAL_SUBNET}]: " internal_subnet
    internal_subnet="${internal_subnet:-${WIZARD_SUGGESTED_INTERNAL_SUBNET}}"
    wizard_print_help \
      "docker compose project name (-p). Isolates containers and networks on one server." \
      "vpn-production" \
      "vpn-uat" \
      "vpn-test-51822"
    read -r -p "COMPOSE_PROJECT_NAME [${WIZARD_SUGGESTED_COMPOSE_PROJECT_NAME}]: " compose_project_name
    compose_project_name="${compose_project_name:-${WIZARD_SUGGESTED_COMPOSE_PROJECT_NAME}}"
  fi

  if [[ -z "${public_host}" ]]; then
    if [[ "${wizard_language}" == ru ]]; then
      echo "Внимание: WIREGUARD_SERVER_PUBLIC_HOST пустой — клиенты не смогут подключиться, пока не задашь хост в .env." >&2
    else
      echo "Warning: WIREGUARD_SERVER_PUBLIC_HOST is empty — clients cannot connect until you set it in .env." >&2
    fi
  else
    apply_env_key_value "${environment_target}" "WIREGUARD_SERVER_PUBLIC_HOST" "${public_host}"
  fi
  apply_env_key_value "${environment_target}" "WIREGUARD_SERVER_PORT" "${server_port}"
  apply_env_key_value "${environment_target}" "WIREGUARD_INTERNAL_SUBNET" "${internal_subnet}"
  apply_env_key_value "${environment_target}" "COMPOSE_PROJECT_NAME" "${compose_project_name}"
}

maybe_open_ufw() {
  local directory_path="$1"
  if ! command -v ufw >/dev/null 2>&1; then
    return
  fi

  wizard_stage_header \
    "Host firewall (ufw)" \
    "Фаервол хоста (ufw)"

  local port_line
  port_line="$(grep -E '^WIREGUARD_SERVER_PORT=' "${directory_path}/.env" | tail -n1 || true)"
  local port_value="${port_line#WIREGUARD_SERVER_PORT=}"
  port_value="${port_value//\"/}"
  port_value="${port_value//\'/}"
  port_value="${port_value:-51820}"

  if [[ "${wizard_language}" == ru ]]; then
    wizard_print_help \
      "Правило только на хосте. Порт в панели VPS (Hetzner, DO, …) всё равно открой отдельно." \
      "y → ufw allow ${port_value}/udp" \
      "n → настроишь ufw или cloud firewall вручную"
    read -r -p "Открыть UDP ${port_value} в ufw? [y/N]: " ufw_answer
  else
    wizard_print_help \
      "Rule on the host only. You still must open the port in the VPS provider panel (Hetzner, DO, …)." \
      "y → ufw allow ${port_value}/udp" \
      "n → configure ufw or cloud firewall yourself"
    read -r -p "Open UDP ${port_value} in ufw? [y/N]: " ufw_answer
  fi
  if [[ "${ufw_answer:-}" =~ ^[yY] ]]; then
    run_sudo ufw allow "${port_value}/udp"
    if [[ "${wizard_language}" == ru ]]; then
      echo "Если ufw был выключен: sudo ufw enable (когда будешь готов)."
    else
      echo "If ufw was inactive: sudo ufw enable (when you are ready)."
    fi
  fi
}

compose_up_now() {
  local directory_path="$1"
  wizard_stage_header \
    "First stack start (optional)" \
    "Первый запуск стека (опционально)"

  if [[ "${wizard_language}" == ru ]]; then
    wizard_print_help \
      "Проверка до первого Release. После настройки GitHub деплой всё равно пойдёт через Release (шаг 4)." \
      "y → docker compose up -d (скачает образ wireguard)" \
      "n → поднимешь позже вручную или дождёшься Release"
    read -r -p "Запустить docker compose up -d сейчас? [y/N]: " up_answer
  else
    wizard_print_help \
      "Smoke test before your first Release. Routine deploys still come from GitHub Release (step 4)." \
      "y → docker compose up -d (pulls wireguard image)" \
      "n → start later manually or wait for Release"
    read -r -p "Run 'docker compose up -d' now? [y/N]: " up_answer
  fi
  if [[ ! "${up_answer:-}" =~ ^[yY] ]]; then
    return
  fi
  (
    cd "${directory_path}"
    if [[ "$(id -u)" -eq 0 ]]; then
      docker compose up -d
    elif docker compose version >/dev/null 2>&1 && docker compose ps >/dev/null 2>&1; then
      docker compose up -d
    else
      if [[ "${wizard_language}" == ru ]]; then
        echo "Пробуем sudo docker compose (нет доступа к docker socket) …"
      else
        echo "Trying sudo docker compose (your user may lack docker socket access) …"
      fi
      run_sudo docker compose up -d
    fi
  )
}

prompt_docker_group() {
  local unix_login="${SUDO_USER:-${USER:-}}"
  if [[ -z "${unix_login}" ]] || [[ "$(id -u)" -eq 0 ]]; then
    return
  fi
  wizard_stage_header \
    "Docker group for your user" \
    "Группа docker для пользователя"
  if [[ "${wizard_language}" == ru ]]; then
    wizard_print_help \
      "Чтобы docker compose без sudo работал от твоего SSH-пользователя (и от deploy user в Actions)." \
      "Y → usermod -aG docker ${unix_login}" \
      "n → compose up может использовать sudo"
    read -r -p "Добавить '${unix_login}' в группу docker? [Y/n]: " group_answer
  else
    wizard_print_help \
      "So docker compose works without sudo for your SSH user (and the Actions deploy user)." \
      "Y → usermod -aG docker ${unix_login}" \
      "n → compose up may use sudo instead"
    read -r -p "Add '${unix_login}' to group docker? [Y/n]: " group_answer
  fi
  group_answer="${group_answer:-Y}"
  if [[ "${group_answer}" =~ ^[yY] ]]; then
    ensure_user_in_docker_group "${unix_login}"
  fi
}

print_finish_summary() {
  local deploy_directory="$1"
  print_separator
  if [[ "${wizard_language}" == ru ]]; then
    cat <<EOF
=== Готово (шаг 3 из 5) ===

GitHub → Environment → переменная DEPLOY_DIRECTORY (скопируй путь):

  ${deploy_directory}

Секреты окружения: SSH_HOST, SSH_USER, SSH_PRIVATE_KEY
(пользователь SSH должен владеть этим clone и запускать docker).

Дальше (шаги 4–5):
  4) На GitHub: тег на main (например v1.0.1) → Releases → Publish
     • pre-release → окружение uat
     • stable release → production
  5) На сервере: после workflow — cd ${deploy_directory}
     docker compose ps
     docker compose logs -f wireguard

Повседневный цикл: локально → PR → main → Release → результат на VPS.
EOF
  else
    cat <<EOF
=== Done (workflow step 3 of 5) ===

GitHub → Environment → variable DEPLOY_DIRECTORY (copy exactly):

  ${deploy_directory}

Environment secrets: SSH_HOST, SSH_USER, SSH_PRIVATE_KEY
(SSH user must own this clone and run docker).

Next (steps 4–5):
  4) On GitHub: tag on main (e.g. v1.0.1) → Releases → Publish
     • pre-release → uat environment
     • stable release → production
  5) On the server: after the workflow — cd ${deploy_directory}
     docker compose ps
     docker compose logs -f wireguard

Day-to-day: local dev → PR → main → Release → result on VPS.
EOF
  fi
}

main() {
  echo ""
  if [[ "${wizard_language}" == ru ]]; then
    echo "=== dockerfile-vpn — визард настройки сервера (шаг 3/5) ==="
  else
    echo "=== dockerfile-vpn — server setup wizard (step 3/5) ==="
  fi
  echo ""

  wizard_print_workflow_overview

  local deploy_directory=""
  resolve_deploy_directory
  deploy_directory="$(cd "${deploy_directory}" && pwd)"

  if [[ ! -f "${deploy_directory}/docker-compose.yml" ]]; then
    echo "No docker-compose.yml in ${deploy_directory}" >&2
    exit 1
  fi

  ensure_docker_available
  prompt_docker_group
  configure_git_safe_directory "${deploy_directory}"
  offer_unshallow "${deploy_directory}"
  configure_environment_file "${deploy_directory}"
  maybe_open_ufw "${deploy_directory}"
  compose_up_now "${deploy_directory}"
  print_finish_summary "${deploy_directory}"
}

main "$@"
