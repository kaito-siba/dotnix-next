{
  # herdr-core (hc) だけを入れる。GUI の要らない machine 向け: ssh で入れる
  # ようにしておけば、手元の herdr-app から `hc machine add <host>` で繋いで、
  # その machine の上で端末やエージェントを動かせる。
  # desktop app も使う machine は herdr-app の方を入れる。そちらが同じ core を
  # 入れるので、両方は要らない。
  flake.modules.homeManager.herdr-core =
    { pkgs, ... }:
    {
      home.packages = [ (pkgs.callPackage ./_core.nix { }) ];
    };
}
