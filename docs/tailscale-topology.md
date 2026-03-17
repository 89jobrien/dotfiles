# Tailnet Topology

> **Sensitive data** (tailnet name, IPs, hostnames) is stored encrypted in `secrets/.env.sops.json`.
> Decrypt with: `sops decrypt secrets/.env.sops.json`

## Roles

### m5-max

- Primary development environment.
- Accesses other devices via tailnet URLs.

### jobrien-vm

- Linux VM — dev environment and remote AI workloads.

### m1-air

- MacBook Air — spare, being given away.

### mac-mini

- Remote Mac Mini (rented) — dev environment, used for work.

## Access Patterns

- Services on tailnet: `http://<hostname>.<tailnet>:<port>` or `http://<tailnet-ip>:<port>`
- Retrieve hostnames and IPs from 1Password item above.

## Conventions

- All internal dashboards and APIs are reachable only over Tailscale.
- Obsidian notes store tailnet URLs to services as canonical links.
