{
  lib,
  writeShellApplication,
  jq,
  python3,
  # herdr-usage-statusline が書く file
  claudeFile,
}:
# herdr-app の下端の bar (./mods/limit-status) に出す、Claude Code と Codex の利用上限を取ってくる物。
{
  # Claude Code の statusLine に挟む (./usage/claude-statusline.sh)。~/.claude/settings.json は
  # nix で書いていないので、statusLine の command には手で足す。入れる前の machine でも
  # statusLine が出るよう、PATH に無ければ挟まずに本来の command を走らせる:
  #   STARSHIP_CONFIG=... $(command -v herdr-usage-statusline) cship
  statusline = writeShellApplication {
    name = "herdr-usage-statusline";
    runtimeInputs = [ jq ];
    # errexit で途中で抜けると、本来の statusLine が出なくなる
    bashOptions = [ ];
    # sandbox にはこの script をそのまま写すので、書く先は外から渡す。
    text = ''
      HERDR_USAGE_FILE=''${HERDR_USAGE_FILE:-${claudeFile}}
    ''
    + lib.removePrefix "#!/bin/sh\n" (builtins.readFile ./usage/claude-statusline.sh);
  };

  # Codex の利用上限を codex app-server に訊く (./usage/codex.py)。codex は PATH の物を使い、
  # 無い machine では何も出さない。
  codex = writeShellApplication {
    name = "herdr-usage-codex";
    text = ''
      exec ${python3}/bin/python3 -I ${./usage/codex.py} "$@"
    '';
  };
}
