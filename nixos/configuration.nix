{ config, pkgs, lib, ... }:

{
  system.stateVersion = "24.05";

  # ── WSL integration ───────────────────────────────────────────────────────
  wsl = {
    enable = true;
    defaultUser = "nixos";
    # Start in the user's home directory, not /mnt/c/...
    startMenuLaunchers = true;
  };

  # ── Nix settings ─────────────────────────────────────────────────────────
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    # Trim old generations automatically
    auto-optimise-store = true;
  };

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };

  # ── System packages (minimal — user env managed by home-manager) ──────────
  environment.systemPackages = with pkgs; [
    git   # needed before home-manager bootstraps
    curl
    wget
  ];

  # ── Shell ─────────────────────────────────────────────────────────────────
  programs.zsh.enable = true;

  users.users.nixos = {
    isNormalUser = true;
    shell = pkgs.zsh;
    extraGroups = [ "wheel" ];
  };

  # Passwordless sudo for wheel (WSL convenience)
  security.sudo.wheelNeedsPassword = false;

  # ── Locale / timezone ─────────────────────────────────────────────────────
  time.timeZone = "America/New_York";  # adjust as needed

  i18n.defaultLocale = "en_US.UTF-8";
}
