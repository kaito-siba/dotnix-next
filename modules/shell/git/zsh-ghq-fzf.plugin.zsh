# zsh-ghq-fzf.plugin.zsh

# 依存: ghq, fzf
# 使い方:
#   - コマンド: ghqcd         -> fzfで選んでcd
#   - ウィジェット: Ctrl-g    -> fzf起動して選んだらその場でcd

# fzfのデフォルトオプションを軽く整える
: ${CUSTOM_FZF_OPTS:="--height=60% --reverse --border"}
: ${CUSTOM_FZF_PREVIEW:="
  if [[ -f {}/README.md ]]; then
    head -n 50 {}/README.md
  elif [[ -f {}/README ]]; then
    head -n 50 {}/README
  else
    git -C {} remote -v
    echo
    git -C {} --no-pager log --oneline -n 10 2>/dev/null
  fi
"}

# コマンド版（関数呼び出しでそのままディレクトリを移動）
ghqcd() {
  local dir
  dir="$(ghq list --full-path | fzf ${=CUSTOM_FZF_OPTS} \
        --preview="${CUSTOM_FZF_PREVIEW}" \
        --preview-window=down:60%:wrap)" || return
  [[ -n "$dir" && -d "$dir" ]] && builtin cd -- "$dir"
}

# ZLEウィジェット版（キーで即起動・即移動）
_ghq_fzf_widget() {
  local dir
  dir="$(ghq list --full-path | fzf ${=CUSTOM_FZF_OPTS} \
        --preview="${CUSTOM_FZF_PREVIEW}" \
        --preview-window=down:60%:wrap)" || return
  if [[ -n "$dir" && -d "$dir" ]]; then
    LBUFFER="cd -- ${(q)dir}"
    zle accept-line
  fi
}
zle -N ghq-fzf _ghq_fzf_widget

# デフォルトのキー割り当て（Ctrl-g）。
bindkey -M emacs '^g' ghq-fzf 2>/dev/null
bindkey -M vicmd '^g' ghq-fzf 2>/dev/null
bindkey -M viins '^g' ghq-fzf 2>/dev/null

# エイリアスも一応
alias gq='ghqcd'
