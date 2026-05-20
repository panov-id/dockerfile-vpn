# Documentation index

| Document | Language | What it covers |
|----------|----------|----------------|
| [../README.md](../README.md) | EN | Overview, quick start, repository layout |
| [deploy-ssh-key.md](deploy-ssh-key.md) | EN | VPS deploy key — **no passphrase** (launchpad + Actions) |
| [launchpad.md](launchpad.md) | EN | Platform setup in Docker — no `gh` on host |
| [multi-server-deployment.md](multi-server-deployment.md) | EN | Per-environment VPS settings in `.env.platform` |
| [user-experience.md](user-experience.md) | RU | Journeys: first setup, MR preview, daily work |
| [debian-wireguard-client.ru.md](debian-wireguard-client.ru.md) | RU | Debian/GNOME: permanent WireGuard via NetworkManager |
| [assets/banner.png](assets/banner.png) | — | README / social preview image |
| [github-workflow.md](github-workflow.md) | EN | Branches, CI workflows, Releases |
| [stands-on-one-vps.md](stands-on-one-vps.md) | EN | dev / test / MR stands, DNS, ports, GitHub variables |
| [server-wizard-user-guide.ru.md](server-wizard-user-guide.ru.md) | RU | Launchpad-first; wizard script CI-only |
| [ROADMAP.md](ROADMAP.md) | EN | Planned work |

## Recommended reading order

1. **[deploy-ssh-key.md](deploy-ssh-key.md)** — create deploy key (`-N ''`), then **[launchpad.md](launchpad.md)**.
2. **[user-experience.md](user-experience.md)** — how day-to-day development feels.
3. **[stands-on-one-vps.md](stands-on-one-vps.md)** — DNS wildcard and UDP firewall after launchpad.
4. **[github-workflow.md](github-workflow.md)** — when you need CI/workflow details.
