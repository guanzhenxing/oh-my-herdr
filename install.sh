#!/bin/sh
# Installs this layout and its mods from the repo into your Herdr home — the reverse of
# sync.sh, for a fresh install or an upgrade after merging upstream. Never touches mods it
# doesn't ship, keeps the key actions you already use, and keeps Mod settings where a
# mod.schema.json describes them.
#
#   sh install.sh              fresh install; mods you already have that differ are kept and listed
#   sh install.sh --yes        upgrade: overwrite differing mods and the layout too
#   sh install.sh --dry-run    report only, write nothing
#   sh install.sh --with-skills  also install the herdr-cowork skill (opt-in; see README)
#   sh install.sh --with-cowork --team <name|path>  also install one cowork team skill and link its
#                              templates into hc (opt-in; see skills/herdr-backend/README.md)
set -e
# Where the user ran the installer: a relative --team path is resolved against it.
cowork_caller_dir=$(pwd)
cd "$(dirname "$0")"
HOME_DIR="${HERDR_APP_HOME:-$HOME/.config/herdr-app}"
YES=0
DRY=0
WITH_SKILLS=0
WITH_COWORK=0
COWORK_TEAM=""
TEAM_GIVEN=0
TEAM_NEXT=0
cowork_tmp=""
for arg in "$@"; do
  if [ "$TEAM_NEXT" = 1 ]; then
    # The value of --team never starts with a dash: another flag here means there was no value.
    case "$arg" in
      --*) echo "--team needs a value: --team <team name or team pack path>"; exit 2 ;;
    esac
    COWORK_TEAM="$arg"; TEAM_GIVEN=1; TEAM_NEXT=0; continue
  fi
  case "$arg" in
    --yes) YES=1 ;;
    --dry-run) DRY=1 ;;
    --with-skills) WITH_SKILLS=1 ;;
    --with-cowork) WITH_COWORK=1 ;;
    --team) TEAM_NEXT=1 ;;
    *) echo "unknown flag: $arg (use --yes, --dry-run, --with-skills, --with-cowork, --team <name|path>)"; exit 2 ;;
  esac
done
[ "$TEAM_NEXT" = 1 ] && { echo "--team needs a value: --team <team name or team pack path>"; exit 2; }

command -v jq >/dev/null 2>&1 || { echo "install.sh needs jq"; exit 1; }
[ -f layouts/oh-my-herdr.json ] || { echo "layouts/oh-my-herdr.json missing from the repo"; exit 1; }
if [ "$WITH_SKILLS" = 1 ] && [ ! -f skills/herdr-cowork/SKILL.md ]; then
  echo "skills/herdr-cowork/SKILL.md missing from the repo"; exit 1
fi
# cowork (--with-cowork --team): the team pack is located and validated here, before
# anything is decided, so a bad pack exits without a single write. A team pack is a
# directory holding team.md (frontmatter: name, prefix) and templates/. The name is
# the team's to choose: it is the name of the skill that gets installed.
cowork_dir=$(pwd)/skills/herdr-backend
# The known team packs: every subdirectory of the two places a pack can live.
cowork_known_teams() {
  for cw_root in "$HOME/.config/cowork/teams" "$cowork_dir/teams"; do
    [ -d "$cw_root" ] || continue
    for cw_pack in "$cw_root"/*/; do
      if [ -d "$cw_pack" ]; then echo "  ${cw_pack%/}"; fi
    done
  done
  return 0
}
# cowork_field <file> <key>: the value on the first "key: value" line of the leading
# frontmatter. Bracket classes are avoided: the awk on macOS rejects them in a built pattern.
cowork_field() {
  awk -v k="$2" '
    NR == 1 && $0 != "---" { exit }
    NR > 1 && $0 == "---" { exit }
    NR > 1 && index($0, k ":") == 1 { v = substr($0, length(k) + 2); sub(/^[ \t]*/, "", v); sub(/[ \t]+$/, "", v); print v; exit }
  ' "$1"
}
# cowork_name_ok <value>: lowercase letters, digits and hyphens, and not empty. The check
# runs under LC_ALL=C: in a UTF-8 locale the a-z range of a bracket expression can be
# collated so that it matches uppercase letters as well.
cowork_name_ok() { [ -n "$1" ] && printf '%s\n' "$1" | LC_ALL=C grep -q '^[a-z0-9-]*$'; }
cowork_die() { echo "cowork: $*"; exit 1; }

cowork_pack=""; cowork_skill_name=""; cowork_prefix=""
if [ "$TEAM_GIVEN" = 1 ] && [ "$WITH_COWORK" = 0 ]; then
  echo "--team is only used with --with-cowork"; exit 2
