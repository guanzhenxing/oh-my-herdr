#!/bin/sh
# The --with-team stage: assemble one team's SKILL.md from the protocol and the
# team pack, install it, and link its templates into hc. Sourced by install.sh.

# team (--with-team --team): the team pack is located and validated here, before
# anything is decided, so a bad pack exits without a single write. A team pack is a
# directory holding team.md (frontmatter: name, prefix) and templates/. The name is
# the team's to choose: it is the name of the skill that gets installed.
team_dir=$(pwd)/skills/herdr-backend
# The known team packs: every subdirectory of ~/.config/herdr-teams, and the
# repo's own pack, which is this directory.
team_known_teams() {
  for team_root in "$HOME/.config/herdr-teams"; do
    [ -d "$team_root" ] || continue
    for team_sub in "$team_root"/*/; do
      if [ -d "$team_sub" ]; then echo "  ${team_sub%/}"; fi
    done
  done
  if [ -f "$team_dir/team.md" ]; then
    echo "  $team_dir ($(team_field "$team_dir/team.md" name))"
  fi
  return 0
}
# team_field <file> <key>: the value on the first "key: value" line of the leading
# frontmatter. Bracket classes are avoided: the awk on macOS rejects them in a built pattern.
team_field() {
  awk -v k="$2" '
    NR == 1 && $0 != "---" { exit }
    NR > 1 && $0 == "---" { exit }
    NR > 1 && index($0, k ":") == 1 { v = substr($0, length(k) + 2); sub(/^[ \t]*/, "", v); sub(/[ \t]+$/, "", v); print v; exit }
  ' "$1"
}
# team_name_ok <value>: lowercase letters, digits and hyphens, and not empty. The check
# runs under LC_ALL=C: in a UTF-8 locale the a-z range of a bracket expression can be
# collated so that it matches uppercase letters as well.
team_name_ok() { [ -n "$1" ] && printf '%s\n' "$1" | LC_ALL=C grep -q '^[a-z0-9-]*$'; }
team_die() { echo "team: $*"; exit 1; }

team_pack=""; team_skill_name=""; team_prefix=""
if [ "$TEAM_GIVEN" = 1 ] && [ "$WITH_TEAM" = 0 ]; then
  echo "--team is only used with --with-team"; exit 2
fi

