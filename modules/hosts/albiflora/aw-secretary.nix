{
  # commitment (自分への約束) はこの常駐機の aw-secretary が集めて持ち、laptop
  # (incarnata) の herdr-app の Inbox からも読み書きする。API (aw-secretary serve)
  # は nix で管理していない: aw-secretary の repo にある
  # deploy/systemd/aw-secretary-serve.service を、user が手で ~/.config/systemd/user
  # に置いて有効にする。他の machine から読ませる node は、aw-secretary の
  # config.toml の [commitments.api] allowed_nodes に書く。
  flake.modules.nixos."hosts/albiflora" = {
    # aw-secretary serve の既定の port。config.toml の [commitments.api] port と揃える
    networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ 8793 ];

    home-manager.users.w963n.herdr-app.commitmentsUrl = "http://127.0.0.1:8793";
  };
}
