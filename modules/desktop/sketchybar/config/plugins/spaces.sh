#!/bin/sh

source "$HOME/.config/sketchybar/colors.sh"
source "$HOME/.config/sketchybar/icons.sh"

SPACE_ICONS=("$GHOST" "$GHOST" "$GHOST" "$GHOST" "$GHOST" "$GHOST" "$GHOST" "$GHOST" "$GHOST")
CURRENT_SPACE_ICONS=("$WORK" "$BROWSER" "$UNI" "$MUSIC" "$MAIL" "$GENERAL" "$GENERAL" "$GENERAL" "$GENERAL")

# OmniWM's virtual workspaces are named "1".."9"; tr guards against the query
# growing decoration around the name. Bail quietly while OmniWM is not up.
ACTIVE_SPACE=$(omniwmctl query active-workspace --fields name --format tsv 2>/dev/null | tail -n1 | tr -cd '0-9')
[ -z "$ACTIVE_SPACE" ] && exit 0

space_bg=(
  background.color=$SPACEBG
  background.height=19
  background.corner_radius=50
)

for i in "${!SPACE_ICONS[@]}"; do
  sid=$(($i + 1))

  if [[ $sid -eq $ACTIVE_SPACE ]]; then
    CURRENT_ICON=$PACMAN
    sketchybar --set space.$sid "${space_bg[@]}"
  else
    CURRENT_ICON=${SPACE_ICONS["$i"]}
    sketchybar --set space.$sid background.color=$TRANSPARENT
  fi

  sketchybar --set space.$sid icon="$CURRENT_ICON"
  sketchybar --set current_space icon=${CURRENT_SPACE_ICONS[$(($ACTIVE_SPACE - 1))]}
done