team_validate() {
  if [ -z "$TEAM_ARG" ]; then
    echo "--with-team needs --team <team name or team pack path>. Known team packs:"
    team_known_teams
    exit 2
  fi
  # A value with a slash is a path: an absolute one as it is, a relative one against the
  # directory the installer was started from. A bare name is looked up, the local directory
  # first. So a team called "mods" is never taken for the repo's mods/.
  case "$TEAM_ARG" in
    /*) [ -d "$TEAM_ARG" ] && team_pack="${TEAM_ARG%/}" ;;
    */*) [ -d "$team_caller_dir/$TEAM_ARG" ] && team_pack="$team_caller_dir/${TEAM_ARG%/}" ;;
    *)
      if [ -d "$HOME/.config/herdr-teams/$TEAM_ARG" ]; then team_pack="$HOME/.config/herdr-teams/$TEAM_ARG"
      elif [ -f "$team_dir/team.md" ] && [ "$(team_field "$team_dir/team.md" name)" = "$TEAM_ARG" ]; then team_pack="$team_dir"
      fi
      ;;
  esac
  if [ -z "$team_pack" ]; then
    echo "team: team pack not found: $TEAM_ARG. Known team packs:"
    team_known_teams
    exit 1
  fi
  [ -f "$team_dir/PROTOCOL.md" ] && [ -f "$team_dir/README.md" ] || team_die "$team_dir/PROTOCOL.md or $team_dir/README.md missing from the repo"
  [ -f "$team_pack/team.md" ] || team_die "$team_pack/team.md missing"
  # Checked before the fields are read: with Windows line endings the first line is
  # not "---", the fields read as empty, and the message would blame the wrong thing.
  case "$(sed -n '1p' "$team_pack/team.md")" in *"$(printf '\r')"*)
    team_die "team.md: uses Windows line endings (CRLF); convert it to LF" ;;
  esac
  team_skill_name="$(team_field "$team_pack/team.md" name)"
  team_prefix="$(team_field "$team_pack/team.md" prefix)"
  # A skill name as the Agent Skills spec wants it: lowercase letters and digits
  # separated by single hyphens, at most 64 characters.
  printf '%s\n' "$team_skill_name" | LC_ALL=C grep -Eq '^[a-z0-9]+(-[a-z0-9]+)*$' \
    || team_die "team.md: 'name' must be lowercase letters and digits separated by single hyphens (got '$team_skill_name')"
  [ "${#team_skill_name}" -le 64 ] || team_die "team.md: 'name' is longer than 64 characters, which is the limit for a skill name"
  team_name_ok "$team_prefix" || team_die "team.md: 'prefix' must be set to lowercase letters, digits and hyphens (got '$team_prefix')"
  # hc limits template names to 32 characters, and "review" is the longest key.
  [ "${#team_prefix}" -le 25 ] || team_die "team.md: 'prefix' is longer than 25 characters, hc limits template names to 32"
  # The frontmatter must be closed. Without the closing line the two fields above
  # still read, and the body would be left out of SKILL.md.
  awk 'NR > 1 && $0 == "---" { found = 1; exit } END { exit !found }' "$team_pack/team.md" \
    || team_die "team.md: frontmatter is not closed by a --- line"
  # The four section headings the generic protocol refers to. A pack must have all of them.
  for cw_heading in "角色与模板" "命名前缀" "工作区" "路径"; do
    grep -q "^### $cw_heading\$" "$team_pack/team.md" || team_die "team.md: required section '### $cw_heading' missing"
  done
  for cw_key in arch dev review test run; do
    [ -f "$team_pack/templates/$team_prefix-$cw_key.md" ] || team_die "templates/$team_prefix-$cw_key.md missing from the team pack"
  done
  # Every template, the five roles and any extra one. The frontmatter must agree with
  # the file name, the name may be 32 characters at most, and it may hold no whitespace:
  # the list of links to create is split on spaces.
  for cw_tpl in "$team_pack"/templates/*.md; do
    [ -f "$cw_tpl" ] || continue
    cw_name="${cw_tpl##*/}"; cw_name="${cw_name%.md}"
    if [ "${#cw_name}" -gt 32 ] || printf '%s\n' "$cw_name" | grep -q '[[:space:]]'; then
      team_die "templates/${cw_tpl##*/}: the file name must be at most 32 characters and hold no whitespace (got '$cw_name')"
    fi
    [ "$(team_field "$cw_tpl" name)" = "$cw_name" ] || team_die "templates/${cw_tpl##*/}: frontmatter 'name' must be $cw_name"
  done
  [ "$(grep -c '^name: TEAM-SKILL$' "$team_dir/PROTOCOL.md")" = 1 ] || team_die "$team_dir/PROTOCOL.md must hold exactly one line 'name: TEAM-SKILL'"
  team_skill_dir="$HOME/.agents/skills/$team_skill_name"
  # herdr-cowork is the skill that --with-skills installs from skills/herdr-cowork/.
  [ "$team_skill_name" != herdr-cowork ] || team_die "team.md: 'name' must not be herdr-cowork: that is the name of the skill installed by --with-skills"
  # The name is the team's to choose, so it can be the name of a skill that is already
  # here. A directory without a team.md is not a team skill: it is never written to,
  # not even with --yes.
  if [ -d "$team_skill_dir" ] && [ ! -L "$team_skill_dir" ] && [ ! -f "$team_skill_dir/team.md" ]; then
    team_die "$team_skill_dir already exists and is not a team skill (no team.md in it); give this team another name in team.md"
  fi
  return 0
}

