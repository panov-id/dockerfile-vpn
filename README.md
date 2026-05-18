# Docker-based VPN on a VPS

This repository will hold **containerized VPN infrastructure** (a `Dockerfile`, `docker-compose.yml`, or both) that you run on **your own VPS**. The goal is a reproducible setup: define the service once, deploy updates safely, and keep secrets out of the Git history.

## Goals

- Run a VPN server on a VPS using **Docker** or **Docker Compose**.
- Automate delivery from **GitHub Actions**: deploy to the server **only when a GitHub Release is published** (`release`, type `published`). Ordinary merges to `main` do not deploy by themselves.
- Document ports, firewall expectations, and backup/rekey procedures.

## Your workflow in five steps

This repository assumes you move like this:

| Step | Where | What you do |
|------|-------|-------------|
| **1 — Develop locally** | Your laptop | Edit the repo; optionally run the stack with **`docker-compose.local.yml`** and **`./scripts/local-compose-up.sh`** / **`local-smoke-check.sh`** (nothing hits the VPS yet). |
| **2 — Put it in Git** | GitHub | Push your branch, open a **pull request**, merge into **`main`**. **Merge does not deploy** by itself. |
| **3 — Set up the server** | VPS (+ GitHub settings) | **Once per VPS/environment:** clone this repo on the server, run **`./scripts/server-setup-wizard.sh`** (Docker, **`.env`**, optional first **`docker compose up`**). In GitHub: **Actions** + **Environments** (**`production`** / **`uat`**), secrets **`SSH_HOST`**, **`SSH_USER`**, **`SSH_PRIVATE_KEY`**, variable **`DEPLOY_DIRECTORY`** = absolute path the wizard printed. Open **UDP** for WireGuard in cloud + host firewall. Details: [Getting started](#getting-started-what-you-need-first); wizard prompts (Russian): [`docs/server-wizard-user-guide.ru.md`](docs/server-wizard-user-guide.ru.md). |
| **4 — Publish a Release** | GitHub | Create a **tag** on **`main`** (e.g. **`v1.1.0`**), open **Releases**, **publish** a Release for that tag ([docs](https://docs.github.com/en/repositories/releasing-projects-on-github/managing-releases-in-a-repository)). **Pre-release** → **`uat`** environment; stable → **`production`** ([`deploy-release.yml`](.github/workflows/deploy-release.yml)). |
| **5 — See the result on the server** | VPS | The workflow SSHs to **`DEPLOY_DIRECTORY`**, **`git fetch --tags`**, **`git checkout`** the release tag, **`docker compose up -d --pull always`**. Check with **`docker compose ps`** / **`docker compose logs -f wireguard`**. |

**After step 3 is done**, routine delivery to **production** is **1 → 2 → 4 → 5**. Repeat step **3** only for a **new** server or GitHub Environment.

### Dev, test, and MR preview (same VPS for now)

| Stand | When it updates | What gets deployed |
|-------|-----------------|-------------------|
| **`dev`** | Push to branch **`dev`** | Branch `dev` at `${STANDS_ROOT}/dev` |
| **`test`** | Push to branch **`test`** | Branch `test` at `${STANDS_ROOT}/test` |
| **`mr-<PR#>`** | Pull request **into `dev`** (open/sync) | Git ref **`pull/<PR>/merge`** — preview of merging into `dev` **before** you click Merge |
| **production / uat** | Published **Release** | Release tag (unchanged) |

Each stand uses its own **UDP port**, **tunnel subnet**, **Compose project name**, and **DNS name** when **`STAND_DNS_ZONE`** is set (e.g. MR **#42** → `mr-42.vpn.example.com`). Full setup: **[docs/stands-on-one-vps.md](docs/stands-on-one-vps.md)**.

Typical feature flow: branch from **`dev`** → PR to **`dev`** → MR preview stand for manual check → merge → **`dev`** stand updates → later **`main`** + Release for production.

Process detail for contributors: **[docs/github-workflow.md](docs/github-workflow.md)**.

## One-command platform setup (secrets only)

You only maintain **`.env.platform`** (gitignored). Everything else is scripted.

```bash
cp .env.platform.example .env.platform
# Edit: SSH_HOST, SSH_USER, SSH_PRIVATE_KEY_FILE, STAND_DNS_ZONE
gh auth login   # once
./scripts/setup-platform.sh
```

Optional shell alias: `source scripts/platform-aliases.sh` then run **`vpn-setup`**.

The script configures **GitHub** (environments `production`, `uat`, `dev`, `test`, `mr-preview` + secrets/variables), creates **`dev`** / **`test`** branches if missing, and **bootstraps stands on the VPS** via SSH. See **[docs/stands-on-one-vps.md](docs/stands-on-one-vps.md)** for DNS (`*.vpn.example.com` → VPS).

## Developer workflow (GitHub)

How **branches, pull requests, CI, tags, Releases, and deployment** fit together — read **[docs/github-workflow.md](docs/github-workflow.md)** first. The short **[CONTRIBUTING.md](CONTRIBUTING.md)** points to the same doc.

## Non-goals (for now)

- Providing a public VPN exit for strangers (this is a **personal or small-team** setup unless you explicitly widen scope).
- Bundling a full observability stack unless we add it in a later phase (see [Roadmap](docs/ROADMAP.md)).

## Prerequisites (high level)

- A VPS with a public IP and **UDP** (and optionally **TCP**) ports opened in the provider firewall and OS firewall.
- **Docker Engine + Compose plugin** on the VPS — on Debian/Ubuntu usually installed by **`scripts/vps-bootstrap.sh`**; on other systems install manually.
- A **GitHub** repository with **Actions** enabled. Use **GitHub-hosted runners** (SSH deploy to your VPS over the public internet) or a **self-hosted runner** on the VPS if you prefer jobs to run locally without inbound SSH from GitHub’s cloud.

## Getting started (what you need first)

The **[five-step workflow](#your-workflow-in-five-steps)** above is the overview; below is **checklist detail** for step **3** (server + GitHub wiring) and friends.

Do these **roughly in order** the first time; later steps depend on earlier ones.

1. **VPS — Git already installed (recommended flow)**  
   ```bash
   git clone git@github.com:panov-id/dockerfile-vpn.git
   cd dockerfile-vpn
   chmod +x scripts/server-setup-wizard.sh   # if needed
   ./scripts/server-setup-wizard.sh
   ```
   The wizard asks whether to use **this clone** as the deploy directory or **clone again** elsewhere, then (on Debian/Ubuntu) can install **Docker + Compose**, fills **`.env`**, optional **ufw**, optional first **`docker compose up`**. At the end it prints the absolute path → paste into GitHub Environment variable **`DEPLOY_DIRECTORY`**.

   **Full prompt-by-prompt user guide (Russian):** [`docs/server-wizard-user-guide.ru.md`](docs/server-wizard-user-guide.ru.md) — numbered stages, description + examples per prompt, scenarios A–D. On the VPS, Russian hints appear when `LANG` is `ru*` or `WIZARD_LANGUAGE=ru`. The wizard prints the **5-step workflow**, offers **production / uat / custom** stack presets, and ends with a checklist for **Release** (steps 4–5).

   **Not the same script:** on your **laptop**, **`scripts/interactive-setup.sh`** is only a **menu** (local Compose checks, optional `gh` helpers). It does **not** replace **`server-setup-wizard.sh`** on the VPS.

   **Private repo:** use an SSH URL or HTTPS with credentials your server already has configured.

   **Alternative — non-interactive one-shot:** **`scripts/vps-bootstrap.sh`** (curl or sudo env vars) — see script header.

2. **Firewall** — open **UDP** for **`WIREGUARD_SERVER_PORT`** (provider + host).

3. **SSH for GitHub Actions** — deploy user + **`authorized_keys`** for the Actions deploy key.

4. **GitHub** — push this repo, enable **Actions**, **branch protection** on **`main`** (PR-only merges); **[Environments](https://docs.github.com/en/actions/deployment/targeting-different-environments/using-environments-for-deployment)** **`production`** / **`uat`**; secrets **`SSH_HOST`**, **`SSH_USER`**, **`SSH_PRIVATE_KEY`**; variable **`DEPLOY_DIRECTORY`** = **exact absolute path** the server wizard printed (same directory where **`docker-compose.yml`** lives — Actions runs **`git fetch --tags`**, **`git checkout` release tag**, **`docker compose up`** there).

5. **Edit server `.env`** — **`WIREGUARD_SERVER_PUBLIC_HOST`**, unique port/subnet/**`COMPOSE_PROJECT_NAME`** per stack on one VPS.

6. **Smoke test** — on VPS: `cd DEPLOY_DIRECTORY && docker compose up -d`; then publish a **Release** — workflow updates the clone to the release **tag** and restarts Compose.

After that, routine work is: **feature branch → PR → merge to `main` → tag → Release (pre-release or stable) → deploy**.

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
| **First VPS setup** | Server | **`git clone`** → **`./scripts/server-setup-wizard.sh`** (interactive) **or** **`vps-bootstrap.sh`** (non-interactive). Produces a **git working tree** used as **`DEPLOY_DIRECTORY`**, a server **`.env`**, and Docker for **`docker compose`**. |
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

This menu walks through **Compose validation**, **local Docker smoke**, **VPS / GitHub checklists**, and (if **`gh`** is installed and logged in) **creating environments** and **uploading deploy secrets** via `gh secret` / `gh variable` — nothing sensitive is committed to Git.

For **server** setup after `git clone` on the VPS, use **`./scripts/server-setup-wizard.sh`** and the guide **[`docs/server-wizard-user-guide.ru.md`](docs/server-wizard-user-guide.ru.md)**.

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

- Create the VPS, open **UDP** ports, configure **`.env`** on the server (never committed). **`DEPLOY_DIRECTORY`** is created/populated by **`vps-bootstrap.sh`** or your own clone.
- Generate GitHub **secrets**, **environment variables**, **branch protection**, and trust **SSH** host keys (optionally extend workflows with `KNOWN_HOSTS` / `ssh-keyscan` hardening).
- Provider firewall rules and backups.

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

- **Single integration branch:** `main`.
- **Direct pushes to `main` are discouraged:** integrate work through **pull requests** (merge requests). Enforce this with **branch protection** on GitHub (require PR, optional required checks).

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

#### How this fits “deploy only on **release published**”

GitHub gives **one** “pre-release” checkbox, so it cannot express **three** staging tiers by that flag alone. Typical patterns:

1. **Production + UAT strictly via Releases:** stable tag → **production**; **pre-release** → **UAT** (same as already documented).
2. **Dev + test without pretending every push is a release:**
   - **Development:** developers run **Compose locally**, or you allow an **extra** workflow (**`workflow_dispatch`** only) that deploys to the **development** directory on the VPS—still gated (manual button), not on every merge.
   - **Test:** keep **test** as **CI-only** (lint, `docker compose config`, optional short-lived container checks). No VPS deploy unless you **choose** to also publish a **GitHub Release** aimed at test (for example tags like `v0.0.0-test.1`) so the rule “deploy only from releases” stays literally true for **every** remote stack.
3. **Tag naming (recommended if every remote tier must ship via a Release):** encode the tier in the tag or release name and branch in the workflow with `if:` conditions, for example:
   - `v*-dev*` → GitHub Environment **`development`** (same VPS path `…/development`)
   - `v*-test*` → **`test`**
   - **Pre-release** stable-looking candidate → **`uat`**
   - Stable semver without those markers → **`production`**

Use **[GitHub Environments](https://docs.github.com/en/actions/deployment/targeting-different-environments/using-environments-for-deployment)** (`development`, `test`, `uat`, `production`) with **scoped secrets** (deploy path, optional different UNIX users). **Production** should have the strictest protection (required reviewers); **development** can be looser.

**Earlier options still apply for UAT vs production only:** pre-release flag, tag convention, manual approval gates—now extended so **dev** and **test** have a defined place (local / CI / optional dispatch / release tags).

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
├── .gitignore
├── docker/
│   ├── Dockerfile.wizard-test
│   └── docker-compose.wizard-test.yml
├── docs/
│   ├── ROADMAP.md
│   ├── github-workflow.md
│   ├── stands-on-one-vps.md   # dev / test / MR stands, DNS, ports
│   └── server-wizard-user-guide.ru.md
├── scripts/
│   ├── setup-platform.sh      # one-shot from .env.platform
│   ├── platform-aliases.sh    # optional: vpn-setup alias
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