fi
if [ "$WITH_COWORK" = 1 ]; then
  if [ -z "$COWORK_TEAM" ]; then
    echo "--with-cowork needs --team <team name or team pack path>. Known team packs:"
    cowork_known_teams
    exit 2
  fi
  # A value with a slash is a path: an absolute one as it is, a relative one against the
  # directory the installer was started from. A bare name is looked up, the local directory
  # first. So a team called "mods" is never taken for the repo's mods/.
  case "$COWORK_TEAM" in
    /*) [ -d "$COWORK_TEAM" ] && cowork_pack="${COWORK_TEAM%/}" ;;
    */*) [ -d "$cowork_caller_dir/$COWORK_TEAM" ] && cowork_pack="$cowork_caller_dir/${COWORK_TEAM%/}" ;;
    *)
      if [ -d "$HOME/.config/cowork/teams/$COWORK_TEAM" ]; then cowork_pack="$HOME/.config/cowork/teams/$COWORK_TEAM"
      elif [ -d "$cowork_dir/teams/$COWORK_TEAM" ]; then cowork_pack="$cowork_dir/teams/$COWORK_TEAM"
      fi
      ;;
  esac
  if [ -z "$cowork_pack" ]; then
    echo "cowork: team pack not found: $COWORK_TEAM. Known team packs:"
    cowork_known_teams
    exit 1
  fi
  [ -f "$cowork_dir/PROTOCOL.md" ] && [ -f "$cowork_dir/README.md" ] || cowork_die "$cowork_dir/PROTOCOL.md or $cowork_dir/README.md missing from the repo"
  [ -f "$cowork_pack/team.md" ] || cowork_die "$cowork_pack/team.md missing"
  # Checked before the fields are read: with Windows line endings the first line is
  # not "---", the fields read as empty, and the message would blame the wrong thing.
  case "$(sed -n '1p' "$cowork_pack/team.md")" in *"$(printf '\r')"*)
    cowork_die "team.md: uses Windows line endings (CRLF); convert it to LF" ;;
  esac
  cowork_skill_name="$(cowork_field "$cowork_pack/team.md" name)"
  cowork_prefix="$(cowork_field "$cowork_pack/team.md" prefix)"
  # A skill name as the Agent Skills spec wants it: lowercase letters and digits
  # separated by single hyphens, at most 64 characters.
  printf '%s\n' "$cowork_skill_name" | LC_ALL=C grep -Eq '^[a-z0-9]+(-[a-z0-9]+)*$' \
    || cowork_die "team.md: 'name' must be lowercase letters and digits separated by single hyphens (got '$cowork_skill_name')"
  [ "${#cowork_skill_name}" -le 64 ] || cowork_die "team.md: 'name' is longer than 64 characters, which is the limit for a skill name"
  cowork_name_ok "$cowork_prefix" || cowork_die "team.md: 'prefix' must be set to lowercase letters, digits and hyphens (got '$cowork_prefix')"
  # hc limits template names to 32 characters, and "review" is the longest key.
  [ "${#cowork_prefix}" -le 25 ] || cowork_die "team.md: 'prefix' is longer than 25 characters, hc limits template names to 32"
  # The frontmatter must be closed. Without the closing line the two fields above
  # still read, and the body would be left out of SKILL.md.
  awk 'NR > 1 && $0 == "---" { found = 1; exit } END { exit !found }' "$cowork_pack/team.md" \
    || cowork_die "team.md: frontmatter is not closed by a --- line"
  # The four section headings the generic protocol refers to. A pack must have all of them.
  for cw_heading in "角色与模板" "命名前缀" "工作区" "路径"; do
    grep -q "^### $cw_heading\$" "$cowork_pack/team.md" || cowork_die "team.md: required section '### $cw_heading' missing"
  done
  for cw_key in arch dev review test run; do
    [ -f "$cowork_pack/templates/$cowork_prefix-$cw_key.md" ] || cowork_die "templates/$cowork_prefix-$cw_key.md missing from the team pack"
  done
  # Every template, the five roles and any extra one. The frontmatter must agree with
  # the file name, the name may be 32 characters at most, and it may hold no whitespace:
  # the list of links to create is split on spaces.
  for cw_tpl in "$cowork_pack"/templates/*.md; do
    [ -f "$cw_tpl" ] || continue
    cw_name="${cw_tpl##*/}"; cw_name="${cw_name%.md}"
    if [ "${#cw_name}" -gt 32 ] || printf '%s\n' "$cw_name" | grep -q '[[:space:]]'; then
      cowork_die "templates/${cw_tpl##*/}: the file name must be at most 32 characters and hold no whitespace (got '$cw_name')"
    fi
    [ "$(cowork_field "$cw_tpl" name)" = "$cw_name" ] || cowork_die "templates/${cw_tpl##*/}: frontmatter 'name' must be $cw_name"
  done
  [ "$(grep -c '^name: TEAM-SKILL$' "$cowork_dir/PROTOCOL.md")" = 1 ] || cowork_die "$cowork_dir/PROTOCOL.md must hold exactly one line 'name: TEAM-SKILL'"
  cowork_skill_dir="$HOME/.agents/skills/$cowork_skill_name"
  # herdr-cowork is the skill that --with-skills installs from skills/herdr-cowork/.
  [ "$cowork_skill_name" != herdr-cowork ] || cowork_die "team.md: 'name' must not be herdr-cowork: that is the name of the skill installed by --with-skills"
  # The name is the team's to choose, so it can be the name of a skill that is already
  # here. A directory without a team.md is not a team skill: it is never written to,
  # not even with --yes.
  if [ -d "$cowork_skill_dir" ] && [ ! -L "$cowork_skill_dir" ] && [ ! -f "$cowork_skill_dir/team.md" ]; then
    cowork_die "$cowork_skill_dir already exists and is not a team skill (no team.md in it); give this team another name in team.md"
  fi
fi
say() { if [ "$DRY" = 1 ]; then echo "[dry] $*"; else echo "$*"; fi; }
# The home copies carry files the app writes itself (type files, jsconfig, caches), and
# CHANGES.md lives in the repo only (sync.sh) — the same set sync.sh leaves out, so a
# "kept, differs" never means only those: none of them count as a difference.
same() { diff -rq -x gpui-kit.d.ts -x herdr.d.ts -x jsconfig.json -x node_modules -x .cache -x .DS_Store -x CHANGES.md "$1" "$2" >/dev/null 2>&1; }

