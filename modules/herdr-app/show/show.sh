# herdr-app の Show パネル (mods/show) に物を置くコマンド。
# パネルは $app_home/show/items を見ているだけなので、ここが唯一の書き手。
# 画像は app の asset loader が app home の外を読めない (symlink も辿らない)
# ので、必ず実体をコピーする。

app_home=${HERDR_APP_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/herdr-app}
items=$app_home/show/items

usage() {
  cat <<'USAGE'
usage: show [-n] <file>...     Show パネルにファイルを送る (-n: パネルを開かない)
       show --list             送られた物を JSON で出す
       show --bake <id> <marks-json>
                               注釈を焼き込んだコピーを作る (パネルが呼ぶ)
       show --rm <id>...       消す (注釈付きコピーも一緒に消える)
       show --clear            全部消す
       show --dir              置き場のパスを出す
USAGE
}

new_id() {
  # 並び順 = 時刻順になるよう、ミリ秒の時刻を頭に置く。
  printf '%s-%04x' "$(date +%s%3N)" "$((RANDOM % 65536))"
}

# 画像なら "幅 高さ" を出す。GPUI が読めない形式や壊れた物は空。
dimensions() {
  case "${1##*.}" in
    png | PNG | jpg | JPG | jpeg | JPEG | gif | GIF | webp | WEBP | bmp | BMP | svg | SVG)
      magick identify -format '%w %h\n' "${1}[0]" 2>/dev/null | head -n 1 || true
      ;;
  esac
}

# 文字の注釈に使うフォント。ImageMagick の既定フォントは日本語を持たないので、
# fontconfig の既定の sans を引く。
font() {
  if [ -n "${SHOW_FONT:-}" ]; then
    printf '%s' "$SHOW_FONT"
  else
    fc-match -f '%{file}' 'sans:bold' 2>/dev/null || true
  fi
}

# app が動いていて Show 入りの layout を表示している時だけ、パネルを前に出す。
reveal() {
  command -v herdr-app >/dev/null 2>&1 || return 0
  {
    timeout 2 herdr-app "do" layout.select --stack panel-body --child show \
      && timeout 2 herdr-app "do" layout.show --id panel
  } >/dev/null 2>&1 || true
}

