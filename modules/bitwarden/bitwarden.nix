{
  # Bitwarden の SSH キーで ssh するための道具。desktop app の SSH agent は使わず、vault の鍵を今動いている SSH agent に載せる
  flake.modules.nixos.bitwarden = {
    # bw-ssh-add が鍵を載せる先の agent。gnome-keyring を有効にすると既定で付いてくるが、それに依存しないようここでも宣言する
    services.gnome.gcr-ssh-agent.enable = true;
  };

  flake.modules.homeManager.bitwarden =
    { pkgs, ... }:
    let
      bw-ssh-add = pkgs.writeShellApplication {
        name = "bw-ssh-add";

        runtimeInputs = with pkgs; [
          bitwarden-cli
          jq
          openssh
        ];

        text = ''
          # agent が鍵を手放すまでの時間。手放した後の ssh は prompt を出さずに publickey で落ちるので、もう一度叩く
          lifetime=''${1:-12h}

          # session key は export しない。script を抜けると、他の bw からは locked に見える
          session=$(bw unlock --raw)
          bw sync --session "$session" >/dev/null

          # ssh_config で IdentitiesOnly yes と IdentityFile <.pub> を組むと、agent の鍵からその 1 本だけを出す。agent の鍵が多いと、全部出して MaxAuthTries で切られる
          # ファイル名はアイテム名。vault でアイテム名を変えたら IdentityFile も合わせる
          pubdir=$HOME/.ssh/bw
          install -d -m 700 "$pubdir"
          # vault から消えた鍵の .pub を残さない
          rm -f "$pubdir"/*.pub

          found=0
          while read -r item; do
            name=$(jq -r .name <<<"$item")
            jq -r .key <<<"$item" | ssh-add -q -t "$lifetime" -
            jq -r .pub <<<"$item" >"$pubdir/''${name//\//_}.pub"
            printf 'added: %s (%s)\n' "$name" "$lifetime"
            found=$((found + 1))
          done < <(
            # type 5 は SSH キーのアイテム
            bw list items --session "$session" \
              | jq -c '.[] | select(.type == 5) | {name, key: .sshKey.privateKey, pub: .sshKey.publicKey}'
          )

          if [ "$found" -eq 0 ]; then
            echo 'bw-ssh-add: vault に SSH キーのアイテムが無い' >&2
            exit 1
          fi
        '';
      };
    in
    {
      home.packages = [
        bw-ssh-add
        pkgs.bitwarden-cli # bw-ssh-add の前に、ホストごとに bw login しておく
      ];
    };
}
