# Contributing

## First-time setup (you only edit secrets)

On your machine you need **Docker** only — not `gh`, not `git` CLI for setup.

```bash
cp .env.platform.example .env.platform
# Fill: SSH_HOST, SSH_USER, LAUNCHPAD_SSH_PRIVATE_KEY_HOST_PATH, GITHUB_TOKEN, STAND_DNS_ZONE
./scripts/launchpad-run.sh
```

Then at your DNS provider: **`*.vpn.example.com`** and apex → VPS IP; open UDP ports (see [stands-on-one-vps.md](docs/stands-on-one-vps.md)).

Details: **[docs/launchpad.md](docs/launchpad.md)**.

## Daily development

| Step | Action |
|------|--------|
| 1 | Branch from **`dev`**, code locally (optional: `./scripts/local-compose-up.sh`) |
| 2 | Open **PR into `dev`** → MR preview stand deploys automatically (`mr-<N>.vpn.example.com`) |
| 3 | Merge PR → **`dev`** stand updates on push |
| 4 | When ready for production: merge **`dev` → `main`**, tag, **publish Release** |

**Do not** expect merge to **`main`** alone to deploy production — only a **published Release** does.

## Documentation

| Topic | Link |
|-------|------|
| Full doc index | [docs/README.md](docs/README.md) |
| UX (Russian) | [docs/user-experience.md](docs/user-experience.md) |
| GitHub / CI | [docs/github-workflow.md](docs/github-workflow.md) |
| Stands & DNS | [docs/stands-on-one-vps.md](docs/stands-on-one-vps.md) |
| VPS wizard (Russian) | [docs/server-wizard-user-guide.ru.md](docs/server-wizard-user-guide.ru.md) |
| Repository overview | [README.md](README.md) |

## Commits and PRs

- Commit messages: **English** (imperative subject).
- Feature PRs target **`dev`** unless it is a release/hotfix to **`main`**.
- Wait for green CI (`compose-validate`, and path-specific workflows).
