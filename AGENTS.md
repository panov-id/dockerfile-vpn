# Agent instructions (dockerfile-vpn)

Project-specific rules for humans and AI agents working in this repository.

## GitHub CLI (`gh`) — launchpad only

**On the developer machine (host), `gh` is intentionally not used and must not be required.**

| Where | `gh` | What to use instead |
|-------|------|---------------------|
| **Host** | Not installed / do not install | `./scripts/launchpad-run.sh` (Docker launchpad image) |
| **Launchpad container** | Yes (`docker/Dockerfile.launchpad`) | `scripts/setup-platform.sh` via entrypoint |

### Do not suggest on the host

- `sudo apt install gh`, `brew install gh`, or any host package install for GitHub CLI
- `gh auth login` on the host
- Running `gh secret set`, `gh api`, `gh variable set`, etc. directly in the user shell

### Do suggest instead

```bash
cp .env.platform.example .env.platform
# Fill GITHUB_TOKEN + each PRODUCTION_*, UAT_*, DEV_*, TEST_*, MR_PREVIEW_* block
./scripts/launchpad-run.sh
```

Secrets and platform setup live in **`.env.platform`** (gitignored). **Each GitHub Environment has its own `{PREFIX}_*` variables** — no global `SSH_HOST` fallback. See [docs/multi-server-deployment.md](docs/multi-server-deployment.md).

**`{PREFIX}_SSH_PRIVATE_KEY_HOST_PATH`** — deploy key **without a passphrase**. See [docs/deploy-ssh-key.md](docs/deploy-ssh-key.md). Run `./scripts/verify-deploy-ssh-key.sh` before launchpad.

Teardown VPS only: `TEARDOWN_CONFIRM=yes ./scripts/teardown-platform-run.sh` (does not delete GitHub environments).

Optional host path (only if the user already has `gh` and prefers it): `./scripts/setup-platform.sh` — documented as fallback, not the default.

## Docker-first execution

- Prefer **`docker compose`** / **`./scripts/launchpad-run.sh`** over assuming tools on the host.
- Local Compose checks: `scripts/compose-config-check.sh`, `scripts/local-compose-up.sh`, wizard test via `docker/docker-compose.wizard-test.yml`.
- Do not run `npm test` / Playwright on the host if the task is covered by CI or Docker scripts in this repo.

## GitHub.com (this repo)

- Web / PAT / `gh` / API: **https://github.com**, repo **`panov-id/dockerfile-vpn`**
- Do **not** copy a custom SSH hostname from `git remote` into `GH_HOST` in `.env.platform`
- `GH_HOST` / `GITHUB_API_URL` only for self-hosted **GitHub Enterprise Server**, not for github.com

## Branches `dev` and `test`

Created by **`setup-platform.sh`** when `SETUP_CREATE_BRANCHES=true` (default), during launchpad run — not by manual `gh` on the host.

If branches are missing after launchpad:

1. Run **`./scripts/launchpad-diagnose-git.sh`** (read-only; prints `gh` / API / `ls-remote` errors).
2. Fix `.env.platform` (remove wrong `GH_HOST`; `GITHUB_TOKEN` from github.com with Contents write), then **`./scripts/launchpad-diagnose-git.sh --try-create`**.
3. Full log: `./scripts/launchpad-run.sh 2>&1 | tee /tmp/launchpad.log` and grep for `Git:|branch|push|403|401`.
4. Or create **`dev`** and **`test`** in the GitHub UI from **`main`**.

## Key docs

| Topic | File |
|-------|------|
| Deploy SSH key | [docs/deploy-ssh-key.md](docs/deploy-ssh-key.md) |
| Launchpad | [docs/launchpad.md](docs/launchpad.md) |
| UX (RU) | [docs/user-experience.md](docs/user-experience.md) |
| Stands / DNS | [docs/stands-on-one-vps.md](docs/stands-on-one-vps.md) |
| Git workflow | [docs/github-workflow.md](docs/github-workflow.md) |
| Doc index | [docs/README.md](docs/README.md) |

## Commits

Git commit messages: **English only** (imperative subject).
