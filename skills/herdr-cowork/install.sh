#!/bin/sh
# The --with-skills stage: install the vendored herdr-cowork skill and link it
# for each agent. Sourced by install.sh; not a program of its own.

skill_validate() {
  [ -f skills/herdr-cowork/SKILL.md ] || { echo "skills/herdr-cowork/SKILL.md missing from the repo"; exit 1; }
  return 0
}

skill_decide() {
skill_target_state=""; skill_copy=0; skill_links=""; skill_link_notes=""
skill_home_target="$HOME/.agents/skills/herdr-cowork"
  if [ -L "$skill_home_target" ]; then
    skill_target_state="kept (is a symlink; never touched, even with --yes)"
  elif [ ! -e "$skill_home_target" ]; then
    skill_target_state="install"; skill_copy=1
  elif cmp -s skills/herdr-cowork/SKILL.md "$skill_home_target/SKILL.md"; then
    skill_target_state="up to date"
  elif [ "$YES" = 1 ]; then
    skill_target_state="replace"; skill_copy=1
  else
    skill_target_state="kept (differs; rerun with --with-skills --yes to overwrite)"
  fi
  if [ -f "$skill_home_target/SKILL.md" ] || [ "$skill_copy" = 1 ]; then
    while IFS='|' read -r name home levels; do
      link="$home/skills/herdr-cowork"
      if [ ! -d "$home" ]; then
        skill_link_notes="$skill_link_notes
$name: skipped ($home not installed)"
      elif [ -L "$link" ] && [ -e "$skill_home_target" ] \
        && [ "$(cd -P "$link" 2>/dev/null && pwd)" = "$(cd -P "$skill_home_target" 2>/dev/null && pwd)" ]; then
        skill_link_notes="$skill_link_notes
$name: up to date"
      elif [ "$YES" = 1 ] || [ ! -e "$link" ]; then
        skill_links="$skill_links $name"
      elif [ -L "$link" ]; then
        skill_link_notes="$skill_link_notes
$name: kept (link points elsewhere; --yes replaces it)"
      else
        skill_link_notes="$skill_link_notes
$name: kept (not a symlink; --yes replaces it)"
      fi
    done <<EOF
$(skill_agent_homes)
EOF
  elif [ -L "$skill_home_target" ]; then
    skill_link_notes="$skill_link_notes
links skipped (the shared target symlink is dangling — fix or remove it yourself; --yes never touches it)"
  else
    skill_link_notes="$skill_link_notes
links skipped (the kept copy at the shared target has no SKILL.md; rerun with --with-skills --yes to replace it)"
  fi
  return 0
}

skill_report() {
  say "skill herdr-cowork: $skill_target_state"
  [ -n "$skill_links" ] && say "skill links to create:$skill_links"
  printf '%s' "$skill_link_notes" | while IFS= read -r note || [ -n "$note" ]; do
    [ -n "$note" ] && say "skill $note"
  done
  return 0
}

skill_write() {
  skill_ok=1
  if [ "$skill_copy" = 1 ]; then
    if mkdir -p "$skill_home_target" && cp skills/herdr-cowork/SKILL.md "$skill_home_target/SKILL.md"; then
      echo "skill herdr-cowork: SKILL.md -> $skill_home_target"
    else
      echo "skill herdr-cowork: copy failed — agent links skipped"
      skill_ok=0
    fi
  fi
  if [ "$skill_ok" = 1 ] && [ -f "$skill_home_target/SKILL.md" ]; then
    while IFS='|' read -r name home levels; do
      case " $skill_links " in *" $name "*) ;; *) continue ;; esac
      if ! mkdir -p "$home/skills"; then
        echo "skill herdr-cowork: cannot create $home/skills"; continue
      fi
      link="$home/skills/herdr-cowork"
      if [ -d "$link" ] && [ ! -L "$link" ]; then
        rm -rf "$link" || { echo "skill herdr-cowork: cannot remove your $link"; continue; }
      fi
      case "$levels" in
        2) rel="../../.agents/skills/herdr-cowork" ;;
        *) rel="../../../.agents/skills/herdr-cowork" ;;
      esac
      if ln -sfn "$rel" "$link"; then
        echo "skill herdr-cowork: linked $link"
      else
        echo "skill herdr-cowork: link failed at $link"
      fi
    done <<EOF
$(skill_agent_homes)
EOF
  elif [ -L "$skill_home_target" ] && [ ! -e "$skill_home_target" ]; then
    echo "skill herdr-cowork: target symlink is dangling — agent links skipped"
  fi
  return 0
}