team_decide() {
team_boundary='<!-- 以上是通用协议，由 oh-my-herdr 的 skills/herdr-backend/PROTOCOL.md 提供；以下是本团队配置，安装时取自团队包的 team.md。个人改动请落在团队包或装好的模板里（改 team.md 后要重跑安装器才生效），不要直接改本文件。 -->'
team_hc_dir="$HOME/.config/herdr-core/templates"
team_skill_state=""; team_links=""; team_link_notes=""; team_hc_links=""; cw_notes=""
team_stale=""; team_hc_stale=""
team_same_dir=0
team_active=0
# team_installed_is_current: the installed skill dir holds exactly what would be written.
team_installed_is_current() {
  cmp -s "$team_tmp/SKILL.md" "$team_skill_dir/SKILL.md" &&
  cmp -s "$team_dir/README.md" "$team_skill_dir/README.md" &&
  cmp -s "$team_pack/team.md" "$team_skill_dir/team.md" &&
  diff -rq -x .DS_Store "$team_pack/templates" "$team_skill_dir/templates" >/dev/null 2>&1
}
# team_link_target <symlink to a file>: the physical path of the file it points to.
# An hc template link is "correct" when this equals the path of the installed template.
team_link_target() (
  cw_lt="$(readlink "$1")"
  case "$cw_lt" in
    /*) cw_td="$(dirname "$cw_lt")" ;;
    *) cw_td="$(dirname "$1")/$(dirname "$cw_lt")" ;;
  esac
  printf '%s/%s\n' "$(cd -P "$cw_td" 2>/dev/null && pwd)" "$(basename "$cw_lt")"
)
# team_link_owner <symlink>: the name of the team skill whose templates the link
# points into, or nothing. hc keeps the templates of every team in one directory, so
# two teams that share a prefix would each take the other's templates over. A team
# skill is known by the team.md in its directory, whatever the skill is called.
team_link_owner() {
  cw_lo="$(team_link_target "$1")"
  case "$cw_lo" in */templates/*.md) ;; *) return 0 ;; esac
  cw_lo="$(dirname "$(dirname "$cw_lo")")"
  [ -f "$cw_lo/team.md" ] || return 0
  cw_lo="$(team_field "$cw_lo/team.md" name)"
  if [ -n "$cw_lo" ] && [ "$cw_lo" != "$team_skill_name" ]; then printf '%s\n' "$cw_lo"; fi
}
  # The installed dir is itself a valid team pack. When it is the one named, only the
  # repo's two files may change.
  if [ -d "$team_pack" ] && [ -d "$team_skill_dir" ] &&
     [ "$(cd -P "$team_pack" 2>/dev/null && pwd)" = "$(cd -P "$team_skill_dir" 2>/dev/null && pwd)" ]; then
    team_same_dir=1
  fi
  team_tmp=$(mktemp -d)
  # The protocol with every TEAM-SKILL replaced by the skill's name, which fills the
  # name line and the sentence that tells members which skills not to load; then a
  # blank line, the boundary, a blank line, and the body of team.md without the blank
  # lines that may follow its frontmatter. awk ends the protocol with a newline even
  # when the file has none, so the result is the same whatever its last line looks like.
  {
    awk -v s="$team_skill_name" '{ gsub(/TEAM-SKILL/, s) } 1' "$team_dir/PROTOCOL.md"
    printf '\n%s\n\n' "$team_boundary"
    awk 'c < 2 { if ($0 == "---") c++; next } !started && /^$/ { next } { started = 1; print }' "$team_pack/team.md"
  } > "$team_tmp/SKILL.md"

  if [ -L "$team_skill_dir" ]; then
    team_skill_state="kept (is a symlink; never touched, even with --yes)"
  elif [ ! -e "$team_skill_dir" ]; then
    team_skill_state="install"
  elif [ ! -d "$team_skill_dir" ]; then
    team_skill_state="kept (is not a directory; never touched, even with --yes)"
  elif team_installed_is_current; then
    team_skill_state="up to date"
  elif [ "$YES" = 1 ]; then
    team_skill_state="replace"
  else
    team_skill_state="kept (differs; rerun with --yes to overwrite)"
  fi

  # Links are planned only when the skill dir has a readable SKILL.md or gets one now.
  # Deciding that here keeps a dry run honest about what a real run would do.
  if [ -f "$team_skill_dir/SKILL.md" ] || [ "$team_skill_state" = install ] || [ "$team_skill_state" = replace ]; then
    team_active=1
  elif [ -L "$team_skill_dir" ]; then
    cw_notes="$cw_notes
links skipped (the skill dir is a symlink to a place without a SKILL.md; fix or remove it yourself; --yes never touches it)"
  elif [ ! -d "$team_skill_dir" ]; then
    cw_notes="$cw_notes
links skipped ($team_skill_dir is not a directory; move it away yourself)"
  else
    cw_notes="$cw_notes
links skipped (the kept copy in $team_skill_dir has no readable SKILL.md; rerun with --yes to replace it)"
  fi

  # The pack and the installed dir are two directories: say when the installed team.md
  # or templates no longer equal the pack's. --yes then overwrites them. "以后 X 都用 Y"
  # edits the installed template, so that is how such an edit is lost.
  if [ "$team_same_dir" = 0 ] && { [ "$team_skill_state" = replace ] || [ "$team_skill_state" = "kept (differs; rerun with --yes to overwrite)" ]; }; then
    if ! cmp -s "$team_pack/team.md" "$team_skill_dir/team.md" \
       || ! diff -rq -x .DS_Store "$team_pack/templates" "$team_skill_dir/templates" >/dev/null 2>&1; then
      cw_notes="$cw_notes
$team_skill_dir: its team.md or templates/ differ from the team pack's (edited in place, or an older pack); --yes overwrites them. To keep them, run with --team $team_skill_dir"
    fi
  fi

  # What a write removes. Templates the pack no longer has go when the skill dir is
  # replaced. hc links into this team's templates dangle when their template is not in
  # the pack, or is already gone when the installed dir is the pack. Decided here, so
  # that a dry run lists them too.
  if [ "$team_skill_state" = install ] || [ "$team_skill_state" = replace ]; then
    if [ "$team_same_dir" = 0 ] && [ -d "$team_skill_dir/templates" ]; then
      for cw_old in "$team_skill_dir"/templates/*.md; do
        [ -f "$cw_old" ] || continue
        [ -f "$team_pack/templates/${cw_old##*/}" ] || team_stale="$team_stale ${cw_old##*/}"
      done
    fi
    if [ -d "$team_hc_dir" ]; then
      for cw_old in "$team_hc_dir"/*; do
        [ -L "$cw_old" ] || continue
        case "$(readlink "$cw_old")" in *"skills/$team_skill_name/templates/"*) ;; *) continue ;; esac
        if [ "$team_same_dir" = 1 ]; then
          [ -f "$team_skill_dir/templates/${cw_old##*/}" ] && continue
        else
          [ -f "$team_pack/templates/${cw_old##*/}" ] && continue
        fi
        team_hc_stale="$team_hc_stale ${cw_old##*/}"
      done
    fi
  fi

  # Agent links. Whatever a run would remove or replace at one of these positions is
  # said in the notes: the report is all a dry run has.
  if [ "$team_active" = 1 ]; then
    while IFS='|' read -r cw_name cw_home cw_levels; do
      cw_link="$cw_home/skills/$team_skill_name"
      if [ ! -d "$cw_home" ]; then
        cw_link_notes="$cw_link_notes
$cw_name: skipped ($cw_home not installed)"
      elif [ -L "$cw_link" ] && [ -e "$team_skill_dir" ] && [ "$(cd -P "$cw_link" 2>/dev/null && pwd)" = "$(cd -P "$team_skill_dir" 2>/dev/null && pwd)" ]; then
        cw_link_notes="$cw_link_notes
$cw_name: up to date"
      elif [ ! -e "$cw_link" ]; then
        team_links="$team_links $cw_name"
      elif [ "$YES" = 1 ]; then
        team_links="$team_links $cw_name"
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
  if [ "$team_active" = 0 ]; then
    :    # already reported above
  elif [ ! -d "$team_hc_dir" ]; then
    cw_notes="$cw_notes
hc templates skipped ($team_hc_dir does not exist; create it and rerun)"
  else
    for cw_src in "$team_pack"/templates/*.md; do
      [ -f "$cw_src" ] || continue
      cw_tpl="${cw_src##*/}"
      # A kept skill dir may lack a template of the pack. There is nothing to link to then.
      if [ "$team_skill_state" != install ] && [ "$team_skill_state" != replace ] && [ ! -f "$team_skill_dir/templates/$cw_tpl" ]; then
        cw_notes="$cw_notes
