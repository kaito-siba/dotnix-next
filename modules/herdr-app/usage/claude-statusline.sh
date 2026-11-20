#!/bin/sh
# Claude Code の statusLine に挟む。stdin の JSON から subscription の利用上限 (rate_limits) だけを file に書き、同じ JSON を本来の statusLine の command に渡す
#   使い方: herdr-usage-statusline <本来の command> [引数...]
# file は herdr-app の下端の bar (../mods/limit-status) が読む。形は ./codex.py が出す物と同じで、at と resets_at は unix 秒
# 書く先は $HERDR_USAGE_FILE で、空なら書かない。sbx の sandbox の中では、host から見える mount の下を指させる。sandbox には写して置き、Debian の dash で走る
# statusLine を消さないよう、読めない時も書けない時も、本来の command は必ず走らせる

input=$(cat)
out=${HERDR_USAGE_FILE:-}
# shellcheck disable=SC2016 # $mins は jq の変数
filter='
  def window($mins):
    if type == "object" and (.used_percentage | type) == "number" and (.resets_at | type) == "number"
    then {mins: $mins, used: .used_percentage, resets_at: .resets_at} else empty end;
  .rate_limits | objects
  | {at: (now | floor), windows: [(.five_hour | window(300)), (.seven_day | window(10080))]}
  | select(.windows != [])
'
if [ -n "$out" ]; then
  # 読む側が書きかけを読まないよう、隣に書いてから rename する。pid を付けて、同時に走る他の session と取り合わない
  tmp="$out.$$"
  if { [ -d "${out%/*}" ] || mkdir -p "${out%/*}"; } 2>/dev/null \
    && printf '%s' "$input" | jq -c "$filter" 2>/dev/null >"$tmp" && [ -s "$tmp" ]; then
    mv -f "$tmp" "$out" 2>/dev/null
  fi
  rm -f "$tmp" 2>/dev/null
fi

# $(cat) が末尾の改行を落とし、here document が 1 つ足す
exec "$@" <<EOF
$input
EOF
