# Platform Launchpad (export mirror)

This directory is the **source-of-truth skeleton** for the standalone product repository:

**https://github.com/panov-id/platform-launchpad**

## Version

Current export matches product version **1.0.0** (`VERSION`).

## What belongs here (product repo)

- `docker/Dockerfile.launchpad`, `docker/launchpad-entrypoint.sh`, `docker/docker-compose.launchpad.yml`
- Generic `scripts/lib/` (platform environments, launchpad preflight, SSH key staging, git helpers)
- `scripts/setup-platform.sh` (GitHub + VPS bootstrap — no app-specific compose)
- Published as `ghcr.io/panov-id/platform-launchpad:<semver>`

## What stays in the application repo

- Application `docker-compose.yml`, stands, GitHub Actions workflows
- `scripts/stand-layout.sh`, `scripts/remote/vps-deploy-stand.sh`
- **Observability** (`docker-compose.observability.yml`, Grafana/Loki)
- `.platform.yaml` + `.env.platform`

## Consumption from an app

In the application repository `.platform.yaml`:

```yaml
platform_launchpad:
  source: registry
  image: ghcr.io/panov-id/platform-launchpad
  version: "1.0.0"
```

Run: `./scripts/launchpad-run.sh` (script lives in the app; it pulls the product image).

See [docs/platform-launchpad-product.md](../../docs/platform-launchpad-product.md).