$cw_tpl: skipped (that template is not installed in the kept skill dir)"
        continue
      fi
      cw_hc_link="$team_hc_dir/$cw_tpl"
      cw_hc_target="$team_skill_dir/templates/$cw_tpl"
      # What the link will point at once this run is over: the pack's template when the
      # skill dir is written, the installed one when it is kept.
      cw_will_be="$cw_src"
      if [ "$team_skill_state" != install ] && [ "$team_skill_state" != replace ]; then cw_will_be="$cw_hc_target"; fi
      # The physical path of the target. The assignment is guarded: cd fails until the
      # templates exist, and an assignment whose command substitution fails ends the
      # script under set -e.
      cw_target_phys="$cw_hc_target"
      if [ -d "$team_skill_dir/templates" ]; then
        cw_target_phys="$(cd -P "$team_skill_dir/templates" 2>/dev/null && pwd)/$cw_tpl"
      fi
      if [ -L "$cw_hc_link" ] && [ -e "$cw_hc_target" ] && [ "$(team_link_target "$cw_hc_link")" = "$cw_target_phys" ]; then
        cw_notes="$cw_notes
$cw_tpl: up to date"
      elif [ -L "$cw_hc_link" ] && [ ! -e "$cw_hc_link" ]; then
        team_hc_links="$team_hc_links $cw_tpl"    # dangling
      elif [ -L "$cw_hc_link" ]; then
        cw_owner="$(team_link_owner "$cw_hc_link")"
        if [ -n "$cw_owner" ]; then
          # Refused before anything is written. With --yes this team would take the
          # other team's templates over, one link at a time, without a word.
          team_die "team.md: prefix '$team_prefix' is already used by the team skill '$cw_owner' ($cw_hc_link links into its skill dir); two teams must not share a prefix"
        elif [ "$YES" = 1 ]; then
          team_hc_links="$team_hc_links $cw_tpl"
          cw_notes="$cw_notes
