# Deploy SSH key (no passphrase)

Launchpad and GitHub Actions connect to your VPS over SSH using the private key at **`LAUNCHPAD_SSH_PRIVATE_KEY_HOST_PATH`**. That file must be a **deploy key without a passphrase**.

## Why no passphrase

| Context | Can ask for passphrase? |
|---------|------------------------|
| Your laptop + `ssh-agent` | Yes — daily key with `-N 'your phrase'` works in the terminal |
| **Launchpad container** | **No** — no TTY, no ssh-agent from the host |
| **GitHub Actions** | **No** — uses `SSH_PRIVATE_KEY` secret as a file |

If the key is encrypted, you see `Permission denied (publickey)` even though `ssh root@vps` works on the laptop.

## Create a deploy key (recommended)

```bash
ssh-keygen -t ed25519 -f ~/.ssh/vpn_deploy_ed25519 -N '' -C 'dockerfile-vpn-deploy'
```

Install the public key on the VPS (replace user and host):

```bash
ssh-copy-id -i ~/.ssh/vpn_deploy_ed25519.pub root@YOUR_VPS_IP
```

Or append manually: `cat ~/.ssh/vpn_deploy_ed25519.pub >> ~/.ssh/authorized_keys` on the server.

## Configure `.env.platform`

```bash
SSH_HOST=YOUR_VPS_IP
SSH_USER=root
LAUNCHPAD_SSH_PRIVATE_KEY_HOST_PATH=/home/you/.ssh/vpn_deploy_ed25519
```

The same private key is uploaded to GitHub Environment secrets as **`SSH_PRIVATE_KEY`** when you run launchpad.

## Verify before launchpad

```bash
./scripts/verify-deploy-ssh-key.sh
```

Checks: file exists, **no passphrase**, optional SSH login to `SSH_HOST` / `SSH_USER`.

## Security notes

- Use this key **only** for this VPS / project — not your personal login key.
- Restrict `SSH_USER` (e.g. dedicated `deploy` user, `sudo` only if needed).
- Rotate by generating a new key pair, updating `authorized_keys`, `.env.platform`, and re-running launchpad.

## VPS Docker

Launchpad installs **Docker Engine** and **Compose** on Debian/Ubuntu before deploying stands (`SETUP_VPS_INSTALL_DOCKER=true`, default). On newer Debian (e.g. Trixie) without `docker-compose-plugin` in apt, Compose **v2** is installed from GitHub releases.

## Related

- [launchpad.md](launchpad.md) — full platform setup
- [user-experience.md](user-experience.md) — first-time setup (RU), PAT section
