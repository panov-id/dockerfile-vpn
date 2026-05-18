# Roadmap (draft)

Step-by-step plan for containerized VPN on a VPS and automated deploy from GitHub. Status and dates are TBD; adjust as we implement.

## 1. Baseline VPN

- **Decision (recorded in root `README.md`):** WireGuard via linuxserver image, file-based configs under `./config`, no admin web UI unless scope changes.
- **`docker-compose.yml` + `.env.example`:** added to this repository — tune per environment.

## 2. Hardening

- OS firewall rules (`ufw`/`nftables`) and VPS provider security group checklist.
- Optional: fail2ban or rate limiting where applicable; periodic image updates.

## 3. GitHub Actions → VPS

- **Deploy trigger (fixed):** `on: release: types: [published]` only—no deploy solely from merges to `main`. Workflow files live under `.github/workflows/` (`deploy-release.yml`, `compose-validate.yml`).
- **Git policy (fixed):** integrate via PR into `main`; protected branch; releases cut from tags on `main`.
- **Optional multi-env on one VPS:** separate UDP ports, tunnel subnets, directories, and Compose project names; **dev** often local or manual/`workflow_dispatch`, **test** often CI-only or release tags, **UAT** vs production via prerelease or tag naming—see root `README.md` (“Dev / test / UAT on the same VPS”).
- Workflow jobs such as: **`compose-validate`** on PR (Compose syntax) → **`deploy-release`** on `release` published (scp compose files + remote `docker compose up`).
- **Implemented deploy path:** **scp** `docker-compose.yml` / `.env.example` to `DEPLOY_DIRECTORY`, then SSH **`docker compose up -d --pull always`** (no `git pull` on the VPS).
- Alternative later: **`git pull` at release tag** on the VPS, or **build/push custom image** to **`ghcr.io`** — see root `README.md` history / issues if we switch.

- Store **SSH private key**, host, and host key verification material as **repository or environment secrets**; never commit secrets. Use **GitHub Environments** (`uat`, `production`, …) with optional required reviewers for production.

## 4. Operations

- Backup/export of WireGuard configuration (without leaking private keys into artifacts).
- Runbook: add/remove peer, rotate keys, restore from backup.