add() {
  local open=1
  if [ "${1:-}" = "-n" ]; then
    open=0
    shift
  fi
  [ "${1:-}" = "--" ] && shift
  if [ $# -lt 1 ]; then
    usage >&2
    exit 2
  fi

  mkdir -p "$items"
  local batch file src name ext id dest dims width height size failed=0
  batch=$(date +%s)
  for file in "$@"; do
    if [ ! -f "$file" ]; then
      printf 'show: %s: ファイルが無い\n' "$file" >&2
      failed=1
      continue
    fi
    src=$(realpath "$file")
    name=$(basename "$src")
    ext=""
    case "$name" in
      *.*) ext=".${name##*.}" ;;
    esac
    id=$(new_id)
    dest=$items/$id$ext
    cp "$src" "$dest"
    chmod u+w "$dest"

    dims=$(dimensions "$dest")
    width=${dims%% *}
    height=${dims##* }
    size=$(stat -c %s "$dest")
    jq -n \
      --arg id "$id" --arg name "$name" --arg file "$id$ext" --arg src "$src" \
      --arg cwd "$PWD" --argjson time "$(date +%s)" --argjson batch "$batch" \
      --argjson size "$size" --arg width "$width" --arg height "$height" \
      '{id: $id, name: $name, file: $file, src: $src, cwd: $cwd, time: $time,
        batch: $batch, size: $size, parent: null,
        width: ($width | tonumber? // null), height: ($height | tonumber? // null)}' \
      >"$items/$id.json.tmp"
    mv "$items/$id.json.tmp" "$items/$id.json"
    printf 'shown: %s\n' "$name"
  done

  [ "$open" -eq 1 ] && reveal
  return "$failed"
}

list() {
  mkdir -p "$items"
  local metas=()
  shopt -s nullglob
  metas=("$items"/*.json)
  shopt -u nullglob
  if [ ${#metas[@]} -eq 0 ]; then
    echo '[]'
    return 0
  fi
  jq -c -s 'sort_by(.id)' "${metas[@]}"
}

# 注釈は 0..1 に正規化した座標で渡ってくるので、元画像の px に戻して描く。
# shape: {type: "pen", color, stroke, points: [[x, y], ...]}
#        {type: "arrow", color, stroke, from: [x, y], to: [x, y]}
#        {type: "text", color, size, at: [x, y], text}
# stroke と size は画像の幅に対する比。
bake() {
  if [ $# -ne 2 ]; then
    usage >&2
    exit 2
  fi
  local id=$1 marks=$2 meta=$items/$1.json
  if [ ! -f "$meta" ]; then
    printf 'show: %s: そんな id は無い\n' "$id" >&2
    exit 1
  fi

  local file width height name
  file=$(jq -r '.file' "$meta")
  width=$(jq -r '.width // empty' "$meta")
  height=$(jq -r '.height // empty' "$meta")
  name=$(jq -r '.name' "$meta")
  if [ -z "$width" ] || [ -z "$height" ]; then
    printf 'show: %s: 画像ではないので注釈を焼けない\n' "$name" >&2
    exit 1
  fi

  local args=()
  mapfile -d '' args < <(
    jq --raw-output0 --argjson w "$width" --argjson h "$height" --arg font "$(font)" '
      def px: [(.[0] * $w | round), (.[1] * $h | round)];
      def pt: "\(.[0]),\(.[1])";
      def sw: ((.stroke // 0.004) * $w) | if . < 1 then 1 else . end | (. * 10 | round) / 10;
      def line($c; $s; $pts):
        ["-fill", "none", "-stroke", $c, "-strokewidth", ($s | tostring),
         "-draw", "stroke-linecap round stroke-linejoin round polyline " + ($pts | map(pt) | join(" "))];
      # ImageMagick は annotate の % と \ と先頭の @ を特別扱いする。
      def literal: gsub("\\\\"; "\\\\") | gsub("%"; "%%") | if startswith("@") then "\\" + . else . end;
      [ .shapes[]
        | (.color // "#ff3b30") as $c
        | if .type == "pen" then
            (.points | map(px)) as $p
            | if ($p | length) == 1 then line($c; sw; $p + $p) else line($c; sw; $p) end
          elif .type == "arrow" then
            (.from | px) as $a | (.to | px) as $b | sw as $s
            | ($b[0] - $a[0]) as $dx | ($b[1] - $a[1]) as $dy
            | (($dx * $dx + $dy * $dy) | sqrt) as $len
            | if $len < 1 then empty else
                ([$s * 6, 18] | max) as $head
                | ($dx / $len) as $ux | ($dy / $len) as $uy
                | (0.9063) as $cos | (0.4226) as $sin
                | [($b[0] - $head * ($ux * $cos - $uy * $sin) | round),
                   ($b[1] - $head * ($uy * $cos + $ux * $sin) | round)] as $l
                | [($b[0] - $head * ($ux * $cos + $uy * $sin) | round),
                   ($b[1] - $head * ($uy * $cos - $ux * $sin) | round)] as $r
                | line($c; $s; [$a, $b]) + line($c; $s; [$l, $b, $r])
              end
          elif .type == "text" then
            (.at | px) as $at
            | (if $font == "" then [] else ["-font", $font] end)
              + ["-gravity", "NorthWest", "-stroke", "none", "-fill", $c,
                 "-pointsize", (((.size // 0.03) * $w) | round | tostring),
                 "-annotate", "+\($at[0])+\($at[1])", (.text | literal)]
          else empty end
      ] | add // [] | .[]' <<<"$marks"
  )

  local ext new out stem marked
  case "$file" in
    *.svg | *.SVG) ext=.png ;;
    *.*) ext=".${file##*.}" ;;
    *) ext=.png ;;
  esac
  new=$(new_id)
  out=$items/$new$ext
  magick "${items}/${file}[0]" "${args[@]}" "$out"

  # foo.png -> foo.marked.png。注釈付きをさらに注釈しても名前は増やさない。
  stem=${name%.*}
  stem=${stem%.marked}
  marked=$stem.marked$ext
  jq --arg id "$new" --arg name "$marked" --arg file "$new$ext" --arg parent "$id" \
    --argjson time "$(date +%s)" --argjson size "$(stat -c %s "$out")" \
    --arg dims "$(dimensions "$out")" \
    '. + {id: $id, name: $name, file: $file, time: $time, size: $size,
          parent: (.parent // $parent), src: null,
          width: ($dims | split(" ")[0] | tonumber? // .width),
          height: ($dims | split(" ")[1] | tonumber? // .height)}' \
    "$meta" >"$items/$new.json.tmp"
  mv "$items/$new.json.tmp" "$items/$new.json"
  jq -c . "$items/$new.json"
}

remove() {
  local id meta child
  for id in "$@"; do
    case "$id" in
      */* | .* | "") continue ;;
    esac
    meta=$items/$id.json
    [ -f "$meta" ] || continue
    shopt -s nullglob
    for child in "$items"/*.json; do
      if [ "$(jq -r '.parent // empty' "$child")" = "$id" ]; then
        rm -f "$items/$(jq -r '.file' "$child")" "$child"
      fi
    done
    shopt -u nullglob
    rm -f "$items/$(jq -r '.file' "$meta")" "$meta"
  done
}

case "${1:-}" in
  -h | --help)
    usage
    ;;
  --list)
    list
    ;;
  --bake)
    shift
    bake "$@"
    ;;
  --rm)
    shift
    remove "$@"
    ;;
  --clear)
    rm -rf "$items"
    mkdir -p "$items"
    ;;
  --dir)
    mkdir -p "$items"
    printf '%s\n' "$items"
    ;;
  *)
    add "$@"
    ;;
esac