install_mods=""
kept_mods=""
uptodate_mods=""
for mod in mods/*/; do
  name=$(basename "$mod")
  target="$HOME_DIR/mods/$name"
  if [ ! -e "$target" ]; then
    install_mods="$install_mods $name"
  elif same "$mod" "$target"; then
    uptodate_mods="$uptodate_mods $name"
  elif [ "$YES" = 1 ]; then
    install_mods="$install_mods $name"
  else
    kept_mods="$kept_mods $name"
  fi
done

# The app stamps a cloned_from on the home layout; sync.sh strips it, so compare without it.
layout_tmp=""
if [ ! -e "$HOME_DIR/layouts/oh-my-herdr.json" ]; then
  install_layout=1
else
  layout_tmp=$(mktemp)
  trap 'rm -f "$layout_tmp"' EXIT
  jq 'del(.cloned_from)' "$HOME_DIR/layouts/oh-my-herdr.json" > "$layout_tmp" 2>/dev/null || cp "$HOME_DIR/layouts/oh-my-herdr.json" "$layout_tmp"
  if [ "$YES" = 1 ] || cmp -s layouts/oh-my-herdr.json "$layout_tmp"; then
    install_layout=1
  else
    install_layout=0
    kept_layout=1
  fi
fi

# keys.json is merged, not replaced: new sections and keys are added, an action you
# already bound keeps yours. Herdr's own default bindings are merged back in as well
# (yours still win): the app swaps its whole keymap for this file, so a keys.json that
# lost them — a deploy that cp'd a partial file over it, or a fresh install written
# before the app ever ran — silently drops every default binding, cmd-v paste included.
# Refresh the embedded tables from herdr-app's defaults/keys.json and
# defaults/keys.macos.json when bumping the Herdr version this repo supports.
keys_changed=0
keys_conflicts=""
keys_defaults=0
keys_dir=$(mktemp -d)
merged="$keys_dir/keys.json"
entries="$keys_dir/entries"
next="$keys_dir/next"
trap 'rm -rf "$keys_dir" "$layout_tmp"; [ -z "$cowork_tmp" ] || rm -rf "$cowork_tmp"' EXIT
if [ "$(uname)" = "Darwin" ]; then
  cat >"$keys_dir/defaults.json" <<'DEFAULTS'
{
  "global": {
    "cmd-q": "app.quit",
    "cmd-h": "app.hide",
    "cmd-alt-h": "app.hide_others",
    "cmd-m": "window.minimize",
    "cmd-t": "tab.new",
    "cmd-w": "tab.close",
    "ctrl-tab": "tab.next",
    "ctrl-shift-tab": "tab.prev",
    "cmd-shift-]": "tab.next",
    "cmd-shift-[": "tab.prev",
    "cmd-alt-]": "space.next",
    "cmd-alt-[": "space.prev",
    "cmd-]": "agent.next",
    "cmd-[": "agent.prev",
    "cmd-shift-l": "layout.switch",
    "cmd-n": "space.new",
    "cmd-p": "mod.open:picker",
    "cmd-shift-p": "app.palette",
    "cmd-,": "app.settings",
    "cmd-d": "pane.split:right",
    "cmd-shift-d": "pane.split:down",
    "cmd-shift-w": "pane.close",
    "cmd-shift-enter": "pane.zoom",
    "cmd-alt-left": "pane.go:left",
    "cmd-alt-right": "pane.go:right",
    "cmd-alt-up": "pane.go:up",
    "cmd-alt-down": "pane.go:down",
    "cmd-alt-shift-left": "pane.swap:left",
    "cmd-alt-shift-right": "pane.swap:right",
    "cmd-alt-shift-up": "pane.swap:up",
    "cmd-alt-shift-down": "pane.swap:down",
    "f2": "tab.rename",
    "shift-f2": "space.rename",
    "cmd-/": "app.help",
    "cmd-shift-/": "app.help",
    "cmd-b": "layout.toggle:sidebar",
    "cmd-=": "app.zoom_in",
    "cmd-+": "app.zoom_in",
    "cmd--": "app.zoom_out",
    "cmd-0": "app.zoom_reset",
    "cmd-1": "tab.select:1",
    "cmd-2": "tab.select:2",
    "cmd-3": "tab.select:3",
    "cmd-4": "tab.select:4",
    "cmd-5": "tab.select:5",
    "cmd-6": "tab.select:6",
    "cmd-7": "tab.select:7",
    "cmd-8": "tab.select:8",
    "cmd-9": "tab.select:9",
    "ctrl-1": "space.select:1",
    "ctrl-2": "space.select:2",
    "ctrl-3": "space.select:3",
    "ctrl-4": "space.select:4",
    "ctrl-5": "space.select:5",
    "ctrl-6": "space.select:6",
    "ctrl-7": "space.select:7",
    "ctrl-8": "space.select:8",
    "ctrl-9": "space.select:9"
  },
  "terminal": {
    "cmd-f": "terminal.search",
    "cmd-a": "terminal.select_all",
    "cmd-c": "terminal.copy",
    "cmd-v": "terminal.paste",
    "ctrl-v": "terminal.paste_image",
    "alt-left": "send:\u001bb",
    "alt-right": "send:\u001bf",
    "alt-backspace": "send:\u0017",
    "cmd-left": "send:\u0001",
    "cmd-right": "send:\u0005",
    "cmd-backspace": "send:\u0015"
  }
}
DEFAULTS
else
  cat >"$keys_dir/defaults.json" <<'DEFAULTS'
{
  "global": {
    "alt-1": "space.select:1",
    "alt-2": "space.select:2",
    "alt-3": "space.select:3",
    "alt-4": "space.select:4",
    "alt-5": "space.select:5",
    "alt-6": "space.select:6",
    "alt-7": "space.select:7",
    "alt-8": "space.select:8",
    "alt-9": "space.select:9",
    "alt-[": "tab.prev",
    "alt-]": "tab.next",
    "alt-down": "agent.next",
    "alt-up": "agent.prev",
    "alt-h": "pane.go:left",
    "alt-j": "pane.go:down",
    "alt-k": "pane.go:up",
    "alt-l": "pane.go:right",
    "alt-left": "pane.go:left",
    "alt-right": "pane.go:right",
    "alt-shift-h": "pane.swap:left",
    "alt-shift-j": "pane.swap:down",
    "alt-shift-k": "pane.swap:up",
    "alt-shift-l": "pane.swap:right",
    "ctrl-+": "app.zoom_in",
    "ctrl-,": "app.settings",
    "ctrl--": "app.zoom_out",
    "ctrl-0": "app.zoom_reset",
    "ctrl-=": "app.zoom_in",
    "ctrl-1": "tab.select:1",
    "ctrl-2": "tab.select:2",
    "ctrl-3": "tab.select:3",
    "ctrl-4": "tab.select:4",
    "ctrl-5": "tab.select:5",
    "ctrl-6": "tab.select:6",
    "ctrl-7": "tab.select:7",
    "ctrl-8": "tab.select:8",
    "ctrl-9": "tab.select:9",
    "ctrl-?": "app.help",
    "ctrl-pagedown": "tab.next",
    "ctrl-pageup": "tab.prev",
    "ctrl-shift-/": "app.help",
    "ctrl-shift-?": "app.help",
    "ctrl-shift-b": "layout.toggle:sidebar",
    "ctrl-shift-e": "pane.split:down",
    "ctrl-shift-k": "mod.open:picker",
    "ctrl-shift-l": "layout.switch",
    "ctrl-shift-n": "space.new",
    "ctrl-shift-o": "pane.split:right",
    "ctrl-shift-p": "app.palette",
    "ctrl-shift-pagedown": "space.next",
    "ctrl-shift-pageup": "space.prev",
    "ctrl-shift-t": "tab.new",
    "ctrl-shift-tab": "tab.prev",
    "ctrl-shift-w": "tab.close",
    "ctrl-shift-x": "pane.close",
    "ctrl-shift-z": "pane.zoom",
    "ctrl-tab": "tab.next",
    "f2": "tab.rename",
    "shift-f2": "space.rename"
  },
  "terminal": {
    "ctrl-backspace": "send:\u0017",
    "ctrl-insert": "terminal.copy",
    "ctrl-left": "send:\u001bb",
    "ctrl-right": "send:\u001bf",
    "ctrl-shift-c": "terminal.copy",
    "ctrl-shift-f": "terminal.search",
    "ctrl-shift-v": "terminal.paste",
    "ctrl-v": "terminal.paste_image",
    "shift-insert": "terminal.paste"
  }
}
DEFAULTS
fi
if [ ! -f "$HOME_DIR/keys.json" ]; then
  install_keys=1
  printf '{}' >"$merged"
else
  install_keys=0
  cp "$HOME_DIR/keys.json" "$merged"
fi
for section in $(jq -r 'keys_unsorted[]' keys.json); do
  jq -r --arg s "$section" '.[$s] | to_entries[] | "\(.key)\t\(.value | tojson)"' keys.json >"$entries"
  while IFS="	" read -r key value; do
    home_value=$(jq -r --arg s "$section" --arg k "$key" '(.[$s][$k] // null) | if . == null then "absent" else tojson end' "$merged")
    if [ "$home_value" = "absent" ]; then
      jq --arg s "$section" --arg k "$key" --argjson v "$value" '.[$s] //= {} | .[$s][$k] = $v' "$merged" >"$next" && mv "$next" "$merged"
      keys_changed=1
    elif [ "$home_value" != "$value" ]; then
      keys_conflicts="$keys_conflicts
  $section / $key: keeping yours ($home_value); the package binds $value"
    fi
  done <"$entries"
done
# The guard itself: count the default bindings missing from the (package-merged) file
# and layer them underneath. Bound keys above are never touched.
keys_defaults=$(jq -s '.[0] as $home | .[1] | [to_entries[] | .key as $sec | (.value | keys[]) as $k | select($home[$sec][$k] == null) | 1] | length' "$merged" "$keys_dir/defaults.json")
if [ "$keys_defaults" -gt 0 ]; then
  jq -s '.[1] * .[0]' "$merged" "$keys_dir/defaults.json" >"$next" && mv "$next" "$merged"
  keys_changed=1
fi

# Where each agent reads skills: name|home directory|levels up to $HOME. Shared by
# --with-skills and --with-cowork. An agent whose home directory is missing is
# skipped, never created.
skill_agent_homes() {
  cat <<EOF
claude|$HOME/.claude|2
codex|$HOME/.codex|2
gemini|$HOME/.gemini|2
opencode|$HOME/.config/opencode|3
pi|$HOME/.pi/agent|3
EOF
}
# herdr-cowork skill (--with-skills): everything is decided here, before the dry-run
# gate, and only written after it. Agent homes that don't exist are skipped, not
# created. "Correct link" means it resolves to the shared copy, not string equality.
skill_target_state=""; skill_copy=0; skill_links=""; skill_link_notes=""
skill_home_target="$HOME/.agents/skills/herdr-cowork"
if [ "$WITH_SKILLS" = 1 ]; then
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
fi

# cowork (--with-cowork --team): everything is decided here, before the dry-run gate,
# and only written after it. SKILL.md is assembled into a temp file now, so the
# comparison with the installed copy is exact and a dry run writes nothing.
cowork_boundary='<!-- 以上是通用协议，由 oh-my-herdr 的 skills/herdr-backend/PROTOCOL.md 提供；以下是本团队配置，安装时取自团队包的 team.md。个人改动请落在团队包或装好的模板里（改 team.md 后要重跑安装器才生效），不要直接改本文件。 -->'
cowork_hc_dir="$HOME/.config/herdr-core/templates"
cowork_skill_state=""; cowork_links=""; cowork_link_notes=""; cowork_hc_links=""; cw_notes=""
cowork_stale=""; cowork_hc_stale=""
cowork_same_dir=0
cowork_active=0
# cowork_installed_is_current: the installed skill dir holds exactly what would be written.
cowork_installed_is_current() {
  cmp -s "$cowork_tmp/SKILL.md" "$cowork_skill_dir/SKILL.md" &&
  cmp -s "$cowork_dir/README.md" "$cowork_skill_dir/README.md" &&
  cmp -s "$cowork_pack/team.md" "$cowork_skill_dir/team.md" &&
  diff -rq -x .DS_Store "$cowork_pack/templates" "$cowork_skill_dir/templates" >/dev/null 2>&1
}
# cowork_link_target <symlink to a file>: the physical path of the file it points to.
# An hc template link is "correct" when this equals the path of the installed template.
cowork_link_target() (
  cw_lt="$(readlink "$1")"
  case "$cw_lt" in
    /*) cw_td="$(dirname "$cw_lt")" ;;
    *) cw_td="$(dirname "$1")/$(dirname "$cw_lt")" ;;
  esac
  printf '%s/%s\n' "$(cd -P "$cw_td" 2>/dev/null && pwd)" "$(basename "$cw_lt")"
)
# cowork_link_owner <symlink>: the name of the team skill whose templates the link
# points into, or nothing. hc keeps the templates of every team in one directory, so
# two teams that share a prefix would each take the other's templates over. A team
# skill is known by the team.md in its directory, whatever the skill is called.
cowork_link_owner() {
  cw_lo="$(cowork_link_target "$1")"
  case "$cw_lo" in */templates/*.md) ;; *) return 0 ;; esac
  cw_lo="$(dirname "$(dirname "$cw_lo")")"
  [ -f "$cw_lo/team.md" ] || return 0
  cw_lo="$(cowork_field "$cw_lo/team.md" name)"
  if [ -n "$cw_lo" ] && [ "$cw_lo" != "$cowork_skill_name" ]; then printf '%s\n' "$cw_lo"; fi
}
if [ "$WITH_COWORK" = 1 ]; then
  # The installed dir is itself a valid team pack. When it is the one named, only the
  # repo's two files may change.
  if [ -d "$cowork_pack" ] && [ -d "$cowork_skill_dir" ] &&
     [ "$(cd -P "$cowork_pack" 2>/dev/null && pwd)" = "$(cd -P "$cowork_skill_dir" 2>/dev/null && pwd)" ]; then
    cowork_same_dir=1
  fi
  cowork_tmp=$(mktemp -d)
  # The protocol with every TEAM-SKILL replaced by the skill's name, which fills the
  # name line and the sentence that tells members which skills not to load; then a
  # blank line, the boundary, a blank line, and the body of team.md without the blank
  # lines that may follow its frontmatter. awk ends the protocol with a newline even
  # when the file has none, so the result is the same whatever its last line looks like.
  {
    awk -v s="$cowork_skill_name" '{ gsub(/TEAM-SKILL/, s) } 1' "$cowork_dir/PROTOCOL.md"
    printf '\n%s\n\n' "$cowork_boundary"
    awk 'c < 2 { if ($0 == "---") c++; next } !started && /^$/ { next } { started = 1; print }' "$cowork_pack/team.md"
  } > "$cowork_tmp/SKILL.md"

  if [ -L "$cowork_skill_dir" ]; then
    cowork_skill_state="kept (is a symlink; never touched, even with --yes)"
  elif [ ! -e "$cowork_skill_dir" ]; then
    cowork_skill_state="install"
  elif [ ! -d "$cowork_skill_dir" ]; then
    cowork_skill_state="kept (is not a directory; never touched, even with --yes)"
  elif cowork_installed_is_current; then
    cowork_skill_state="up to date"
  elif [ "$YES" = 1 ]; then
    cowork_skill_state="replace"
  else
    cowork_skill_state="kept (differs; rerun with --yes to overwrite)"
  fi

  # Links are planned only when the skill dir has a readable SKILL.md or gets one now.
  # Deciding that here keeps a dry run honest about what a real run would do.
  if [ -f "$cowork_skill_dir/SKILL.md" ] || [ "$cowork_skill_state" = install ] || [ "$cowork_skill_state" = replace ]; then
    cowork_active=1
  elif [ -L "$cowork_skill_dir" ]; then
    cw_notes="$cw_notes
links skipped (the skill dir is a symlink to a place without a SKILL.md; fix or remove it yourself; --yes never touches it)"
  elif [ ! -d "$cowork_skill_dir" ]; then
    cw_notes="$cw_notes
links skipped ($cowork_skill_dir is not a directory; move it away yourself)"
  else
    cw_notes="$cw_notes
links skipped (the kept copy in $cowork_skill_dir has no readable SKILL.md; rerun with --yes to replace it)"
  fi

  # The pack and the installed dir are two directories: say when the installed team.md
  # or templates no longer equal the pack's. --yes then overwrites them. "以后 X 都用 Y"
  # edits the installed template, so that is how such an edit is lost.
  if [ "$cowork_same_dir" = 0 ] && { [ "$cowork_skill_state" = replace ] || [ "$cowork_skill_state" = "kept (differs; rerun with --yes to overwrite)" ]; }; then
    if ! cmp -s "$cowork_pack/team.md" "$cowork_skill_dir/team.md" \
       || ! diff -rq -x .DS_Store "$cowork_pack/templates" "$cowork_skill_dir/templates" >/dev/null 2>&1; then
      cw_notes="$cw_notes
$cowork_skill_dir: its team.md or templates/ differ from the team pack's (edited in place, or an older pack); --yes overwrites them. To keep them, run with --team $cowork_skill_dir"
    fi
  fi

  # What a write removes. Templates the pack no longer has go when the skill dir is
  # replaced. hc links into this team's templates dangle when their template is not in
  # the pack, or is already gone when the installed dir is the pack. Decided here, so
  # that a dry run lists them too.
  if [ "$cowork_skill_state" = install ] || [ "$cowork_skill_state" = replace ]; then
    if [ "$cowork_same_dir" = 0 ] && [ -d "$cowork_skill_dir/templates" ]; then
      for cw_old in "$cowork_skill_dir"/templates/*.md; do
        [ -f "$cw_old" ] || continue
        [ -f "$cowork_pack/templates/${cw_old##*/}" ] || cowork_stale="$cowork_stale ${cw_old##*/}"
      done
    fi
    if [ -d "$cowork_hc_dir" ]; then
      for cw_old in "$cowork_hc_dir"/*; do
        [ -L "$cw_old" ] || continue
        case "$(readlink "$cw_old")" in *"skills/$cowork_skill_name/templates/"*) ;; *) continue ;; esac
        if [ "$cowork_same_dir" = 1 ]; then
          [ -f "$cowork_skill_dir/templates/${cw_old##*/}" ] && continue
        else
          [ -f "$cowork_pack/templates/${cw_old##*/}" ] && continue
        fi
        cowork_hc_stale="$cowork_hc_stale ${cw_old##*/}"
      done
    fi
  fi

  # Agent links. Whatever a run would remove or replace at one of these positions is
  # said in the notes: the report is all a dry run has.
  if [ "$cowork_active" = 1 ]; then
    while IFS='|' read -r cw_name cw_home cw_levels; do
      cw_link="$cw_home/skills/$cowork_skill_name"
      if [ ! -d "$cw_home" ]; then
        cw_link_notes="$cw_link_notes
