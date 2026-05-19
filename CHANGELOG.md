# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **MIT** [LICENSE](LICENSE).
- README banner ([docs/assets/banner.png](docs/assets/banner.png)), streamlined README structure.

## [1.2.0] - 2026-05-19

### Added

- **Launchpad container** (`docker/Dockerfile.launchpad`, **`./scripts/launchpad-run.sh`**) — run full platform setup from Docker only; **`GITHUB_TOKEN`** in `.env.platform` replaces `gh` on the host.
- **`docs/user-experience.md`** — user journeys (first setup, MR preview, dev/prod), what is manual vs automated (Russian).
- **`docs/launchpad.md`**, **`docs/README.md`** — documentation index and launchpad guide.
- **`./scripts/setup-platform.sh`** — one-shot setup from **`.env.platform`** (only SSH + DNS zone required): GitHub envs/secrets/vars, `dev`/`test` branches, VPS stands over SSH.
- **`.env.platform.example`**, **`scripts/lib/load-platform-config.sh`**, **`scripts/platform-aliases.sh`** (`vpn-setup`), **`scripts/generate-wizard-stdin.sh`**.

### Changed

- **README.md**, **CONTRIBUTING.md**, **docs/github-workflow.md**, **server-wizard-user-guide.ru.md** — launchpad-first quick start; PR → **`dev`**; production via Release only.

## [1.1.0] - 2026-05-18

### Added

- **Stands on one VPS:** persistent **`dev`** and **`test`** stands; **MR preview** on every PR into **`dev`** (`pull/N/merge`), PR comment with endpoint, teardown on close.
- **Per-stand DNS** via **`STAND_DNS_ZONE`** (e.g. `mr-42.vpn.example.com`, `dev.vpn.example.com`; wildcard `*.vpn.example.com` recommended).
- **`scripts/stand-layout.sh`**, **`scripts/stand-resolve-public-host.sh`**, **`scripts/remote/vps-deploy-stand.sh`**, **`scripts/remote/vps-teardown-stand.sh`**.
- Workflows: **`deploy-dev-stand.yml`**, **`deploy-test-stand.yml`**, **`deploy-mr-preview.yml`**, **`teardown-mr-preview.yml`**, **`stand-layout-validate.yml`**.
- **`docs/stands-on-one-vps.md`** — ports, DNS, GitHub variables, first-time VPS layout.
- **`docs/server-wizard-user-guide.ru.md`** — Russian walkthrough: 5-step context, wizard stages, examples, scenarios A–D.
- **`docs/github-workflow.md`**, **`CONTRIBUTING.md`**, README **Your workflow in five steps**.

### Changed

- **`server-setup-wizard.sh`**: workflow intro/finish, numbered stages, bilingual help (`WIZARD_LANGUAGE` / `LANG=ru*`), stack profiles aligned with **`stand-layout.sh`**.
- **`test-wizard-docker.sh`**: answers for profile, `.env` reconfigure, optional **ufw**.

## [1.0.0] - 2026-05-18

First documented baseline: WireGuard on Docker, Git-only deploy from GitHub Releases, local dev overlay, and server setup automation.

### Added

- Production WireGuard stack (`docker-compose.yml`, `.env.example`, linuxserver/wireguard image).
- GitHub Actions: **`deploy-release.yml`** — deploy when a **Release** is **published** (`git fetch --tags`, checkout release tag, `docker compose up`); environments **`uat`** (pre-release) vs **`production`** (stable).
- **`compose-validate.yml`** — `docker compose config` on pull requests.
- Local development: **`docker-compose.local.yml`**, `.env.local` examples, **`local-compose-*`**, **`local-smoke-check.sh`**, **`local-two-stacks-test.sh`**.
- **`scripts/interactive-setup.sh`**, **`scripts/vps-bootstrap.sh`**, **`scripts/server-setup-wizard.sh`** (interactive server bootstrap after `git clone`).
- Wizard integration test: **`docker/Dockerfile.wizard-test`**, **`docker/docker-compose.wizard-test.yml`**, **`scripts/test-wizard-docker.sh`** (scripted stdin; optional `WIZARD_TEST_SKIP_COMPOSE_UP`).
- **`wizard-docker-test.yml`** — CI builds the test image and runs the scripted wizard on relevant path changes.

### Changed

- **`scripts/server-setup-wizard.sh`**: start Docker with **`systemctl`** only when systemd is available (friendlier in containers / non-systemd hosts).

### Documentation

- **`README.md`**: process overview table, wizard Docker test section, deployment flow.
