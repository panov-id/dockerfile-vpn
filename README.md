# Docker-based VPN on a VPS

This repository will hold **containerized VPN infrastructure** (a `Dockerfile`, `docker-compose.yml`, or both) that you run on **your own VPS**. The goal is a reproducible setup: define the service once, deploy updates safely, and keep secrets out of the Git history.

## Goals

- Run a VPN server on a VPS using **Docker** or **Docker Compose**.
- Automate delivery from **GitHub Actions**: deploy to the server **only when a GitHub Release is published** (`release`, type `published`). Ordinary merges to `main` do not deploy by themselves.
- Document ports, firewall expectations, and backup/rekey procedures.

## Non-goals (for now)

- Providing a public VPN exit for strangers (this is a **personal or small-team** setup unless you explicitly widen scope).
- Bundling a full observability stack unless we add it in a later phase (see [Roadmap](docs/ROADMAP.md)).

## Prerequisites (high level)

- A VPS with a public IP and **UDP** (and optionally **TCP**) ports opened in the provider firewall and OS firewall.
- **Docker Engine** and optionally **Docker Compose v2** on the VPS (installation steps will be added with the compose file).
- A **GitHub** repository with **Actions** enabled. Use **GitHub-hosted runners** (SSH deploy to your VPS over the public internet) or a **self-hosted runner** on the VPS if you prefer jobs to run locally without inbound SSH from GitHub’s cloud.

## Getting started (what you need first)

Do these **roughly in order**; later steps depend on earlier ones.

1. **VPS**
   - Fresh or existing Linux host with a **static-ish public IP**, **sudo**, and outbound internet for images.
   - Install **Docker Engine** and **Docker Compose v2 plugin**.
   - Plan **one UDP port per WireGuard stack** you will run (production first; add UAT/dev/test ports when needed). Open them in the **provider firewall** and **`ufw`/`nftables`** (if used).

2. **Directories on the server**
   - Create deploy roots (example): `/opt/dockerfile-vpn/production` (and later `uat`, `test`, `development` if you use those tiers).
   - Keys and `.env` with secrets stay **on the server** (or in CI secrets), **not** in Git.

3. **SSH access for automation**
   - Dedicated **deploy** UNIX user (or role account), **`authorized_keys`** only for the **GitHub Actions** deploy key.
   - Prefer **restricted key**, non-interactive commands if you harden further later.
   - Know **`ssh-ed25519` host key** fingerprint for `known_hosts` in Actions.

4. **GitHub repository**
   - Push this repo (or connect origin), enable **Actions**.
   - **Branch protection** on `main`: require **pull request**, block force-push; add required checks when workflows exist (PRs run **Compose validate** when compose files change).
   - Create **[Environments](https://docs.github.com/en/actions/deployment/targeting-different-environments/using-environments-for-deployment)** named **`production`** and **`uat`** (pre-releases deploy to `uat`). For each environment add **secrets** `SSH_HOST`, `SSH_USER`, `SSH_PRIVATE_KEY` and a **variable** `DEPLOY_DIRECTORY` (absolute path on the VPS, for example `/opt/dockerfile-vpn/production/` — create that directory once; the deploy step uploads into it).

5. **Server-side `.env` (once per environment directory)**
   - Copy `.env.example` → `.env` in `DEPLOY_DIRECTORY`, set **`WIREGUARD_SERVER_PUBLIC_HOST`** to your VPS DNS name or IP, choose **`WIREGUARD_SERVER_PORT`** / **`WIREGUARD_INTERNAL_SUBNET`** / **`COMPOSE_PROJECT_NAME`** (must differ per stack on one VPS). The linuxserver image generates persistent WireGuard material under `./config` on first start.

6. **Smoke test before the first “real” release**
   - On the VPS inside `DEPLOY_DIRECTORY`, run `docker compose up -d` once (same command CI uses later). Confirm a client connects using generated peer files under `config/`.
   - Publish a **GitHub Release** from a tag on `main` and verify **Deploy published release** copies `docker-compose.yml` / `.env.example` and restarts the stack.

After that, routine work is: **feature branch → PR → merge to `main` → tag → Release (pre-release or stable) → deploy**.

### Interactive wizard (optional)

After cloning/updating the repo on your machine:

```bash
./scripts/interactive-setup.sh
```

This menu walks through **Compose validation**, **local Docker smoke**, **VPS / GitHub checklists**, and (if **`gh`** is installed and logged in) **creating environments** and **uploading deploy secrets** via `gh secret` / `gh variable` — nothing sensitive is committed to Git.

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
- **`.github/workflows/deploy-release.yml`** — on **`release` published**, checks out the release tag, **scp**’s `docker-compose.yml` and `.env.example` to **`DEPLOY_DIRECTORY`** on the VPS, then SSH **`docker compose up -d --pull always`**. The job targets GitHub Environment **`uat`** when the release is a **pre-release**, otherwise **`production`**.

**Only you (or your cloud/GitHub account) can do:**

- Create the VPS, install Docker, open **UDP** ports, create **`DEPLOY_DIRECTORY`**, write **`.env`** on the server (never committed).
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
├── docker-compose.yml
├── docker-compose.local.yml   # local overrides (LOCAL_WIREGUARD_CONFIG_DIRECTORY)
├── .env.example
├── .env.local.example
├── .env.local.stack-b.example
├── .gitignore
├── docs/
│   └── ROADMAP.md
├── scripts/
│   ├── compose-config-check.sh
│   ├── local-compose-down.sh
│   ├── local-compose-logs.sh
│   ├── local-compose-up.sh
│   ├── local-smoke-check.sh
│   ├── local-two-stacks-test.sh
│   ├── interactive-setup.sh   # menu: local checks + optional gh bootstrap
│   └── deploy-from-runner-over-ssh.sh
└── .github/workflows/
    ├── compose-validate.yml
    └── deploy-release.yml
```

## Security reminders

- Do **not** commit real private keys, `.env` with secrets, or client configs containing secrets.
- Prefer **branch protection**, **required reviews**, and **deployment environment gates** (especially for production) until the workflow is trusted. Deploy runs on **`release` published**, not on every push to `main`.

## License

TBD.