$cw_name: skipped ($cw_home not installed)"
      elif [ -L "$cw_link" ] && [ -e "$cowork_skill_dir" ] && [ "$(cd -P "$cw_link" 2>/dev/null && pwd)" = "$(cd -P "$cowork_skill_dir" 2>/dev/null && pwd)" ]; then
        cw_link_notes="$cw_link_notes
$cw_name: up to date"
      elif [ ! -e "$cw_link" ]; then
        cowork_links="$cowork_links $cw_name"
      elif [ "$YES" = 1 ]; then
        cowork_links="$cowork_links $cw_name"
        if [ -L "$cw_link" ]; then
          cw_link_notes="$cw_link_notes
$cw_name: replaces the link that points elsewhere"
        elif [ -d "$cw_link" ]; then
          cw_link_notes="$cw_link_notes
$cw_name: deletes your directory $cw_link and links in its place"
        else
          cw_link_notes="$cw_link_notes
$cw_name: deletes your file $cw_link and links in its place"
        fi
      elif [ -L "$cw_link" ]; then
        cw_link_notes="$cw_link_notes
$cw_name: kept (link points elsewhere; --yes replaces it)"
      elif [ -d "$cw_link" ]; then
        cw_link_notes="$cw_link_notes
$cw_name: kept (a real directory; --yes deletes it and links in its place)"
      else
        cw_link_notes="$cw_link_notes
