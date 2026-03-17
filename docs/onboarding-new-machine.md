# Onboarding a New Machine

This document describes how to bring a new machine into my standard environment. It is structured as a prompt context for an LLM (Claude) to generate detailed, step-by-step checklists.

When you say:

> "Generate an onboarding checklist for a new \<platform\> machine"

Claude should:

1. Fetch `https://raw.githubusercontent.com/89jobrien/dotfiles/main/README.md` as the primary reference for exact commands.
2. Use this document as the structural guide.
3. Ask any clarifying questions (personal vs work vs lab, secrets or no, workstation or lab/server for Tailscale role, etc.).
4. Output a numbered checklist you can literally work through in order.

---

## 1. Prerequisites

- Git is installed (or can be installed with the system package manager).
- Shell access to the machine (local or SSH).
- An [`age`](https://github.com/FiloSottile/age) key for [SOPS](https://github.com/getsops/sops) secrets (or the ability to create one).
- Platform is known:
  - macOS laptop/desktop.
  - Linux (desktop, server, or WSL).
  - Windows (for [NixOS-WSL](https://github.com/nix-community/NixOS-WSL) bootstrap).

> **Claude:** first, confirm the platform and whether this machine is **personal**, **work**, or **lab**, then tailor the checklist.

## 2. Clone and bootstrap dotfiles

High-level flow (exact commands may differ per OS):

1. Clone the repo into the expected location (usually `~/dotfiles` or as defined in the README).
2. Run the bootstrap script:
   - `./install.sh` on Unix-like systems.
   - `./install.ps1` in PowerShell on Windows.
3. Let the bootstrap:
   - Install [Homebrew](https://brew.sh) / [winget](https://learn.microsoft.com/en-us/windows/package-manager/winget/) / [Nix](https://nixos.org/download/) (as appropriate).
   - Install core packages from Brewfile and/or Nix flake.
   - Set up `.mise.toml`, `Justfile`, `Makefile`, and symlink dotfiles via [stow](https://www.gnu.org/software/stow/).

> **Claude:** generate the exact commands for the detected OS, and note anywhere the README expects environment variables or flags.

## 3. Run core tasks

After bootstrap, run ([mise docs](https://mise.jdx.dev/)):

- `mise run doctor` – sanity checks on the environment.
- `mise run drift` – check for config drift or missing pieces.
- `mise run stow` – ensure symlinks are in place.
- `mise run post` – post-setup hooks (shell, macOS tweaks, dev tools, etc.).
- `mise run test` – optional, runs the automated test suite.

> **Claude:** turn this into a checklist with checkboxes and, if needed, OS-specific notes.

## 4. Secrets and environment

Secrets and environment are handled via [SOPS](https://github.com/getsops/sops) and env layering:

- Decrypt SOPS files (if this machine is allowed to hold secrets):
  - Ensure the `age` key is installed in the correct location.
  - Run the appropriate `mise run` or helper script to decrypt env files in `secrets/`.
- Verify:
  - `.mise.toml` and `mise.local.toml` are in place.
  - Encrypted env files have been decrypted to their expected locations.

> **Claude:** ask whether this machine should hold real secrets (yes/no) and adjust instructions accordingly (e.g., skip decryption on throwaway or demo machines).

## 5. Platform-specific follow-ups

- **macOS**:
  - Confirm Xcode Command Line Tools are installed.
  - Run any macOS-specific `mise run` tasks (e.g., macOS defaults, GUI apps, fonts).
- **Linux**:
  - Confirm system packages (graphics, dev headers) are installed.
  - Optional: configure systemd user services for always-on tools, if defined.
- **Windows ([NixOS-WSL](https://github.com/nix-community/NixOS-WSL))**:
  - Ensure [WSL](https://learn.microsoft.com/en-us/windows/wsl/install) is installed.
  - Run the PowerShell bootstrap to install NixOS-WSL.
  - Apply `nixos/` and `home.nix` configs.

> **Claude:** based on the platform, extend this section into a concrete, ordered checklist.

## 6. Verification

- Shell:
  - Open a new terminal and verify the prompt, aliases, and functions are loaded.
- Tools:
  - `mise run doctor` passes.
  - Key tools (Rust, uv, Bun/Node, Docker/Colima, kubectl, etc.) are on `PATH`.
- Editors:
  - Zed and Neovim start with the expected configs.
- Git:
  - Global git config (name, email, signing) is correct.

> **Claude:** generate a quick "smoke test" list of commands to run and what output to expect.

## 7. Tailscale setup and roles

Tailscale is part of the default environment. Run this section after core dotfiles bootstrap.

### 7.1 Install Tailscale

- macOS:
  - Prefer the **Standalone** Tailscale app from [Tailscale's download page](https://tailscale.com/download/mac) (not the App Store). See [macOS variants](https://tailscale.com/kb/1065/macos-variants).
  - Do **not** install both Standalone and App Store variants at the same time.
- Linux:
  - Use the [official install script](https://tailscale.com/download/linux) or distro packages from [Tailscale's Linux docs](https://tailscale.com/kb/1031/install-linux).
- Windows:
  - Install the [official Windows client](https://tailscale.com/download/windows) from Tailscale's download page (outside WSL).

> **Claude:** detect the OS and generate the exact install commands or steps from the official docs.

### 7.2 Authenticate and join tailnet

- Start Tailscale and log in to the existing tailnet.
- Verify the device appears in the admin UI and has a 100.x tailnet IP.
- Give the machine a clear device name:
  - `m5-max` for the main MacBook Pro.
  - `m1-lab` for the always-on lab Mac.
  - For new machines, follow the pattern `<model>-<role>`.

> **Claude:** include a "confirm device shows up in admin console" checklist item.

### 7.3 Assign machine role

- **Workstation** (interactive dev):
  - Example: `m5-max`.
  - Needs easy access to other tailnet services.
  - Typically **not** an exit node.
- **Lab/Server** (always-on):
  - Example: `m1-lab`.
  - May run services (Jupyter, MLflow, agents, dashboards).
  - May be configured as an **exit node**.

> **Claude:** ask "Is this workstation or lab/server?" and then generate role-specific tasks.

### 7.4 Configure exit node / services (lab machines only)

- Enable **exit node** (if desired) and authorize it in the admin console.
- Decide which services to expose over Tailscale (Jupyter, MLflow, TensorBoard, agent APIs).
- Standardize URLs and ports for services (e.g. `http://100.x.x.x:8888` for Jupyter).

> **Claude:** when the role is "lab", add tasks to turn on exit node (with admin approval step) and list/standardize key service URLs.

### 7.5 Documentation updates

After Tailscale is onboarded, update the vault:

- `Machines - Overview.md` — device name, role, OS, tailnet IP, exit node status, key services.
- `Tailscale - Topology.md` — reflect the new machine and any new services.

> **Claude:** generate the snippets needed to update these notes.
