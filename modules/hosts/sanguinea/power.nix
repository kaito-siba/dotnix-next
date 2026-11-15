{
  # Laptop power management: battery state for noctalia and power profiles.
  flake.modules.nixos."hosts/sanguinea" = {
    services.upower.enable = true;
    services.power-profiles-daemon.enable = true;

    # エージェント常駐機としてクラムシェルで運用するので、蓋を閉じても suspend しない。
    # 内蔵パネルは niri が蓋に合わせて消す。
    services.logind.settings.Login = {
      HandleLidSwitch = "ignore";
      HandleLidSwitchExternalPower = "ignore";
      HandleLidSwitchDocked = "ignore";
    };

    # 充電上限 (80% など) は設定していない: この機種 (Chuwi CoreBook Air) には
    # charge_control_end_threshold も BIOS の設定項目も無い。
  };
}
