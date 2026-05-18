# Dev, test, and MR preview stands on one VPS

All stands share one physical server for now. Each stand is an **isolated** directory, **Compose project name**, **UDP port**, and **tunnel subnet**. Production/UAT from **GitHub Releases** stay as documented in the root README.

## Branch and deploy model

```text
feature/* ──PR──► dev ──(merge)──► dev stand updated
                    │
                    └── MR preview stand (per PR, merge ref, torn down on close)

test branch ──push──► test stand

main + Release published ──► production / uat (existing deploy-release.yml)
```

| Stand | Trigger | Git revision on VPS | Typical path |
|-------|---------|---------------------|--------------|
| **dev** | Push to branch **`dev`** | Branch `dev` | `${STANDS_ROOT}/dev` |
| **test** | Push to branch **`test`** | Branch `test` | `${STANDS_ROOT}/test` |
| **mr-&lt;N&gt;** | PR opened/updated **into `dev`** | `pull/N/merge` (preview merge, not merged yet) | `${STANDS_ROOT}/mr-N` |
| **uat / production** | Release published | Release tag | `DEPLOY_DIRECTORY` per environment |

## Port and subnet map (default formulas)

Computed by [`scripts/stand-layout.sh`](../scripts/stand-layout.sh):

| Stand | UDP port | Subnet | Compose project |
|-------|----------|--------|-----------------|
| production | 51820 | 10.13.13.0 | vpn-production |
| uat | 51821 | 10.13.14.0 | vpn-uat |
| test | 51822 | 10.13.22.0 | vpn-test |
| dev | 51823 | 10.13.23.0 | vpn-dev |
| MR #N | 51900 + N | 10.20.(N mod 254 + 1).0 | vpn-mr-N |

## DNS hostnames (`STAND_DNS_ZONE`)

Set GitHub variable **`STAND_DNS_ZONE`** = `vpn.example.com` (your zone). Deploy workflows write this into each stand’s **`.env`** as **`WIREGUARD_SERVER_PUBLIC_HOST`**:

| Stand | Hostname |
|-------|----------|
| production | `vpn.example.com` (zone apex) |
| uat | `uat.vpn.example.com` |
| test | `test.vpn.example.com` |
| dev | `dev.vpn.example.com` |
| MR #42 | **`mr-42.vpn.example.com`** |

Computed by [`scripts/stand-layout.sh`](../scripts/stand-layout.sh) when `STAND_DNS_ZONE` is set ([`scripts/stand-resolve-public-host.sh`](../scripts/stand-resolve-public-host.sh) for CLI).

### DNS at your provider (recommended)

Point all stand hostnames to the **same VPS IP**:

```text
*.vpn.example.com.   A    203.0.113.10
vpn.example.com.     A    203.0.113.10
```

Wildcard covers every **`mr-<N>.vpn.example.com`** without creating records per PR. You can still add explicit A records for `dev`, `test`, etc.

If **`STAND_DNS_ZONE`** is unset, workflows fall back to **`WIREGUARD_SERVER_PUBLIC_HOST`** (single hostname for every stand — legacy mode).

Open **every used UDP port** in the cloud provider firewall (and host `ufw` if enabled).

**MR limit:** PR numbers above **1099** exceed port 52999 — reduce PR number or adjust the formula in `stand-layout.sh` before that happens.

## GitHub setup (automated)

Run on your laptop (after `cp .env.platform.example .env.platform` and `gh auth login`):

```bash
./scripts/setup-platform.sh
```

This creates environments, uploads secrets/variables, and bootstraps VPS stands — no manual typing in the GitHub UI.

### Manual reference (if you skip the script)

Create **Environments**: `dev`, `test`, `mr-preview` (can share the same VPS; secrets may be identical).

**Secrets** (each environment, or repo-wide):

| Secret | Purpose |
|--------|---------|
| `SSH_HOST` | VPS address |
| `SSH_USER` | Deploy user |
| `SSH_PRIVATE_KEY` | Private key for Actions |

**Variables** (recommended same values in `dev`, `test`, `mr-preview` while on one server):

| Variable | Example | Purpose |
|----------|---------|---------|
| `STANDS_ROOT` | `/srv/vpn` | Parent of `dev/`, `test/`, `mr-42/` |
| `STANDS_TOOLING_DIRECTORY` | `/srv/vpn/_tooling` | CI copies deploy scripts here |
| `STAND_DNS_ZONE` | `vpn.example.com` | **Preferred.** Per-stand hostnames (`mr-42.vpn.example.com`, `dev.vpn.example.com`, …) |
| `WIREGUARD_SERVER_PUBLIC_HOST` | _(optional)_ | Fallback if `STAND_DNS_ZONE` is empty (one hostname for all stands) |
| `GIT_REMOTE_URL` | `git@github.com:panov-id/dockerfile-vpn.git` | Used when creating a new stand clone |

Production/UAT still use **`DEPLOY_DIRECTORY`** in their own environments (see README).

## Workflows

| File | Event |
|------|--------|
| [`deploy-dev-stand.yml`](../.github/workflows/deploy-dev-stand.yml) | `push` → `dev` |
| [`deploy-test-stand.yml`](../.github/workflows/deploy-test-stand.yml) | `push` → `test` |
| [`deploy-mr-preview.yml`](../.github/workflows/deploy-mr-preview.yml) | PR → `dev` (opened/sync/reopened) |
| [`teardown-mr-preview.yml`](../.github/workflows/teardown-mr-preview.yml) | PR → `dev` closed |

MR preview jobs comment on the PR with host, port, and directory.

## First-time VPS layout (example)

```bash
sudo mkdir -p /srv/vpn/_tooling
sudo chown -R deploy:deploy /srv/vpn
```

Run the server wizard for the **first** stand, or let the first workflow create clones when `GIT_REMOTE_URL` is set.

## Manual checks on the server

```bash
./scripts/stand-layout.sh dev
./scripts/stand-layout.sh mr 42
cd /srv/vpn/mr-42 && docker compose ps
```

## Merge conflicts

If the PR cannot be merged into `dev`, GitHub does not provide `pull/N/merge` and the MR preview deploy **fails** until conflicts are resolved.

## Later: separate servers

Point `SSH_HOST` / `STANDS_ROOT` per environment to different machines; workflows stay the same.