$cw_name: kept (a regular file; --yes deletes it and links in its place)"
      fi
    done <<EOF
$(skill_agent_homes)
EOF
  fi

  # hc template links, one per template in the pack.
  if [ "$cowork_active" = 0 ]; then
    :    # already reported above
  elif [ ! -d "$cowork_hc_dir" ]; then
    cw_notes="$cw_notes
hc templates skipped ($cowork_hc_dir does not exist; create it and rerun)"
  else
    for cw_src in "$cowork_pack"/templates/*.md; do
      [ -f "$cw_src" ] || continue
      cw_tpl="${cw_src##*/}"
      # A kept skill dir may lack a template of the pack. There is nothing to link to then.
      if [ "$cowork_skill_state" != install ] && [ "$cowork_skill_state" != replace ] && [ ! -f "$cowork_skill_dir/templates/$cw_tpl" ]; then
        cw_notes="$cw_notes
$cw_tpl: skipped (that template is not installed in the kept skill dir)"
        continue
      fi
      cw_hc_link="$cowork_hc_dir/$cw_tpl"
      cw_hc_target="$cowork_skill_dir/templates/$cw_tpl"
      # What the link will point at once this run is over: the pack's template when the
      # skill dir is written, the installed one when it is kept.
      cw_will_be="$cw_src"
      if [ "$cowork_skill_state" != install ] && [ "$cowork_skill_state" != replace ]; then cw_will_be="$cw_hc_target"; fi
      # The physical path of the target. The assignment is guarded: cd fails until the
      # templates exist, and an assignment whose command substitution fails ends the
      # script under set -e.
      cw_target_phys="$cw_hc_target"
      if [ -d "$cowork_skill_dir/templates" ]; then
        cw_target_phys="$(cd -P "$cowork_skill_dir/templates" 2>/dev/null && pwd)/$cw_tpl"
      fi
      if [ -L "$cw_hc_link" ] && [ -e "$cw_hc_target" ] && [ "$(cowork_link_target "$cw_hc_link")" = "$cw_target_phys" ]; then
        cw_notes="$cw_notes
