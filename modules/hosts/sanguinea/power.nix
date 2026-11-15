{
  # Laptop power management: battery state for noctalia and power profiles.
  flake.modules.nixos."hosts/sanguinea" =
    { pkgs, ... }:
    {
      services.upower.enable = true;
      services.power-profiles-daemon.enable = true;

      # エージェント常駐機としてクラムシェルで運用するので、蓋を閉じても suspend しない。
      # 内蔵パネルは niri が蓋に合わせて消す。
      services.logind.settings.Login = {
        HandleLidSwitch = "ignore";
        HandleLidSwitchExternalPower = "ignore";
        HandleLidSwitchDocked = "ignore";
      };

      # AC 繋ぎっぱなしになるので、バッテリー保護のため充電を 80% で止める。
      # 閾値は機種によって再起動や resume で戻るので、その都度書き直す。
      # sysfs の属性はベンダドライバが後から生やすことがあり、udev rule だと間に合わない。
      systemd.services.battery-charge-threshold = {
        description = "Limit battery charging to 80%";
        wantedBy = [
          "multi-user.target"
          "post-resume.target"
        ];
        after = [ "post-resume.target" ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = pkgs.writeShellScript "battery-charge-threshold" ''
            found=0
            for f in /sys/class/power_supply/BAT*/charge_control_end_threshold; do
              [ -e "$f" ] || continue
              echo 80 > "$f" && found=1
            done
            if [ "$found" = 0 ]; then
              echo "charge_control_end_threshold is not available on this machine" >&2
            fi
          '';
        };
      };
    };
}
