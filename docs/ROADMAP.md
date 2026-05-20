# Roadmap (draft)

Step-by-step plan for containerized VPN on a VPS and automated deploy from GitHub. Status and dates are TBD; adjust as we implement.

## 1. Baseline VPN

- **Decision (recorded in root `README.md`):** WireGuard via linuxserver image, file-based configs under `./config`, no admin web UI unless scope changes.
- **`docker-compose.yml` + `.env.example`:** added to this repository — tune per environment.

## 2. Hardening

- OS firewall rules (`ufw`/`nftables`) and VPS provider security group checklist.
- Optional: fail2ban or rate limiting where applicable; periodic image updates.

## 3. GitHub Actions → VPS

- **Developer-facing summary:** [`docs/github-workflow.md`](github-workflow.md) (branches, PRs, CI, Releases, `uat` vs `production`).
- **Platform setup:** [`docs/launchpad.md`](launchpad.md) — `./scripts/launchpad-run.sh` only.
- **Deploy trigger (fixed):** `on: release: types: [published]` only—no deploy solely from merges to `main`. Workflow files live under `.github/workflows/` (`deploy-release.yml`, `compose-validate.yml`).
- **Git policy (fixed):** feature PRs into **`dev`**; MR preview stands; merge **`dev` → `main`** for production; releases from tags on **`main`**.
- **Multi-env on one VPS (implemented):** `dev` / `test` / MR preview stands + release deploy to **uat** / **production** — see [`stands-on-one-vps.md`](stands-on-one-vps.md) and launchpad setup in [`launchpad.md`](launchpad.md).
- Workflow jobs such as: **`compose-validate`** on PR (Compose syntax) → **`deploy-release`** on `release` published (SSH: **`git fetch --tags`**, **`git checkout`** release tag, **`docker compose up`** in **`DEPLOY_DIRECTORY`**).
- **Server bootstrap:** launchpad on laptop; **`server-setup-wizard.sh`** retained for CI wizard test only.
- Store **SSH private key**, host, and host key verification material as **repository or environment secrets**; never commit secrets. Use **GitHub Environments** (`uat`, `production`, …) with optional required reviewers for production.

## 4. Operations

- Backup/export of WireGuard configuration (without leaking private keys into artifacts).
- Runbook: add/remove peer, rotate keys, restore from backup.
