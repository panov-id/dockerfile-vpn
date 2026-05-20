# Deploy SSH key (no passphrase)

Launchpad and GitHub Actions connect to each VPS over SSH. Every GitHub Environment in **`.env.platform`** needs **`{PREFIX}_SSH_PRIVATE_KEY_HOST_PATH`** — the deploy private key on your laptop, **without a passphrase**.

Example: `PRODUCTION_SSH_PRIVATE_KEY_HOST_PATH`, `DEV_SSH_PRIVATE_KEY_HOST_PATH`, …

## Why no passphrase

| Context | Can ask for passphrase? |
|---------|------------------------|
| Your laptop + `ssh-agent` | Yes — daily key with `-N 'your phrase'` works in the terminal |
| **Launchpad container** | **No** — no TTY, no ssh-agent from the host |
| **GitHub Actions** | **No** — uses `SSH_PRIVATE_KEY` secret as a file |

If the key is encrypted, you see `Permission denied (publickey)` even though interactive SSH works on the laptop.

## Create a deploy key (recommended)

```bash
ssh-keygen -t ed25519 -f ~/.ssh/vpn_deploy_ed25519 -N '' -C 'dockerfile-vpn-deploy'
```

Install the public key on **each** VPS you use (replace user and host):

```bash
ssh-copy-id -i ~/.ssh/vpn_deploy_ed25519.pub root@YOUR_VPS_IP
```

Or append manually: `cat ~/.ssh/vpn_deploy_ed25519.pub >> ~/.ssh/authorized_keys` on the server.

## Configure `.env.platform`

One block per environment (same key path is fine if one key is authorized on all servers):

```bash
PRODUCTION_SSH_HOST=203.0.113.10
PRODUCTION_SSH_USER=root
PRODUCTION_SSH_PRIVATE_KEY_HOST_PATH=/home/you/.ssh/vpn_deploy_ed25519

DEV_SSH_HOST=203.0.113.20
DEV_SSH_USER=root
DEV_SSH_PRIVATE_KEY_HOST_PATH=/home/you/.ssh/vpn_deploy_ed25519
```

See **`.env.platform.example`** and [multi-server-deployment.md](multi-server-deployment.md).

Launchpad uploads each environment’s key to GitHub as **`SSH_PRIVATE_KEY`** for that Environment.

## Verify before launchpad

```bash
./scripts/verify-deploy-ssh-key.sh
```

Checks **every** environment in `PLATFORM_ENVIRONMENTS`: file exists, **no passphrase**, SSH login to `{PREFIX}_SSH_HOST`.

## Security notes

- Use this key **only** for deploy automation — not your personal login key.
- Restrict `SSH_USER` (e.g. dedicated `deploy` user).
- Rotate: new key pair → `authorized_keys` on each VPS → update `.env.platform` → re-run launchpad.

## VPS Docker

Launchpad installs **Docker Engine** and **Compose** on Debian/Ubuntu before deploying stands (`SETUP_VPS_INSTALL_DOCKER=true`, default). On newer Debian (e.g. Trixie) without `docker-compose-plugin` in apt, Compose **v2** is installed from GitHub releases.

## Related

- [launchpad.md](launchpad.md) — full platform setup
- [multi-server-deployment.md](multi-server-deployment.md) — different VPS per environment
- [user-experience.md](user-experience.md) — first-time setup (RU), PAT section
