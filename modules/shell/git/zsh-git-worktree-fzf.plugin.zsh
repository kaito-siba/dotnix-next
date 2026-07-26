# 依存: git (worktree対応), fzf
# 使い方:
#   - gtwcd        : 現在のGitリポジトリのworktree一覧をfzfで選んでcd
#   - Ctrl-t       : その場でfzf起動→選択→cd（ZLEウィジェット）

: ${CUSTOM_FZF_OPTS:="--height=40% --reverse --border"}
: ${CUSTOM_WT_PREVIEW:='
  p="{}"
  # READMEプレビュー（20行）
  for f in README.md README README.MD Readme.md readme.md readme; do
    if [ -f "$p/$f" ]; then
      echo "# README: $f"
      head -n 20 "$p/$f"
      echo
      break
    fi
  done
  # ブランチ/HEADと直近ログ
  git -C "$p" rev-parse --abbrev-ref HEAD 2>/dev/null | sed "s/^/HEAD: /"
  git -C "$p" remote -v 2>/dev/null
  echo
  git -C "$p" --no-pager log --oneline -n 10 2>/dev/null
'}

# ---- 内部ヘルパ ----

# 現リポジトリの worktree パス一覧を出力（1行=絶対パス）
_git_worktree_list_paths() {
  # porcelainは "worktree <path>" 形式で出る
  git worktree list --porcelain 2>/dev/null | awk '
    $1 == "worktree" { $1=""; sub(/^ /,""); print $0 }
  '
}

# 任意のGitリポジトリrootを受け取り worktree を列挙
_git_worktree_list_paths_in_repo() {
  local repo="$1"
  git -C "$repo" worktree list --porcelain 2>/dev/null | awk '
    $1 == "worktree" { $1=""; sub(/^ /,""); print $0 }
  '
}

# ---- ユーザー向けコマンド ----

# 現在のリポジトリ内で worktree を選んで cd
gtwcd() {
  # いまがGit管理下でなければ上に辿ってrootを探す
  local repo
  repo="$(git rev-parse --show-toplevel 2>/dev/null)" || {
    print -r -- "git管理下じゃない。まずリポジトリに入れ、とな。"; return 1
  }

  local target
  target="$(_git_worktree_list_paths | fzf ${=CUSTOM_FZF_OPTS} \
            --prompt='worktree> ' \
            --preview="${CUSTOM_WT_PREVIEW}" \
            --preview-window=down:60%:wrap)" || return

  [[ -n "$target" && -d "$target" ]] && builtin cd -- "$target"
}

# ZLEウィジェット（Ctrl-tで即起動→選択→cd）
_git_worktree_widget() {
  local target
  target="$(_git_worktree_list_paths | fzf ${=CUSTOM_FZF_OPTS} \
            --prompt='worktree> ' \
            --preview="${CUSTOM_WT_PREVIEW}" \
            --preview-window=down:60%:wrap)" || return
  if [[ -n "$target" && -d "$target" ]]; then
    LBUFFER="cd -- ${(q)target}"
    zle accept-line
  fi
}
zle -N git-worktree-fzf _git_worktree_widget
bindkey -M emacs '^t' git-worktree-fzf 2>/dev/null
bindkey -M vicmd '^t'  git-worktree-fzf 2>/dev/null
bindkey -M viins '^t'  git-worktree-fzf 2>/dev/null

# 補助エイリアス
alias gtw='gtwcd'