$cw_tpl: replaces the link that points elsewhere"
        else
          cw_notes="$cw_notes
$cw_tpl: kept (link points elsewhere; --yes replaces it)"
        fi
      elif [ ! -e "$cw_hc_link" ]; then
        team_hc_links="$team_hc_links $cw_tpl"
      elif [ -f "$cw_hc_link" ] && cmp -s "$cw_will_be" "$cw_hc_link"; then
        team_hc_links="$team_hc_links $cw_tpl"
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
  return 0
}

team_report() {
  say "team $team_skill_name: team pack $team_pack"
  say "team $team_skill_name: $team_skill_dir $team_skill_state"
  [ -n "$team_links" ] && say "team $team_skill_name: skill links to create:$team_links"
  [ -n "$team_hc_links" ] && say "team $team_skill_name: hc template links to create:$team_hc_links"
  [ -n "$team_stale" ] && say "team $team_skill_name: templates to remove from the installed dir:$team_stale"
  [ -n "$team_hc_stale" ] && say "team $team_skill_name: hc links to remove, they would dangle:$team_hc_stale"
  # The same shape as the herdr-cowork notes: printf '%s' without a trailing newline, so
  # the loop ends on a non-empty note. A loop that ends on an empty line returns 1, which
  # would end the script under set -e right after the report.
  for cw_note_list in "$cw_link_notes" "$cw_notes"; do
    printf '%s' "$cw_note_list" | while IFS= read -r cw_note || [ -n "$cw_note" ]; do
      [ -n "$cw_note" ] && say "team $team_skill_name: $cw_note"
    done
  done
  return 0
}