$cw_tpl: up to date"
      elif [ -L "$cw_hc_link" ] && [ ! -e "$cw_hc_link" ]; then
        cowork_hc_links="$cowork_hc_links $cw_tpl"    # dangling
      elif [ -L "$cw_hc_link" ]; then
        cw_owner="$(cowork_link_owner "$cw_hc_link")"
        if [ -n "$cw_owner" ]; then
          # Refused before anything is written. With --yes this team would take the
          # other team's templates over, one link at a time, without a word.
          cowork_die "team.md: prefix '$cowork_prefix' is already used by the team skill '$cw_owner' ($cw_hc_link links into its skill dir); two teams must not share a prefix"
        elif [ "$YES" = 1 ]; then
          cowork_hc_links="$cowork_hc_links $cw_tpl"
          cw_notes="$cw_notes
$cw_tpl: replaces the link that points elsewhere"
        else
          cw_notes="$cw_notes
$cw_tpl: kept (link points elsewhere; --yes replaces it)"
        fi
      elif [ ! -e "$cw_hc_link" ]; then
        cowork_hc_links="$cowork_hc_links $cw_tpl"
      elif [ -f "$cw_hc_link" ] && cmp -s "$cw_will_be" "$cw_hc_link"; then
        cowork_hc_links="$cowork_hc_links $cw_tpl"
        cw_notes="$cw_notes
$cw_tpl: a regular file identical to the template the link will point to; replacing it with a link"
      elif [ -f "$cw_hc_link" ]; then
        cw_notes="$cw_notes
$cw_tpl: kept (a regular file that differs; move it away yourself — --yes never replaces it)"
      else
        cw_notes="$cw_notes
$cw_tpl: kept (not a symlink; --yes never replaces it)"
      fi
    done
  fi
