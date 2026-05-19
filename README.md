# Docker-based VPN on a VPS

This repository will hold **containerized VPN infrastructure** (a `Dockerfile`, `docker-compose.yml`, or both) that you run on **your own VPS**. The goal is a reproducible setup: define the service once, deploy updates safely, and keep secrets out of the Git history.

## Goals

- Run a VPN server on a VPS using **Docker** or **Docker Compose**.
- Automate delivery from **GitHub Actions**: deploy to the server **only when a GitHub Release is published** (`release`, type `published`). Ordinary merges to `main` do not deploy by themselves.
- Document ports, firewall expectations, and backup/rekey procedures.

## Quick start (first time on this project)

**Host:** Docker only. **Secrets:** one file `.env.platform` (gitignored).

```bash
cp .env.platform.example .env.platform
# Edit: SSH_HOST, SSH_USER, LAUNCHPAD_SSH_PRIVATE_KEY_HOST_PATH, GITHUB_TOKEN, STAND_DNS_ZONE
./scripts/verify-deploy-ssh-key.sh   # optional; launchpad-run.sh runs this too
./scripts/launchpad-run.sh
```

**SSH key:** dedicated deploy key, **no passphrase** — [docs/deploy-ssh-key.md](docs/deploy-ssh-key.md).  
Then manually: **DNS** `*.your-zone` → VPS IP, **UDP ports** in cloud firewall — [stands-on-one-vps.md](docs/stands-on-one-vps.md).

| More docs | |
|-----------|--|
| All documentation | [docs/README.md](docs/README.md) |
| Deploy SSH key (no passphrase) | [docs/deploy-ssh-key.md](docs/deploy-ssh-key.md) |
| Launchpad | [docs/launchpad.md](docs/launchpad.md) |
| User journeys (RU) | [docs/user-experience.md](docs/user-experience.md) |
| Contributing | [CONTRIBUTING.md](CONTRIBUTING.md) |

## Your workflow in five steps

This repository assumes you move like this:

| Step | Where | What you do |
|------|-------|-------------|
| **1 — Develop locally** | Your laptop | Edit the repo; optionally run the stack with **`docker-compose.local.yml`** and **`./scripts/local-compose-up.sh`** / **`local-smoke-check.sh`** (nothing hits the VPS yet). |
| **2 — Put it in Git** | GitHub | Feature work: **PR into `dev`** (MR preview stand deploys automatically). Production path: merge to **`main`** later. **Merge to `main` alone does not deploy.** |
| **3 — Set up platform** | Laptop + VPS | **Once:** `./scripts/launchpad-run.sh` with **`.env.platform`** — GitHub environments/secrets, **`dev`**/**`test`** branches, VPS stands (`dev`, `test`, `uat`, `production`). Then DNS + UDP firewall. Alternative on VPS only: [`server-setup-wizard.sh`](scripts/server-setup-wizard.sh) — [guide (RU)](docs/server-wizard-user-guide.ru.md). |
| **4 — Publish a Release** | GitHub | Create a **tag** on **`main`** (e.g. **`v1.1.0`**), open **Releases**, **publish** a Release for that tag ([docs](https://docs.github.com/en/repositories/releasing-projects-on-github/managing-releases-in-a-repository)). **Pre-release** → **`uat`** environment; stable → **`production`** ([`deploy-release.yml`](.github/workflows/deploy-release.yml)). |
| **5 — See the result on the server** | VPS | The workflow SSHs to **`DEPLOY_DIRECTORY`**, **`git fetch --tags`**, **`git checkout`** the release tag, **`docker compose up -d --pull always`**. Check with **`docker compose ps`** / **`docker compose logs -f wireguard`**. |

**After step 3:** feature cycle is **1 → PR to `dev` → MR preview → merge → dev stand**; production is **merge `dev`→`main` → Release (steps 4–5)**. Repeat step **3** only for a new VPS or broken GitHub/VPS wiring.

### Dev, test, and MR preview (same VPS for now)

| Stand | When it updates | What gets deployed |
|-------|-----------------|-------------------|
| **`dev`** | Push to branch **`dev`** | Branch `dev` at `${STANDS_ROOT}/dev` |
| **`test`** | Push to branch **`test`** | Branch `test` at `${STANDS_ROOT}/test` |
| **`mr-<PR#>`** | Pull request **into `dev`** (open/sync) | Git ref **`pull/<PR>/merge`** — preview of merging into `dev` **before** you click Merge |
| **production / uat** | Published **Release** | Release tag (unchanged) |

Each stand uses its own **UDP port**, **tunnel subnet**, **Compose project name**, and **DNS name** when **`STAND_DNS_ZONE`** is set (e.g. MR **#42** → `mr-42.vpn.example.com`). Full setup: **[docs/stands-on-one-vps.md](docs/stands-on-one-vps.md)**.

Typical feature flow: branch from **`dev`** → PR to **`dev`** → MR preview stand for manual check → merge → **`dev`** stand updates → later **`main`** + Release for production.

Process detail for contributors: **[docs/github-workflow.md](docs/github-workflow.md)**. **User experience (journeys, what you see):** **[docs/user-experience.md](docs/user-experience.md)**.

## Developer workflow (GitHub)

How **branches, pull requests, CI, tags, Releases, and deployment** fit together — read **[docs/github-workflow.md](docs/github-workflow.md)** first. The short **[CONTRIBUTING.md](CONTRIBUTING.md)** points to the same doc.

## Non-goals (for now)

- Providing a public VPN exit for strangers (this is a **personal or small-team** setup unless you explicitly widen scope).
- Bundling a full observability stack unless we add it in a later phase (see [Roadmap](docs/ROADMAP.md)).

## Prerequisites (high level)

- A VPS with a public IP and **UDP** (and optionally **TCP**) ports opened in the provider firewall and OS firewall.
- **Docker Engine + Compose plugin** on the VPS — on Debian/Ubuntu usually installed by **`scripts/vps-bootstrap.sh`**; on other systems install manually.
- A **GitHub** repository with **Actions** enabled. Use **GitHub-hosted runners** (SSH deploy to your VPS over the public internet) or a **self-hosted runner** on the VPS if you prefer jobs to run locally without inbound SSH from GitHub’s cloud.

## Getting started (checklist)

### A. Automated platform setup (recommended)

See **[Quick start](#quick-start-first-time-on-this-project)** and **[docs/launchpad.md](docs/launchpad.md)**.

Launchpad configures GitHub (`production`, `uat`, `dev`, `test`, `mr-preview`) and bootstraps VPS stands under **`STANDS_ROOT`** (default `/srv/vpn`).

### B. Manual steps only you can do (outside scripts)

| # | Task | Where |
|---|------|--------|
| 1 | **DNS:** `*.vpn.example.com` and apex → VPS IP | Domain registrar / Cloudflare |
| 2 | **Firewall:** UDP 51820–51823, 51900+ for MR | Cloud provider (+ `ufw` on VPS if used) |
| 3 | **SSH:** deploy key **without passphrase** on VPS | [deploy-ssh-key.md](docs/deploy-ssh-key.md), `LAUNCHPAD_SSH_PRIVATE_KEY_HOST_PATH` |
| 4 | **GitHub PAT** with repo + Actions secrets | `GITHUB_TOKEN` in `.env.platform` |
| 5 | Enable **Actions**, protect **`main`** (and optionally **`dev`**) | GitHub Settings |

### C. Alternative: VPS-only wizard (no launchpad)

If the VPS already has Git and you prefer an interactive session on the server:

```bash
git clone git@github.com:panov-id/dockerfile-vpn.git
cd dockerfile-vpn
./scripts/server-setup-wizard.sh
```

Guide: [`docs/server-wizard-user-guide.ru.md`](docs/server-wizard-user-guide.ru.md). Non-interactive: **`scripts/vps-bootstrap.sh`**.

### D. Routine work after setup

**Features:** `feature/*` → **PR to `dev`** → test on **`mr-N.your-zone`** → merge → **`dev`** stand updates.

**Production:** merge **`dev` → `main`** → tag → **publish Release** (pre-release → uat, stable → production).

## Versioning and releases

- **Changelog:** [`CHANGELOG.md`](CHANGELOG.md) — what shipped in each version ([Keep a Changelog](https://keepachangelog.com/)).
- **Tags:** [Semantic versioning](https://semver.org/) (`v1.0.0`, `v1.1.0`, …). The deploy workflow checks out the **tag** named on the GitHub Release.
- **Cutting a release:** tag the intended commit on `main`, then [create a GitHub Release](https://docs.github.com/en/repositories/releasing-projects-on-github/managing-releases-in-a-repository) from that tag and **publish** it — that triggers **`deploy-release.yml`**. Use a **pre-release** for **`uat`** and a stable Release for **`production`** (see workflow).
- **Stands (1.1.0):** see **[docs/stands-on-one-vps.md](docs/stands-on-one-vps.md)** — set **`STAND_DNS_ZONE`**, create GitHub Environments **`dev`**, **`test`**, **`mr-preview`**, branches **`dev`** and **`test`**.
- **Patch/minor/major:** increment **PATCH** for fixes, **MINOR** for backward-compatible additions, **MAJOR** for breaking operational or compatibility changes you want callers to notice.

## Process overview (how everything connects)

| Stage | Where | What happens |
|-------|--------|----------------|
| **Local dev** | Your laptop | **`docker-compose.yml` + `docker-compose.local.yml`** and **`.env.local`**: WireGuard in Docker with state under **`./config.local/`**. Scripts: **`local-compose-*`**, **`local-smoke-check.sh`**, **`local-two-stacks-test.sh`**. No impact on production files. |
| **Compose CI** | GitHub Actions | **`compose-validate.yml`** runs **`docker compose config`** for production and local env templates on PRs. |
| **Wizard Docker test** | GitHub Actions / local | **`wizard-docker-test.yml`** on PRs (when wizard/test paths change): builds **`docker/Dockerfile.wizard-test`**, runs **`scripts/test-wizard-docker.sh`** with **`WIZARD_TEST_SKIP_COMPOSE_UP=true`**. Locally the same **`docker/docker-compose.wizard-test.yml`** — full wizard output in your terminal; use **`WIZARD_TEST_SKIP_COMPOSE_UP=true`** below to skip **`compose up`**. |
| **Platform setup** | Laptop | **`./scripts/launchpad-run.sh`** — GitHub + VPS stands from **`.env.platform`** |
| **MR / dev / test deploy** | GitHub → VPS | **`deploy-mr-preview`**, **`deploy-dev-stand`**, **`deploy-test-stand`** |
| **First VPS (manual)** | Server | **`server-setup-wizard.sh`** or **`vps-bootstrap.sh`** if not using launchpad |
| **Runtime deploy** | GitHub → VPS | **`deploy-release.yml`** on **`release` published**: SSH into **`DEPLOY_DIRECTORY`**, **`git fetch --tags`**, **`git checkout`** release tag, **`docker compose up -d --pull always`**. **Pre-release** uses GitHub Environment **`uat`**, stable release uses **`production`** (different secrets / **`DEPLOY_DIRECTORY`** per env). |

### Integration test: server wizard inside Docker

This runs **`server-setup-wizard.sh`** with **scripted stdin** inside a **Debian** container that has the **Docker CLI** and mounts **`/var/run/docker.sock`** from the host so **`docker compose`** talks to your real daemon (stdout/stderr are visible in the terminal). The image installs **`docker.io`** from Debian and the **`docker compose` v2 CLI plugin** from the [Compose releases](https://github.com/docker/compose/releases) (Debian Bookworm does not ship **`docker-compose-plugin`** in its default apt repositories).

From the **repository root** on a machine with Docker:

```bash
docker compose -f docker/docker-compose.wizard-test.yml build wizard-test
docker compose -f docker/docker-compose.wizard-test.yml run --rm wizard-test
```

By default this runs **`scripts/test-wizard-docker.sh`**, which answers prompts automatically and ends with **`docker compose up`** (pulls **linuxserver/wireguard**).

Faster smoke (wizard only, **no** compose up):

```bash
WIZARD_TEST_SKIP_COMPOSE_UP=true docker compose -f docker/docker-compose.wizard-test.yml run --rm wizard-test
```

Optional:

```bash
WIZARD_TEST_PUBLIC_HOST=198.51.100.10 docker compose -f docker/docker-compose.wizard-test.yml run --rm wizard-test
```

**Note:** the wizard writes **`.env`** into the **mounted repo directory** (ignored by git). Remove it after a local test if needed: **`rm -f .env`** (only if you do not rely on that file).

The same fast path runs in CI via **`.github/workflows/wizard-docker-test.yml`** (`WIZARD_TEST_SKIP_COMPOSE_UP=true`).

### Laptop helper menu (`interactive-setup.sh`)

After cloning/updating the repo on your **development machine** (this is **not** the VPS server wizard):

```bash
./scripts/interactive-setup.sh
```

Menu item **8** runs **`launchpad-run.sh`** (same as recommended setup). Other items: local Compose smoke, checklists, optional legacy **`gh`** upload if installed on host.

For **server-only** setup: **`./scripts/server-setup-wizard.sh`** — **[guide (RU)](docs/server-wizard-user-guide.ru.md)**.

**Note:** CI/CD in this repository is **GitHub Actions**. A GitLab mirror would need a separate `.gitlab-ci.yml` if you move hosting later.

## Local environment (test on your laptop)

**What fits:** the same **Docker Compose + linuxserver/wireguard** stack merged with **`docker-compose.local.yml`**. Persisted keys and peers live under **`LOCAL_WIREGUARD_CONFIG_DIRECTORY`** on the host (defaults to **`./config.local/`**), never mixed with VPS **`./config/`**.

1. Copy **`.env.local.example` → `.env.local`** (gitignored).
2. Adjust **`WIREGUARD_SERVER_PUBLIC_HOST`**: use **`127.0.0.1`** only if the WireGuard client runs **on this machine**; for a phone or another PC on the LAN, use your laptop’s **LAN IP**.
3. Ensure **`WIREGUARD_SERVER_PORT`** (default `51830` in the example) is free.

```bash
./scripts/local-compose-up.sh
./scripts/local-compose-logs.sh    # optional; Ctrl+C to stop tailing
./scripts/local-compose-down.sh
```

### Automated smoke check (one stack)

After **`./scripts/local-compose-up.sh`** (or let the script start the stack for you):

```bash
./scripts/local-smoke-check.sh
# Second env file:
LOCAL_ENVIRONMENT_FILE="$(pwd)/.env.local.stack-b" ./scripts/local-smoke-check.sh
```

This verifies **`docker compose ps`**, **`wg show`** (listening port present, retries up to ~60s), and **`wg_confs/wg0.conf`** under your **`LOCAL_WIREGUARD_CONFIG_DIRECTORY`**.

### Two parallel stacks on one machine (dev rehearsal)

Models two VPS instances from one clone: different **`COMPOSE_PROJECT_NAME`**, **UDP port**, **tunnel subnet**, and **config directory**.

```bash
cp .env.local.example .env.local
cp .env.local.stack-b.example .env.local.stack-b
./scripts/local-two-stacks-test.sh           # tears down both stacks when finished
./scripts/local-two-stacks-test.sh --keep-running   # leaves them up for manual client tests
```

Override env files when needed: **`LOCAL_ENVIRONMENT_FILE`** for `./scripts/local-compose-*.sh` and **`PRIMARY_LOCAL_ENVIRONMENT_FILE` / `SECONDARY_LOCAL_ENVIRONMENT_FILE`** for **`local-two-stacks-test.sh`**.

**Requirements:** Linux (or any host where Docker can grant **`NET_ADMIN`** to the container). **WireGuard kernel module** may need to be loaded on the host for linuxserver’s image to behave well—if the container fails to bring up `wg0`, check image logs and host `modprobe wireguard`.

## What this repository automates vs what only you can do

**Inside Git (done here):**

- `docker-compose.yml` running **[linuxserver/wireguard](https://docs.linuxserver.io/images/docker-wireguard/)** with values driven by `.env`.
- **`.github/workflows/compose-validate.yml`** — on PRs touching Compose files, validates **`docker-compose.yml`** with `.env.example` and local merges using **`.env.local.example`** and **`.env.local.stack-b.example`**.
- **`.github/workflows/wizard-docker-test.yml`** — builds **`docker/Dockerfile.wizard-test`** and runs **`server-setup-wizard.sh`** with scripted stdin ( **`WIZARD_TEST_SKIP_COMPOSE_UP=true`** for speed).
- **`.github/workflows/stand-layout-validate.yml`** — asserts port/subnet/DNS layout from **`scripts/stand-layout.sh`**.
- **`.github/workflows/deploy-dev-stand.yml`** / **`deploy-test-stand.yml`** — push to **`dev`** / **`test`** updates persistent stands on the VPS.
- **`.github/workflows/deploy-mr-preview.yml`** / **`teardown-mr-preview.yml`** — PR into **`dev`** deploys **`pull/N/merge`** to **`mr-N`** stand (e.g. **`mr-42.vpn.example.com`**); teardown on PR close.
- **`.github/workflows/deploy-release.yml`** — on **`release` published**, SSH to the VPS: **`git fetch --tags`**, **`git checkout`** release tag inside **`DEPLOY_DIRECTORY`**, **`docker compose up -d --pull always`** (server holds a full **git clone**).

**Only you (or your cloud/GitHub account) can do:**

- Create the VPS, **DNS** records, **UDP** firewall rules, backups.
- Fill **`.env.platform`** (secrets) and run **launchpad** once — or configure GitHub/VPS manually.
- **Branch protection** and PAT/token scopes in GitHub.

No assistant can safely “click through” your VPS provider or GitHub on your behalf without your credentials.

## VPN stack

### Current decision

- **Protocol:** **WireGuard** in Docker Compose on the VPS.
- **Operations:** **File-based configuration** under `./config` on the server (generated/managed by the linuxserver WireGuard image from `.env`). **No** separate administration web UI (for example no wg-easy) unless requirements change later.

### Alternatives (if requirements change)

| Approach | Pros | Cons |
|----------|------|------|
| **WireGuard** | Fast, simple protocol, excellent on Linux, easy in Docker | Clients must support WireGuard (widely available today) |
| **OpenVPN** | Very wide legacy client support | Heavier, more moving parts, often slower than WireGuard |
| **Headscale** (self-hosted Tailscale control plane) | Great for device mesh, SSO integrations possible | Different mental model than “classic” VPN server |

OpenVPN or Headscale remain options if client support or mesh topology becomes a priority.

## Git workflow and deploy trigger

Contributor-oriented overview: **[docs/github-workflow.md](docs/github-workflow.md)**. The sections below add detail (multi-tier VPS, tables).

### Branching

| Branch | Role |
|--------|------|
| **`dev`** | Feature integration; **PRs target here**; push updates **dev** stand |
| **`test`** | Optional line; push updates **test** stand |
| **`main`** | Production-ready; deploy only via **Release** |

Protect **`main`** and **`dev`** with required PRs where possible.

### When production deploys

- **Deploy trigger:** workflow runs on **`release` → `published`** (a GitHub Release was published—not only a tag pushed).
- **Recommendation:** create the release **from a tag** on `main` (for example `v1.2.0`) so the deployed revision is clearly named and listed on the Releases page.

### Implementation status (repository)

1. **Compose assets:** `docker-compose.yml` + `.env.example` — **in repo** (adjust values per environment).
2. **VPS layout:** directories, UDP ports, subnets — **you** (see tables below).
3. **GitHub Actions:** `deploy-release.yml` + `compose-validate.yml` — **in repo**; wire **secrets** / **`DEPLOY_DIRECTORY`** per environment in GitHub.
4. **Secrets outside Git:** `.env` on the VPS and SSH keys in GitHub — **you**.
5. **Branch protection on `main`:** **you** in GitHub repository settings.

### Dev / test / UAT on the **same** VPS

Treat **dev**, **test**, **UAT**, and **production** as separate concerns: **isolation on the VPS is the same** (unique UDP port, subnet, directory, Compose project name); **what differs is how often things change and how you trigger a deploy**.

#### What each tier is usually for

| Tier | Purpose | Often lives… |
|------|---------|----------------|
| **Development** | Quick experiments, breaking changes OK | **Your laptop** (`docker compose`) or a **throwaway stack** on the VPS |
| **Test** | Automated checks and/or a disposable stack used by CI or developers | **GitHub Actions only** (validate compose, smoke scripts) **and/or** a small VPS stack |
| **UAT** | “Like prod,” validation by you or stakeholders before a stable release | Same VPS as prod, separate WireGuard port/subnet |
| **Production** | What you rely on day to day | Same VPS, dedicated port/subnet |

#### Technical isolation (same server, multiple stacks)

| Concern | Typical approach |
|--------|-------------------|
| **WireGuard UDP port** | **One unique host port per tier** (example: production `51820`, UAT `51821`, test `51822`, dev `51823`). Open every port you use in the VPS firewall and provider security group. |
| **VPN IP range** | **Distinct tunnel subnets** per tier (example: production `10.8.0.0/24`, UAT `10.9.0.0/24`, test `10.10.0.0/24`, dev `10.11.0.0/24`). |
| **Files and keys** | Separate directories (example: `…/production`, `…/uat`, `…/test`, `…/development`), each with its own `.env` and WireGuard material **outside Git**. |
| **Compose isolation** | `docker compose -p vpn-production`, `-p vpn-uat`, `-p vpn-test`, `-p vpn-development` (or separate compose files). |

#### How deploy triggers differ by tier

| Tier | Trigger | Workflow |
|------|---------|----------|
| **MR preview** | PR opened/updated **into `dev`** | `deploy-mr-preview.yml` |
| **dev** | Push to **`dev`** | `deploy-dev-stand.yml` |
| **test** | Push to **`test`** | `deploy-test-stand.yml` |
| **uat** | Release **pre-release** | `deploy-release.yml` |
| **production** | Stable **Release** | `deploy-release.yml` |

Full reference: **[docs/stands-on-one-vps.md](docs/stands-on-one-vps.md)** and **[docs/github-workflow.md](docs/github-workflow.md)**.

## Roadmap

See **[docs/ROADMAP.md](docs/ROADMAP.md)** for the phased implementation plan (baseline VPN, hardening, GitHub Actions deploy, operations).

## Repository layout

```
./
├── README.md
├── CONTRIBUTING.md            # link to docs/github-workflow.md
├── docker-compose.yml
├── docker-compose.local.yml   # local overrides (LOCAL_WIREGUARD_CONFIG_DIRECTORY)
├── .env.example
├── .env.local.example
├── .env.local.stack-b.example
├── .env.platform.example      # template for launchpad (copy → .env.platform)
├── .gitignore
├── docker/
│   ├── Dockerfile.wizard-test
│   ├── Dockerfile.launchpad
│   ├── docker-compose.wizard-test.yml
│   └── docker-compose.launchpad.yml
├── docs/
│   ├── README.md              # documentation index
│   ├── launchpad.md
│   ├── user-experience.md     # UX journeys (Russian)
│   ├── github-workflow.md
│   ├── stands-on-one-vps.md
│   ├── server-wizard-user-guide.ru.md
│   └── ROADMAP.md
├── scripts/
│   ├── launchpad-run.sh       # setup via container (no gh on host)
│   ├── setup-platform.sh      # same logic, run inside launchpad or on host
│   ├── platform-aliases.sh    # optional: vpn-setup → launchpad-run
│   ├── stand-layout.sh
│   ├── stand-resolve-public-host.sh
│   ├── remote/
│   │   ├── vps-deploy-stand.sh
│   │   └── vps-teardown-stand.sh
│   ├── compose-config-check.sh
│   ├── local-compose-*.sh
│   ├── local-smoke-check.sh
│   ├── local-two-stacks-test.sh
│   ├── interactive-setup.sh
│   ├── vps-bootstrap.sh
│   ├── server-setup-wizard.sh
│   ├── deploy-from-runner-over-ssh.sh
│   └── test-wizard-docker.sh
└── .github/workflows/
    ├── compose-validate.yml
    ├── stand-layout-validate.yml
    ├── wizard-docker-test.yml
    ├── deploy-dev-stand.yml
    ├── deploy-test-stand.yml
    ├── deploy-mr-preview.yml
    ├── teardown-mr-preview.yml
    └── deploy-release.yml
```

## Security reminders

- Do **not** commit real private keys, `.env` with secrets, or client configs containing secrets.
- Prefer **branch protection**, **required reviews**, and **deployment environment gates** (especially for production) until the workflow is trusted. Deploy runs on **`release` published**, not on every push to `main`.

## License

TBD.
