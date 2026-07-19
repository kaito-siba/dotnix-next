{
  flake.modules.nixos.desktop =
    { pkgs, ... }:
    {
      # Full local GUI session: GDM login manager + GNOME desktop.
      services.xserver.enable = true;
      services.displayManager.gdm.enable = true;
      services.desktopManager.gnome.enable = true;

      # Audio stack expected by modern desktop apps.
      security.rtkit.enable = true;
      services.pulseaudio.enable = false;
      services.pipewire = {
        enable = true;
        alsa.enable = true;
        alsa.support32Bit = true;
        pulse.enable = true;
      };

      # Useful baseline GUI tools. Chromium is already managed in home-manager,
      # but Firefox is a sane fallback at the system level.
      programs.firefox.enable = true;

      environment.systemPackages = with pkgs; [
        gnome-tweaks
        wl-clipboard
        xclip
      ];

      # Keep GNOME from pulling a few noisy extras by default.
      environment.gnome.excludePackages = with pkgs; [
        gnome-tour
      ];
    };
}
