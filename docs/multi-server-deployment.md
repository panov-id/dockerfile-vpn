# Multi-server deployment (per-environment config)

Each **GitHub Environment** (`production`, `uat`, `dev`, `test`, `mr-preview`) has its **own** settings in `.env.platform`. There is **no** global `SSH_HOST` fallback.

## Quick start (unchanged)

```bash
cp .env.platform.example .env.platform
# Fill every PRODUCTION_*, UAT_*, DEV_*, TEST_*, MR_PREVIEW_* block
./scripts/launchpad-run.sh
```

One command — same as before. The file is longer because each environment is explicit.

## Variable naming

| GitHub Environment | Prefix in `.env.platform` |
|--------------------|---------------------------|
| `production` | `PRODUCTION_` |
| `uat` | `UAT_` |
| `dev` | `DEV_` |
| `test` | `TEST_` |
| `mr-preview` | `MR_PREVIEW_` |

Required fields per environment:

| Field | GitHub secret/variable |
|-------|-------------------------|
| `{PREFIX}_SSH_HOST` | Secret `SSH_HOST` |
| `{PREFIX}_SSH_USER` | Secret `SSH_USER` |
| `{PREFIX}_SSH_PRIVATE_KEY_HOST_PATH` | Secret `SSH_PRIVATE_KEY` (file on laptop) |
| `{PREFIX}_STANDS_ROOT` | Variable `STANDS_ROOT` |
| `{PREFIX}_STANDS_TOOLING_DIRECTORY` | Variable `STANDS_TOOLING_DIRECTORY` |
| `{PREFIX}_STAND_DNS_ZONE` | Variable `STAND_DNS_ZONE` |
| `{PREFIX}_BOOTSTRAP_STANDS` | Launchpad only — stands to deploy on that server |

Optional: `PLATFORM_ENVIRONMENTS` — comma list if you do not need all five.

## One VPS (same as before)

Use the **same** IP, user, key, and paths in every block. Example is in `.env.platform.example`.

Launchpad groups by server: Docker install and script upload happen **once per unique host**.

## Several VPS

Example:

| Environment | Server | `BOOTSTRAP_STANDS` |
|-------------|--------|---------------------|
| `production` | `203.0.113.10` | `production` |
| `uat` | `203.0.113.10` | `uat` |
| `dev`, `test`, `mr-preview` | `203.0.113.20` | `dev`, `test` / empty for MR |

Rules:

1. **Same physical server** → same `STANDS_ROOT` and `STANDS_TOOLING_DIRECTORY` in every block for that host (launchpad validates this).
2. **DNS** — point each environment’s hostnames to **that** environment’s `SSH_HOST` (wildcard per zone if you use one zone everywhere).
3. **UDP ports** — on a dedicated server you may use `51820` for every stand; on one shared server use distinct ports from `scripts/stand-layout.sh`.

## Teardown (remove from VPS)

Does **not** delete GitHub environments or secrets.

```bash
TEARDOWN_CONFIRM=yes ./scripts/teardown-platform-run.sh
```

Optional in `.env.platform`:

- `TEARDOWN_ENVIRONMENTS=production,dev` — limit scope
- `TEARDOWN_REMOVE_TOOLING=false` — keep `/_tooling` scripts on disk

For each server, teardown removes:

- Stand directories from `BOOTSTRAP_STANDS` of environments in scope
- `mr-*` directories if `mr-preview` is in scope
- `STANDS_TOOLING_DIRECTORY` when `TEARDOWN_REMOVE_TOOLING=true`

## See also

- [launchpad.md](launchpad.md)
- [stands-on-one-vps.md](stands-on-one-vps.md)
- [user-experience.md](user-experience.md) (RU)
