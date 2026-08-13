{
  # GIF 作成まわり。Linux にまともな GUI の GIF エディタが無いので、
  # 「録画 → カット → エンコード → 最適化」を道具の組み合わせで賄う。
  # 録画自体は gpu-screen-recorder (noctalia の screen_recorder プラグイン) 側。
  flake.modules.homeManager.gif =
    { pkgs, ... }:
    let
      # 動画 -> GIF の定型パイプライン。zsh 関数ではなく実行ファイルにして、
      # 依存を runtimeInputs で固定し shellcheck も通す。
      mp4gif = pkgs.writeShellApplication {
        name = "mp4gif";

        runtimeInputs = with pkgs; [
          ffmpeg
          gifski
          gifsicle
        ];

        text = ''
          usage() {
            cat <<'USAGE'
          usage: mp4gif [-f fps] [-w width] [-q quality] [-l lossy] <input> [output]

            -f  フレームレート                     (default 15)
            -w  横幅 px, アスペクト比は維持        (default 720)
            -q  gifski の品質 1-100                (default 90)
            -l  gifsicle の lossy 値, 0 で最適化なし (default 80)

          output を省略すると input と同じ場所に .gif を作る。
          USAGE
          }

          fps=15
          width=720
          quality=90
          lossy=80

          while getopts ':f:w:q:l:h' opt; do
            case "$opt" in
              f) fps=$OPTARG ;;
              w) width=$OPTARG ;;
              q) quality=$OPTARG ;;
              l) lossy=$OPTARG ;;
              h) usage; exit 0 ;;
              *) usage >&2; exit 2 ;;
            esac
          done
          shift $((OPTIND - 1))

          if [ $# -lt 1 ]; then
            usage >&2
            exit 2
          fi

          input=$1
          output=''${2:-''${input%.*}.gif}

          tmp=$(mktemp --suffix=.gif)
          trap 'rm -f "$tmp"' EXIT

          # gifski はフレームごとに最適パレットを作るので、ffmpeg の
          # palettegen より素直に綺麗になる。間は y4m で繋ぐ。
          ffmpeg -hide_banner -loglevel warning -i "$input" \
            -vf "fps=$fps,scale=$width:-1:flags=lanczos" \
            -f yuv4mpegpipe - \
            | gifski -o "$tmp" --quality "$quality" -

          if [ "$lossy" -gt 0 ]; then
            # --colors 256 が無いと per-frame の local colormap に落ちて
            # 「too many colors」警告が出るうえサイズも膨らむ
            gifsicle -O3 --lossy="$lossy" --colors 256 "$tmp" -o "$output"
          else
            cp "$tmp" "$output"
          fi

          printf '%s (%s)\n' "$output" "$(du -h "$output" | cut -f1)"
        '';
      };
    in
    {
      home.packages = [ mp4gif ] ++ (with pkgs; [
        # 元動画の前後をフレーム単位で詰める GUI。再エンコードしない
        losslesscut-bin

        # mp4 -> GIF。フレームごとに最適パレットを作るので
        # ffmpeg の palettegen より明らかに綺麗
        gifski

        # 出来た GIF の後処理: フレーム削除 / クロップ / リサイズ / 減色
        gifsicle
      ]);
    };
}
