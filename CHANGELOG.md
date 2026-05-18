# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Documentation

- **`docs/github-workflow.md`** — contributor-facing GitHub process (branches, PRs, CI, Releases, environments).
- **`CONTRIBUTING.md`** — entry point linking to that workflow doc.

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