fi
echo "Install from $(pwd) into $HOME_DIR"
[ -n "$uptodate_mods" ] && say "up to date:$uptodate_mods"
[ -n "$install_mods" ] && say "mods to install:$install_mods"
[ -n "$kept_mods" ] && say "kept, you already have different ones:$kept_mods (rerun with --yes to overwrite)"
if [ "$install_layout" = 1 ]; then say "layout: layouts/oh-my-herdr.json"; elif [ "$kept_layout" = 1 ]; then say "kept your layouts/oh-my-herdr.json (differs; rerun with --yes to overwrite)"; fi
if [ "$install_keys" = 1 ]; then say "keys.json: none yet, installing the app defaults plus the package's"
elif [ "$keys_changed" = 1 ]; then say "keys.json: merging in new bindings"
elif [ "$keys_conflicts" = "" ]; then say "keys.json: already merged"; fi
[ "$keys_defaults" -gt 0 ] && say "keys.json: restored $keys_defaults Herdr default binding(s) the file was missing (a cp over keys.json drops them: the app replaces its whole keymap with that file)"
[ -n "$keys_conflicts" ] && say "keys.json conflicts:$keys_conflicts"

if [ "$WITH_SKILLS" = 1 ]; then
  say "skill herdr-cowork: $skill_target_state"
  [ -n "$skill_links" ] && say "skill links to create:$skill_links"
  printf '%s' "$skill_link_notes" | while IFS= read -r note || [ -n "$note" ]; do
    [ -n "$note" ] && say "skill $note"
  done
fi

if [ "$WITH_COWORK" = 1 ]; then
  say "cowork $cowork_skill_name: team pack $cowork_pack"
  say "cowork $cowork_skill_name: $cowork_skill_dir $cowork_skill_state"
  [ -n "$cowork_links" ] && say "cowork $cowork_skill_name: skill links to create:$cowork_links"
  [ -n "$cowork_hc_links" ] && say "cowork $cowork_skill_name: hc template links to create:$cowork_hc_links"
  [ -n "$cowork_stale" ] && say "cowork $cowork_skill_name: templates to remove from the installed dir:$cowork_stale"
  [ -n "$cowork_hc_stale" ] && say "cowork $cowork_skill_name: hc links to remove, they would dangle:$cowork_hc_stale"
  # The same shape as the herdr-cowork notes: printf '%s' without a trailing newline, so
  # the loop ends on a non-empty note. A loop that ends on an empty line returns 1, which
  # would end the script under set -e right after the report.
  for cw_note_list in "$cw_link_notes" "$cw_notes"; do
    printf '%s' "$cw_note_list" | while IFS= read -r cw_note || [ -n "$cw_note" ]; do
      [ -n "$cw_note" ] && say "cowork $cowork_skill_name: $cw_note"
    done
  done
fi
if [ "$DRY" = 1 ]; then
  echo "dry run: nothing written."
  exit 0
fi

mkdir -p "$HOME_DIR/mods" "$HOME_DIR/layouts"
for name in $install_mods; do
  # Mod settings a schema describes are the person's choices: keep them across the upgrade.
  prev=null
  if [ -f "mods/$name/mod.schema.json" ] && [ -f "$HOME_DIR/mods/$name/mod.json" ]; then
    prev=$(jq '.settings // null' "$HOME_DIR/mods/$name/mod.json")
  fi
  rsync -a --delete "mods/$name/" "$HOME_DIR/mods/$name/"
  if [ "$prev" != "null" ]; then
    jq --argjson s "$prev" '.settings = $s' "mods/$name/mod.json" > "$HOME_DIR/mods/$name/mod.json.tmp"
    mv "$HOME_DIR/mods/$name/mod.json.tmp" "$HOME_DIR/mods/$name/mod.json"
  fi
done
[ "$install_layout" = 1 ] && cp layouts/oh-my-herdr.json "$HOME_DIR/layouts/oh-my-herdr.json"
if [ "$install_keys" = 1 ] || [ "$keys_changed" = 1 ]; then
  cp "$merged" "$HOME_DIR/keys.json"
fi

# The Automations panel needs the herdr-automations CLI. Build it from the vendored
# source when Go is here; otherwise download the pinned release and verify its
# checksum. Already-installed copies (PATH or ~/.local/bin) are left alone.
if command -v herdr-automations >/dev/null 2>&1 || [ -x "$HOME/.local/bin/herdr-automations" ]; then
  echo "herdr-automations CLI: already installed"
else
  cli_bin="$HOME/.local/bin/herdr-automations"
  tag="v0.14.0"
  if command -v go >/dev/null 2>&1; then
    echo "herdr-automations CLI: building from vendored source (cli/herdr-automations)"
    (cd cli/herdr-automations && go build -o "$cli_bin" .) || echo "  go build failed — the Automations panel will say so until it is installed."
  else
    case "$(uname -sm)" in
      Darwin\ arm64) asset="darwin_arm64" ;;
      Darwin\ x86_64) asset="darwin_amd64" ;;
      Linux\ x86_64) asset="linux_amd64" ;;
      Linux\ aarch64) asset="linux_arm64" ;;
      *) asset="" ;;
    esac
    if [ -z "$asset" ]; then
      echo "herdr-automations CLI: no release binary for $(uname -sm); install Go and rerun, or build cli/herdr-automations."
    else
      rel="https://github.com/DnzzL/herdr-automations/releases/download/$tag"
      tmp=$(mktemp -d)
      if curl -fsSL -o "$tmp/herdr-automations_$asset" "$rel/herdr-automations_$asset" \
         && curl -fsSL -o "$tmp/checksums.txt" "$rel/checksums.txt"; then
        if command -v shasum >/dev/null 2>&1; then
          grep "herdr-automations_$asset" "$tmp/checksums.txt" | shasum -a 256 -c -
        elif command -v sha256sum >/dev/null 2>&1; then
          grep "herdr-automations_$asset" "$tmp/checksums.txt" | sha256sum -c -
        else
          echo "herdr-automations CLI: no sha256 tool found; refusing to install an unverified binary."
        fi
        [ $? = 0 ] && mkdir -p "$HOME/.local/bin" && install -m 755 "$tmp/herdr-automations_$asset" "$cli_bin" \
          && echo "herdr-automations CLI: installed $tag to $cli_bin"
      else
        echo "herdr-automations CLI: download failed ($rel) — the Automations panel will say so until it is installed."
      fi
      rm -rf "$tmp"
    fi
  fi
