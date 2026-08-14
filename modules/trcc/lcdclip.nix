{
  # Source-side framing for the Trofeo Vision 9.16 LCD, the home half of the
  # `trcc` module.
  #
  # TRCC's exporter resizes with a bare `-s 1920x462` and nothing else
  # (services/video_export.py) — no letterbox, no crop, no aspect handling —
  # so a 16:9 source arrives vertically squashed. The framing has to happen
  # before TRCC sees the file, which is the whole point of lcdclip: decide
  # *how* 16:9 collapses into 4.16:1, then hand over something TRCC only has
  # to re-encode.
  #
  # 1920x462 rather than the 1920x480 printed on the product page.
  # core/registry.py pins 0416:5408 to (1920, 462) on the authority of the
  # decompiled Windows app's explicit `is1920x462` branch, and the panel
  # drawing agrees: a 225.86 x 54.04mm active area is 4.1795:1, which is
  # 1920/462 (4.1558) and not 1920/480 (4.0) — at 480 rows the image would
  # overhang the bezel opening by 2.4mm.
  #
  # 24 fps because _EXPORT_FPS is hardcoded and no CLI flag reaches it.
  # Anything else just gets frame-duplicated on the way into the .zt.
  #
  # Output is mp4, never GIF. Every input ends up as per-frame JPEG inside
  # the .zt, so a GIF's palette quantisation is a lossy step that buys
  # nothing and whose dither noise then costs the JPEG stage extra bits.
  flake.modules.homeManager.trcc =
    { pkgs, ... }:
    let
      lcdclip = pkgs.writeShellApplication {
        name = "lcdclip";

        runtimeInputs = with pkgs; [
          ffmpeg
          coreutils
          gawk
        ];

        text = ''
          usage() {
            cat <<'USAGE'
          usage: lcdclip [-m mode] [-y pos] [-s start] [-t dur] [-q crf] [-o out] <input>...

            Trofeo Vision 9.16 LCD 用に 1920x462 / 24fps の mp4 を作る。
            出来たものは trcc display load-video にそのまま渡せる。

              -m  レイアウト     band | pan | blur | triptych   (default band)
              -y  縦位置         band: 0.0-1.0                  (default 0.5)
                                 pan : A:B                      (default 0:1)
              -s  開始位置 (秒)  各入力の -ss                    (default 0)
              -t  尺 (秒)        出力の -t                       (default 最後まで)
              -q  x264 の crf                                    (default 18)
              -o  出力先                                         (default <input>.lcd.mp4)

            band      1080 のうち 462 の帯を抜く。-y で縦位置を決める
            pan       その帯を -y の A から B へ縦に動かす
            blur      全体を高さ 462 に収め、左右をぼかしで埋める
            triptych  入力 3 つを 640x462 ずつ横に並べる

            尺の上限は 300s (TRCC の _MAX_DURATION_MS)。ただし .zt は
            フレーム間圧縮が無いので実用は 5-15s のループ。
          USAGE
          }

          # パネルの実解像度。registry.py の native_resolution と一致させる
          W=1920
          H=462
          FPS=24

          mode=band
          ypos=
          start=
          dur=
          crf=18
          output=

          while getopts ':m:y:s:t:q:o:h' opt; do
            case "$opt" in
              m) mode=$OPTARG ;;
              y) ypos=$OPTARG ;;
              s) start=$OPTARG ;;
              t) dur=$OPTARG ;;
              q) crf=$OPTARG ;;
              o) output=$OPTARG ;;
              h) usage; exit 0 ;;
              *) usage >&2; exit 2 ;;
            esac
          done
          shift $((OPTIND - 1))

          case "$mode" in
            band|pan|blur) want=1 ;;
            triptych)      want=3 ;;
            *) echo "lcdclip: 未知のモード: $mode" >&2; usage >&2; exit 2 ;;
          esac

          if [ $# -ne "$want" ]; then
            echo "lcdclip: -m $mode は入力を $want 個取ります (given: $#)" >&2
            exit 2
          fi

          output=''${output:-''${1%.*}.lcd.mp4}

          probe_duration() {
            ffprobe -v error -show_entries format=duration \
              -of default=nw=1:nk=1 "$1"
          }

          # 4.16:1 に「はみ出す側だけ」を削るクロップ。16:9 なら縦が余るので
          # h 側の min が効き、逆に元がもっと横長なら w 側が効く。x/y は w/h の
          # 後に評価されるので ow/oh を参照できる。
          cover="w=min(iw\,ih*$W/$H):h=min(ih\,iw*$H/$W):x=(iw-ow)/2"

          vf=
          fc=

          case "$mode" in
            band)
              band_y=''${ypos:-0.5}
              vf="crop=$cover:y=(ih-oh)*$band_y,scale=$W:$H:flags=lanczos,setsar=1"
              ;;

            pan)
              pan=''${ypos:-0:1}
              case "$pan" in
                *:*) pan_a=''${pan%%:*}; pan_b=''${pan##*:} ;;
                *) echo "lcdclip: -m pan の -y は A:B 形式です (例: -y 0:1)" >&2; exit 2 ;;
              esac

              # t は -ss 適用後の出力タイムライン基準なので、尺は
              # -t があればそれ、無ければ (全体 - 開始位置)
              if [ -n "$dur" ]; then
                span=$dur
              else
                span=$(awk -v a="$(probe_duration "$1")" -v b="''${start:-0}" \
                  'BEGIN { printf "%.3f", a - b }')
              fi

              # crop の x/y は常にフレーム毎評価なので eval オプションは無い
              # (scale や pad と違うところ)。t を書けばそのまま動く
              vf="crop=$cover:y=(ih-oh)*($pan_a+($pan_b-$pan_a)*min(1\,t/$span)),scale=$W:$H:flags=lanczos,setsar=1"
              ;;

            blur)
              # 背景は同じフレームを increase で埋めてからクロップしてぼかす。
              # 少し暗く落とすのは、上に載る TRCC のセンサー文字を読ませるため
              fc="[0:v]split=2[bg][fg];"
              fc="''${fc}[bg]scale=$W:$H:force_original_aspect_ratio=increase:flags=lanczos,crop=$W:$H,gblur=sigma=40,eq=brightness=-0.15[b];"
              fc="''${fc}[fg]scale=$W:$H:force_original_aspect_ratio=decrease:flags=lanczos[f];"
              fc="''${fc}[b][f]overlay=(W-w)/2:(H-h)/2,setsar=1"
              ;;

            triptych)
              # 1920/3 = 640。640x462 は約 1.385:1 でほぼアカデミー比なので
              # 顔のアップを 3 枚並べるとちょうど収まる
              tw=$((W / 3))
              one="scale=$tw:$H:force_original_aspect_ratio=increase:flags=lanczos,crop=$tw:$H,setsar=1"
              fc="[0:v]''${one}[a];[1:v]''${one}[b];[2:v]''${one}[c];[a][b][c]hstack=inputs=3,setsar=1"
              ;;
          esac

          args=(-hide_banner -loglevel warning -y)
          for f in "$@"; do
            # -ss は入力側に置く (シークが速く、出力の t が 0 始まりになる)
            if [ -n "$start" ]; then
              args+=(-ss "$start")
            fi
            args+=(-i "$f")
          done

          if [ -n "$fc" ]; then
            args+=(-filter_complex "$fc")
          else
            args+=(-vf "$vf")
          fi

          if [ -n "$dur" ]; then
            args+=(-t "$dur")
          fi

          if [ "$mode" = triptych ]; then
            args+=(-shortest)
          fi

          # 音声は LCD に出ないので落とす。crf は TRCC が JPEG に振り直す前の
          # 中間なので、切り詰めずに素材を保つ側に振っておく
          args+=(
            -r "$FPS" -an
            -c:v libx264 -crf "$crf" -preset slow -pix_fmt yuv420p
            -movflags +faststart
            "$output"
          )

          ffmpeg "''${args[@]}"

          out_dur=$(probe_duration "$output")
          frames=$(awk -v d="$out_dur" -v f="$FPS" 'BEGIN { printf "%d", d * f }')

          # .zt はフレーム間圧縮が無く JPEG を並べるだけなので、TRCC と同じ
          # -q:v 5 で 1 秒ごとに抜いた平均からサイズを見積もれる
          sample=$(mktemp -d)
          trap 'rm -rf "$sample"' EXIT
          ffmpeg -hide_banner -loglevel error -y -i "$output" \
            -vf fps=1 -f image2 -q:v 5 "$sample/%04d.jpg"

          shopt -s nullglob
          jpgs=("$sample"/*.jpg)
          count=''${#jpgs[@]}

          printf '%s (%s)\n' "$output" "$(du -h "$output" | cut -f1)"

          if [ "$count" -gt 0 ]; then
            bytes=$(du -sb "$sample" | cut -f1)
            est=$(( bytes * frames / count ))
            printf '  %dx%d %dfps / %d frames / .zt 見込み %d MB\n' \
              "$W" "$H" "$FPS" "$frames" "$(( est / 1000000 ))"
          fi

          if awk -v d="$out_dur" 'BEGIN { exit !(d > 300) }'; then
            echo "  警告: 300s を超えています。TRCC が書き出しを拒否します" >&2
          elif awk -v d="$out_dur" 'BEGIN { exit !(d > 30) }'; then
            echo "  注意: .zt が肥大します。5-15s のループを推奨" >&2
          fi

          # -e を省くと probe 失敗時に先頭 10s だけになるので明示して出す
          printf '  trcc display load-video -s 0 -e %d 0416:5408 %s\n' \
            "$(awk -v d="$out_dur" 'BEGIN { printf "%d", d * 1000 }')" "$output"
        '';
      };
    in
    {
      home.packages = [ lcdclip ];
    };
}
