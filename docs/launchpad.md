# Launchpad container

Run **full platform setup** without installing `gh`, `git`, or OpenSSH clients on your laptop. The host only needs **Docker** and a filled **`.env.platform`**.

## Quick start

```bash
cp .env.platform.example .env.platform
```

Edit `.env.platform`:

| Variable | Example |
|----------|---------|
| `SSH_HOST` | VPS IP |
| `SSH_USER` | `deploy` |
| `LAUNCHPAD_SSH_PRIVATE_KEY_HOST_PATH` | `/home/you/.ssh/vpn_deploy_ed25519` |
| `GITHUB_TOKEN` | `ghp_…` (classic PAT or fine-grained with repo + Actions secrets) |
| `STAND_DNS_ZONE` | `vpn.example.com` |

```bash
./scripts/launchpad-run.sh
```

## What the container does

1. Builds image `docker/Dockerfile.launchpad` (Debian + `gh` + `git` + `openssh-client`).
2. Mounts your repo, `.env.platform`, and SSH private key (read-only).
3. Authenticates `gh` with `GITHUB_TOKEN`.
4. Runs `scripts/setup-platform.sh` (GitHub envs, VPS stands, optional branch push).

## GitHub token scopes

Classic PAT: **`repo`**, **`workflow`** (or admin access to configure environments/secrets).

Fine-grained: repository access to this repo, permissions for **Actions**, **Environments**, **Secrets**, **Variables**, **Contents** (read/write for branch push).

## Files

| Path | Role |
|------|------|
| `docker/docker-compose.launchpad.yml` | Compose service definition |
| `docker/launchpad-entrypoint.sh` | Token login + invoke setup |
| `scripts/launchpad-run.sh` | Host wrapper (build + run) |

## Troubleshooting

| Problem | Fix |
|---------|-----|
| `LAUNCHPAD_SSH_PRIVATE_KEY_HOST_PATH` empty | Set absolute path to key in `.env.platform` |
| `gh` permission denied on secrets | Regenerate PAT with repo admin or required scopes |
| SSH to VPS fails | Key must match `authorized_keys` on VPS; `SSH_HOST` reachable |

See also: [user-experience.md](user-experience.md), [stands-on-one-vps.md](stands-on-one-vps.md).