fi

# herdr-cowork skill (--with-skills): the copy first; links only if it landed, so a
# failed copy never leaves five dangling links for every agent to list as a bad skill.
if [ "$WITH_SKILLS" = 1 ]; then
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
fi

# cowork (--with-cowork --team): the skill dir first; links only if it ended with a
# readable SKILL.md, so a failed write never leaves dangling links behind.
if [ "$WITH_COWORK" = 1 ]; then
  cw_write_ok=1
  if [ "$cowork_skill_state" = install ] || [ "$cowork_skill_state" = replace ]; then
    if [ "$cowork_same_dir" = 1 ]; then
      # The team pack is the installed dir itself. SKILL.md and README.md are the
      # repo's and change; team.md and templates/ are the user's and stay.
      if cp "$cowork_tmp/SKILL.md" "$cowork_skill_dir/SKILL.md" \
         && cp "$cowork_dir/README.md" "$cowork_skill_dir/README.md"; then
        echo "cowork $cowork_skill_name: SKILL.md and README.md updated in $cowork_skill_dir"
      else
        echo "cowork $cowork_skill_name: writing SKILL.md or README.md failed — links skipped"
        cw_write_ok=0
      fi
    elif mkdir -p "$cowork_skill_dir" \
         && cp "$cowork_tmp/SKILL.md" "$cowork_skill_dir/SKILL.md" \
         && cp "$cowork_dir/README.md" "$cowork_skill_dir/README.md" \
         && cp "$cowork_pack/team.md" "$cowork_skill_dir/team.md" \
         && rm -rf "$cowork_skill_dir/templates.tmp" \
         && cp -R "$cowork_pack/templates" "$cowork_skill_dir/templates.tmp" \
         && rm -rf "$cowork_skill_dir/templates" \
         && mv "$cowork_skill_dir/templates.tmp" "$cowork_skill_dir/templates"; then
      echo "cowork $cowork_skill_name: installed to $cowork_skill_dir"
    else
      echo "cowork $cowork_skill_name: writing $cowork_skill_dir failed — links skipped"
      cw_write_ok=0
    fi
  fi

  # The hc links that were decided above to dangle now that the skill dir is written.
  # Each is removed only if it really dangles.
  if [ "$cw_write_ok" = 1 ]; then
    for cw_tpl in $cowork_hc_stale; do
      cw_old="$cowork_hc_dir/$cw_tpl"
      if [ -L "$cw_old" ] && [ ! -e "$cw_old" ]; then
        if rm -f "$cw_old"; then
          echo "cowork $cowork_skill_name: removed dangling hc link $cw_old"
        else
          echo "cowork $cowork_skill_name: could not remove $cw_old"
        fi
      fi
    done
  fi

  if [ "$cw_write_ok" = 1 ] && [ -f "$cowork_skill_dir/SKILL.md" ]; then
    while IFS='|' read -r cw_name cw_home cw_levels; do
      case " $cowork_links " in *" $cw_name "*) ;; *) continue ;; esac
      if ! mkdir -p "$cw_home/skills"; then
        echo "cowork $cowork_skill_name: cannot create $cw_home/skills"; continue
      fi
      cw_link="$cw_home/skills/$cowork_skill_name"
      if [ -d "$cw_link" ] && [ ! -L "$cw_link" ]; then
        rm -rf "$cw_link" || { echo "cowork $cowork_skill_name: cannot remove your $cw_link"; continue; }
      fi
      case "$cw_levels" in
        2) cw_rel="../../.agents/skills/$cowork_skill_name" ;;
        *) cw_rel="../../../.agents/skills/$cowork_skill_name" ;;
      esac
      if ln -sfn "$cw_rel" "$cw_link"; then
        echo "cowork $cowork_skill_name: linked $cw_link"
      else
        echo "cowork $cowork_skill_name: link failed at $cw_link"
      fi
    done <<EOF
$(skill_agent_homes)
EOF

    if [ -d "$cowork_hc_dir" ]; then
      for cw_tpl in $cowork_hc_links; do
        cw_hc_link="$cowork_hc_dir/$cw_tpl"
        if [ ! -f "$cowork_skill_dir/templates/$cw_tpl" ]; then
          echo "cowork $cowork_skill_name: hc link for $cw_tpl skipped (that template is not installed)"
          continue
        fi
        # ln -sfn onto a real directory does not fail: it creates the link inside it.
        if [ -d "$cw_hc_link" ] && [ ! -L "$cw_hc_link" ]; then
          echo "cowork $cowork_skill_name: hc link for $cw_tpl skipped ($cw_hc_link is a directory)"
          continue
        fi
        if ln -sfn "../../../.agents/skills/$cowork_skill_name/templates/$cw_tpl" "$cw_hc_link"; then
          echo "cowork $cowork_skill_name: hc template linked $cw_hc_link"
        else
          echo "cowork $cowork_skill_name: hc link failed for $cw_tpl"
        fi
      done
    fi
  fi
fi
check_failed=""
if command -v herdr-app >/dev/null 2>&1; then
  for name in $install_mods; do
    herdr-app check "$HOME_DIR/mods/$name" >/dev/null 2>&1 || check_failed="$check_failed $name"
  done
  [ -n "$check_failed" ] && echo "check FAILED:$check_failed" || echo "herdr-app check: all installed mods pass"
else
  echo "herdr-app not on PATH: run herdr-app check on each installed mod yourself."
fi

[ -n "$keys_conflicts" ] && echo "Keys you kept are listed above; take the package's binding by editing $HOME_DIR/keys.json."
echo "Done. Switch with: herdr-app do layout.switch '{\"name\":\"oh-my-herdr\"}'  (ctrl-shift-l switches back)"
