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
#   sh install.sh --with-team --team <name|path>  also install one team skill and link its
#                              templates into hc (opt-in; see skills/herdr-backend/README.md)
set -e
# Where the user ran the installer: a relative --team path is resolved against it.
team_caller_dir=$(pwd)
cd "$(dirname "$0")"
HOME_DIR="${HERDR_APP_HOME:-$HOME/.config/herdr-app}"
YES=0
DRY=0
WITH_SKILLS=0
WITH_TEAM=0
TEAM_ARG=""
TEAM_GIVEN=0
TEAM_NEXT=0
team_tmp=""
for arg in "$@"; do
  if [ "$TEAM_NEXT" = 1 ]; then
    # The value of --team never starts with a dash: another flag here means there was no value.
    case "$arg" in
      --*) echo "--team needs a value: --team <team name or team pack path>"; exit 2 ;;
    esac
    TEAM_ARG="$arg"; TEAM_GIVEN=1; TEAM_NEXT=0; continue
  fi
  case "$arg" in
    --yes) YES=1 ;;
    --dry-run) DRY=1 ;;
    --with-skills) WITH_SKILLS=1 ;;
    --with-team) WITH_TEAM=1 ;;
    --team) TEAM_NEXT=1 ;;
    *) echo "unknown flag: $arg (use --yes, --dry-run, --with-skills, --with-team, --team <name|path>)"; exit 2 ;;
  esac
done
[ "$TEAM_NEXT" = 1 ] && { echo "--team needs a value: --team <team name or team pack path>"; exit 2; }

command -v jq >/dev/null 2>&1 || { echo "install.sh needs jq"; exit 1; }
[ -f layouts/oh-my-herdr.json ] || { echo "layouts/oh-my-herdr.json missing from the repo"; exit 1; }
# The two stages live with their files; each is sourced here, not run as a program.
for stage in skills/herdr-cowork/install.sh skills/herdr-backend/install.sh; do
  [ -f "$stage" ] || { echo "install.sh: $stage missing from the repo"; exit 1; }
  . "./$stage"
done
if [ "$WITH_SKILLS" = 1 ]; then skill_validate; fi
if [ "$WITH_TEAM" = 1 ]; then team_validate; fi
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
trap 'rm -rf "$keys_dir" "$layout_tmp"; [ -z "$team_tmp" ] || rm -rf "$team_tmp"' EXIT
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
# --with-skills and --with-team. An agent whose home directory is missing is
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
if [ "$WITH_SKILLS" = 1 ]; then skill_decide; fi
if [ "$WITH_TEAM" = 1 ]; then team_decide; fi

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

if [ "$WITH_SKILLS" = 1 ]; then skill_report; fi

if [ "$WITH_TEAM" = 1 ]; then team_report; fi
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
if [ "$WITH_SKILLS" = 1 ]; then skill_write; fi

if [ "$WITH_TEAM" = 1 ]; then team_write; fi
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
