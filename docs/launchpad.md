# Launchpad container

Run **full platform setup** without installing `gh`, `git`, or OpenSSH on your laptop. You need **Docker** and **`.env.platform`**.

## Quick start

```bash
cp .env.platform.example .env.platform
# Fill variables (see checklist in the example file)
./scripts/verify-deploy-ssh-key.sh
./scripts/launchpad-run.sh
```

| Variable | Purpose |
|----------|---------|
| `PRODUCTION_*`, `UAT_*`, `DEV_*`, `TEST_*`, `MR_PREVIEW_*` | **Required** per GitHub Environment — see `.env.platform.example` |
| `{PREFIX}_SSH_HOST`, `{PREFIX}_SSH_USER`, `{PREFIX}_SSH_PRIVATE_KEY_HOST_PATH` | VPS target for that environment |
| `{PREFIX}_BOOTSTRAP_STANDS` | Stands to deploy on that server (`dev`, `production`, …; empty for `mr-preview`) |
| `GITHUB_TOKEN` | PAT from [github.com/settings/tokens](https://github.com/settings/tokens) |

Multi-server: [multi-server-deployment.md](multi-server-deployment.md). Teardown: `TEARDOWN_CONFIRM=yes ./scripts/teardown-platform-run.sh`.

`GH_HOST` — only for self-hosted GitHub Enterprise; leave unset for **github.com**.

## What launchpad runs (order)

1. **`dev` / `test` branches** (GitHub API) if missing  
2. **GitHub Environments** + secrets + variables  
3. **VPS:** install **Docker + Compose** on Debian/Ubuntu if missing (`docker.io`, `docker-compose-plugin`)  
4. **VPS stands** (`dev`, `test`, `uat`, `production` by default) — clone + `docker compose up`  

See [stands-on-one-vps.md](stands-on-one-vps.md) for DNS and UDP firewall. Disable auto-install: `SETUP_VPS_INSTALL_DOCKER=false` in `.env.platform`.

## GitHub PAT (fine-grained)

For `panov-id/dockerfile-vpn`: **Contents**, **Actions**, **Administration**, **Secrets** — all **Read and write**. Authorize **SSO** for org `panov-id` if required. Details: [user-experience.md](user-experience.md) (PAT section, RU).

## Scripts

| Script | Role |
|--------|------|
| `scripts/launchpad-run.sh` | Build image + run setup |
| `scripts/verify-deploy-ssh-key.sh` | Host check: key without passphrase + SSH login |
| `scripts/launchpad-diagnose-git.sh` | GitHub branches / PAT diagnostics |
| `scripts/setup-platform.sh` | Invoked inside container |
| `scripts/teardown-platform-run.sh` | Remove stands/tooling from VPS (not GitHub) |
| `scripts/migrate-env-platform-per-environment.sh` | One-time legacy `.env.platform` → per-environment blocks |

## Troubleshooting

| Problem | Fix |
|---------|-----|
| SSH `Permission denied` | [deploy-ssh-key.md](deploy-ssh-key.md) — key with passphrase or wrong `authorized_keys` |
| `docker: command not found` on VPS | Re-run launchpad (`SETUP_VPS_INSTALL_DOCKER=true`); or install Docker manually on Debian/Ubuntu |
| `SSH private key requires a passphrase` | Create key with `-N ''`; run `verify-deploy-ssh-key.sh` |
| `403` on secrets / environments | PAT: **Secrets** + **Administration** read/write; SSO authorize |
| `dev` / `test` missing | `./scripts/launchpad-diagnose-git.sh --try-create` |
| Exits after `GITHUB_TOKEN environment variable` | Rebuild image (`launchpad-run.sh` rebuilds); fixed in entrypoint |

## Related

- [deploy-ssh-key.md](deploy-ssh-key.md)  
- [user-experience.md](user-experience.md)  
- [stands-on-one-vps.md](stands-on-one-vps.md)