team_write() {
  cw_write_ok=1
  if [ "$team_skill_state" = install ] || [ "$team_skill_state" = replace ]; then
    if [ "$team_same_dir" = 1 ]; then
      # The team pack is the installed dir itself. SKILL.md and README.md are the
      # repo's and change; team.md and templates/ are the user's and stay.
      if cp "$team_tmp/SKILL.md" "$team_skill_dir/SKILL.md" \
         && cp "$team_dir/README.md" "$team_skill_dir/README.md"; then
        echo "team $team_skill_name: SKILL.md and README.md updated in $team_skill_dir"
      else
        echo "team $team_skill_name: writing SKILL.md or README.md failed — links skipped"
        cw_write_ok=0
      fi
    elif mkdir -p "$team_skill_dir" \
         && cp "$team_tmp/SKILL.md" "$team_skill_dir/SKILL.md" \
         && cp "$team_dir/README.md" "$team_skill_dir/README.md" \
         && cp "$team_pack/team.md" "$team_skill_dir/team.md" \
         && rm -rf "$team_skill_dir/templates.tmp" \
         && cp -R "$team_pack/templates" "$team_skill_dir/templates.tmp" \
         && rm -rf "$team_skill_dir/templates" \
         && mv "$team_skill_dir/templates.tmp" "$team_skill_dir/templates"; then
      echo "team $team_skill_name: installed to $team_skill_dir"
    else
      echo "team $team_skill_name: writing $team_skill_dir failed — links skipped"
      cw_write_ok=0
    fi
  fi

  # The hc links that were decided above to dangle now that the skill dir is written.
  # Each is removed only if it really dangles.
  if [ "$cw_write_ok" = 1 ]; then
    for cw_tpl in $team_hc_stale; do
      cw_old="$team_hc_dir/$cw_tpl"
      if [ -L "$cw_old" ] && [ ! -e "$cw_old" ]; then
        if rm -f "$cw_old"; then
          echo "team $team_skill_name: removed dangling hc link $cw_old"
        else
          echo "team $team_skill_name: could not remove $cw_old"
        fi
      fi
    done
  fi

  if [ "$cw_write_ok" = 1 ] && [ -f "$team_skill_dir/SKILL.md" ]; then
    while IFS='|' read -r cw_name cw_home cw_levels; do
      case " $team_links " in *" $cw_name "*) ;; *) continue ;; esac
      if ! mkdir -p "$cw_home/skills"; then
        echo "team $team_skill_name: cannot create $cw_home/skills"; continue
      fi
      cw_link="$cw_home/skills/$team_skill_name"
      if [ -d "$cw_link" ] && [ ! -L "$cw_link" ]; then
        rm -rf "$cw_link" || { echo "team $team_skill_name: cannot remove your $cw_link"; continue; }
      fi
      case "$cw_levels" in
        2) cw_rel="../../.agents/skills/$team_skill_name" ;;
        *) cw_rel="../../../.agents/skills/$team_skill_name" ;;
      esac
      if ln -sfn "$cw_rel" "$cw_link"; then
        echo "team $team_skill_name: linked $cw_link"
      else
        echo "team $team_skill_name: link failed at $cw_link"
      fi
    done <<EOF
$(skill_agent_homes)
EOF

    if [ -d "$team_hc_dir" ]; then
      for cw_tpl in $team_hc_links; do
        cw_hc_link="$team_hc_dir/$cw_tpl"
        if [ ! -f "$team_skill_dir/templates/$cw_tpl" ]; then
          echo "team $team_skill_name: hc link for $cw_tpl skipped (that template is not installed)"
          continue
        fi
        # ln -sfn onto a real directory does not fail: it creates the link inside it.
        if [ -d "$cw_hc_link" ] && [ ! -L "$cw_hc_link" ]; then
          echo "team $team_skill_name: hc link for $cw_tpl skipped ($cw_hc_link is a directory)"
          continue
        fi
        if ln -sfn "../../../.agents/skills/$team_skill_name/templates/$cw_tpl" "$cw_hc_link"; then
          echo "team $team_skill_name: hc template linked $cw_hc_link"
        else
          echo "team $team_skill_name: hc link failed for $cw_tpl"
        fi
      done
    fi
  fi
  return 0
}
