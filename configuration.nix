# NixOS configuration for "myserver"
# ============================================================
# 1. Copy to /etc/nixos/configuration.nix
# 2. Build with: sudo nixos-rebuild switch --rollback-on-failure
# 3. After boot, run: nvidia-smi && docker run ... && sudo tailscale up
# ============================================================

{ config, pkgs, lib, ... }:

{
  imports = [ ./hardware-configuration.nix ];

  # ====================
  # Bootloader
  # ====================
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEFIVariables = true;

  # ====================
  # System identification
  # ====================
  networking.hostName = "myserver";

  # CRITICAL FOR ZFS: Generate yours via `head -c 8 /etc/machine-id`
  networking.hostId = "abcdef12";

  system.stateVersion = "26.05";

  # ====================
  # Timezone & locale
  # ====================
  time.timeZone = "Europe/Stockholm";
  i18n.defaultLocale = "en_US.UTF-8";
  i18n.extraLocaleSettings = {
    LC_ADDRESS        = "sv_SE.UTF-8";
    LC_IDENTIFICATION = "sv_SE.UTF-8";
    LC_MEASUREMENT    = "sv_SE.UTF-8";
    LC_MONETARY       = "sv_SE.UTF-8";
    LC_NAME           = "sv_SE.UTF-8";
    LC_NUMERIC        = "sv_SE.UTF-8";
    LC_PAPER          = "sv_SE.UTF-8";
    LC_TELEPHONE      = "sv_SE.UTF-8";
    LC_TIME           = "sv_SE.UTF-8";
  };

  # ====================
  # X11 + GNOME
  # ====================
  services.xserver.enable = true;
  services.displayManager.gdm.enable = true;
  services.desktopManager.gnome.enable = true;
  services.xserver.xkb = { layout = "us"; variant = ""; };

  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable        = true;
    alsa.enable   = true;
    alsa.support32Bit = true;
    pulse.enable  = true;
  };

  services.printing.enable = true;

  # ====================
  # Powers & Never suspend
  # ====================
  powerManagement.enable = false;

  # Disable idle-based suspend (this is what broadcasts the GDM message)
  services.logind.extraConfig = "IdleAction=none";


  # GNOME desktop does not enter idle mode and never sleeps on power profile
  dconf.settings = {
    "org/gnome/desktop/session" = let
      zeroUint32 = lib.gvariant.makeVariant (lib.gvariant.mkuint32 0);
    in {
      idle-delay = zeroUint32;
    };
    "org/gnome/settings-daemon/plugins/power" = {
      sleep-inactive-ac-type   = "nothing";
      sleep-inactive-battery-type = "nothing";
    };
  };

  # ====================
  # Unfree
  # ====================
  nixpkgs.config.allowUnfree = true;

  # ====================
  # USER & Shells
  # ====================
  programs.zsh.enable = true;
  users.defaultUserShell = pkgs.zsh;
  users.users."pxp" = {
    isNormalUser = true;
    description  = "paul perrine";
    extraGroups  = [ "networkmanager" "wheel" "docker" ];
  };

  # ====================
  # CLI tools & Programs
  # ====================
  environment.systemPackages = with pkgs; [
    git                   # version control
    htop                  # process viewer
    nvtopPackages.nvidia  # Correct package for NVIDIA GPU monitoring
    pv                    # pipe visualization
    mbuffer               # network throughput tool
    tmux                  # terminal multiplexer
    ncdu                  # disk usage analyzer
    yt-dlp                # video/audio downloader
    fzf                   # fuzzy finder
    bat
    veracrypt             # Enabled: encryption (package)
    zfs                   # ZFS CLI tools (zpool, zfs, etc.)
  ];

  programs.firefox.enable = true;
  programs.nix-ld.enable = true;

  # ============================================================
  # Graphics Support (CRITICAL for GDM/GNOME to launch)
  # ============================================================
  hardware.graphics = {
    enable      = true;
    enable32Bit = true; # Highly recommended for steam/compatibility
  };

  # ============================================================
  # NVIDIA driver — PROPRIETARY (recommended for RTX 2080 right now)
  # Switch to "open = true" later when 4080 Super is installed
  # ============================================================
  boot.kernelParams                 = [ "nvidia-drm.modeset=1" ];
  hardware.nvidia                   = {
    modesetting.enable      = true;
    open                    = true;   # Set to true! RTX 3080 fully supports this.
    powerManagement.enable  = false;
    powerManagement.finegrained = false;
    nvidiaSettings          = true;
    package                 = config.boot.kernelPackages.nvidiaPackages.stable;
  };

  services.xserver.videoDrivers = [ "nvidia" ];
  hardware.nvidia-container-toolkit.enable = true;

  # =============================================
  # Docker & Podman
  # =============================================
  virtualisation.docker.enable   = true;
  virtualisation.podman.enable   = true;

  # =============================================
  # Tailscale
  # =============================================
  services.tailscale.enable = true;

  # =============================================
  # ZFS — import existing pool "tank"
  # =============================================
  boot.supportedFilesystems = [ "zfs" ];

  # This tells NixOS to find and auto-import "tank" at boot
  boot.zfs.extraPools       = [ "tank" ];

  services.zfs = {
    autoScrub.enable = true;   # monthly scrub to catch bit-rot
    trim.enable      = true;
  };

  # NOTE: If your pool uses native ZFS mounting (default), leave this
  # block commented out. If you want NixOS to mount it, uncomment this
  # and run `sudo zfs set mountpoint=legacy tank` first.
  #
  # fileSystems = {
  #   "/tank" = {
  #     device     = "tank";
  #     fsType     = "zfs";
  #     neededForBoot = true;
  #   };
  # };

  # =============================================
  # SSH server (key-only, cert-based)
  # =============================================
  services.openssh.enable = true;
  networking.firewall.allowedTCPPorts = [ 22 ];
  services.openssh.settings = {
    PermitRootLogin         = "no";
    PasswordAuthentication  = false;
    KbdInteractiveAuthentication = false;
  };

  services.openssh.extraConfig = ''
    TrustedUserCAKeys /etc/ssh/ca.pub
  '';

  # =============================================
  # Security configuration for VeraCrypt
  # =============================================
  security.sudo.extraConfig = ''
    # Allows users in the wheel group (like pxp) to run the veracrypt binary
    # without a sudo password prompt during volume mounts.
    %wheel ALL=(ALL) NOPASSWD: /run/current-system/sw/bin/veracrypt
  '';
}
