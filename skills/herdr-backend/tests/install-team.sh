#!/bin/sh
# Acceptance tests for install.sh's team stage (--with-team --team). They cover the
# checks listed in docs/superpowers/specs/2026-11-24-team-framework-design.md and
# every row of the installer's three decision tables.
#
# The real installer runs against throwaway HOME directories inside one temp dir, so
# nothing outside it is written and the real home is never touched. A private PATH
# holds stub herdr-automations and herdr-app commands: the installer then neither
# builds nor downloads the CLI and never talks to a real Herdr.
#
#   sh skills/herdr-backend/tests/install-team.sh        exit 0 when every check passes
set -u

REPO=$(cd "$(dirname "$0")/../../.." && pwd)
INSTALL="$REPO/install.sh"
PROTOCOL="$REPO/skills/herdr-backend/PROTOCOL.md"
EXAMPLE="$REPO/skills/herdr-backend/teams/example"
BOUNDARY='<!-- 以上是通用协议，由 oh-my-herdr 的 skills/herdr-backend/PROTOCOL.md 提供；以下是本团队配置，安装时取自团队包的 team.md。个人改动请落在团队包或装好的模板里（改 team.md 后要重跑安装器才生效），不要直接改本文件。 -->'

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
# jq and rsync are needed. Whatever else the real PATH holds is not: it could bring a
# real herdr-app along.
TOOLS=$(dirname "$(command -v jq || echo /nonexistent/jq)"):$(dirname "$(command -v rsync || echo /nonexistent/rsync)")

pass=0
fail=0
ok() { pass=$((pass + 1)); echo "ok   $1"; }
bad() { fail=$((fail + 1)); echo "FAIL $1 — $2"; }
# check <label> <expected> <actual>
check() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected [$2], got [$3]"; fi; }
# has / lacks <label> <text>: the last installer output contains / does not contain the text
has() { case "$OUT" in *"$2"*) ok "$1" ;; *) bad "$1" "the output lacks [$2]" ;; esac; }
lacks() { case "$OUT" in *"$2"*) bad "$1" "the output unexpectedly contains [$2]" ;; *) ok "$1" ;; esac; }

n=0
H=""    # the throwaway HOME of the current test
OUT=""  # output of the last installer run
RC=0    # its exit status
P=""    # the team pack of the current test

new_home() {
  n=$((n + 1)); H="$WORK/home$n"
  mkdir -p "$H/bin"
  printf '#!/bin/sh\nexit 0\n' > "$H/bin/herdr-automations"
  printf '#!/bin/sh\nexit 0\n' > "$H/bin/herdr-app"
  chmod +x "$H/bin/herdr-automations" "$H/bin/herdr-app"
}

# run <installer arguments>: runs the installer inside the current throwaway HOME
run() {
  # LC_ALL=C keeps the order in which the installer lists and links templates the same
  # on every machine, so the report can be compared line by line.
  OUT=$(HOME="$H" HERDR_APP_HOME="$H/.config/herdr-app" PATH="$H/bin:$TOOLS:/usr/bin:/bin" LC_ALL=C /bin/sh "$INSTALL" "$@" 2>&1)
  RC=$?
}

all_agent_homes() { mkdir -p "$H/.claude" "$H/.codex" "$H/.gemini" "$H/.config/opencode" "$H/.pi/agent"; }
hc_home() { mkdir -p "$H/.config/herdr-core/templates"; }
# skill_dir <skill name>: where a team skill is installed. The directory carries the
# name written in the team pack's team.md, nothing else.
skill_dir() { printf '%s/.agents/skills/%s' "$H" "$1"; }
hc_link() { printf '%s/.config/herdr-core/templates/%s' "$H" "$1"; }
entries() { find "$H" 2>/dev/null | wc -l | tr -d ' '; }
# isdir <path>: "directory" only for a real directory, not for a symlink to one
isdir() { if [ -d "$1" ] && [ ! -L "$1" ]; then echo directory; else echo "something else"; fi; }
# team_lines: the team report lines of the last installer output. They are told
# apart by their shape, "team <skill name>: …", because a path in the output can
# itself hold the word "team", and other stages of the installer say "kept" and
# "skipped" too.
team_lines() { printf '%s\n' "$OUT" | grep 'team [a-z0-9-]*:'; }

# link_ok <label> <link> <directory it must resolve to>
link_ok() {
  if [ -L "$2" ] && [ "$(cd -P "$2" 2>/dev/null && pwd)" = "$(cd -P "$3" 2>/dev/null && pwd)" ]; then
    ok "$1"
  else
    bad "$1" "$2 does not resolve to $3"
  fi
}

# make_pack <directory> <skill name> <prefix>: a team pack copied from the example
# and renamed. The directory's own name is left to the caller: it need not be either.
make_pack() {
  mkdir -p "$1/templates"
  sed -e "s/^name: herdr-example$/name: $2/" -e "s/^prefix: example$/prefix: $3/" "$EXAMPLE/team.md" > "$1/team.md"
  for f in "$EXAMPLE"/templates/*.md; do
    sed "s/^name: example-/name: $3-/" "$f" > "$1/templates/$3-${f##*/example-}"
  done
}

# expected_skill <team pack directory> <skill name>: what the assembled SKILL.md must
# equal. Built independently of the installer: the boundary is the second "---" line
# of team.md, and every TEAM-SKILL in the protocol becomes the skill's name.
expected_skill() {
  sed "s/TEAM-SKILL/$2/g" "$PROTOCOL"
  printf '\n%s\n\n' "$BOUNDARY"
  awk 'skipping && /^$/ { next } { skipping = 0 } found { print; next } /^---$/ && ++dashes == 2 { found = 1; skipping = 1 }' "$1/team.md"
}

# rejects_pack <label> <message fragment> <mutation>: an invalid pack is refused with
# exit status 1, a message, and not one write.
rejects_pack() {
  new_home; all_agent_homes; hc_home
  P="$H/.config/herdr-teams/bad"
  make_pack "$P" bad bad
  "$3"
  before=$(entries)
  run --with-team --team bad
  check "$1: exit status" 1 "$RC"
  has "$1: message" "$2"
  check "$1: zero writes" "$before" "$(entries)"
}

drop_prefix() { grep -v '^prefix: ' "$P/team.md" > "$P/team.new"; mv "$P/team.new" "$P/team.md"; }
drop_name() { grep -v '^name: ' "$P/team.md" > "$P/team.new"; mv "$P/team.new" "$P/team.md"; }
drop_section() { grep -v '^### 工作区$' "$P/team.md" > "$P/team.new"; mv "$P/team.new" "$P/team.md"; }
drop_template() { rm "$P/templates/bad-run.md"; }
wrong_name() { sed 's/^name: bad-run$/name: something-else/' "$P/templates/bad-run.md" > "$P/bad-run.new"; mv "$P/bad-run.new" "$P/templates/bad-run.md"; }
no_close() { awk 'NR != 1 && $0 == "---" { next } { print }' "$P/team.md" > "$P/team.new"; mv "$P/team.new" "$P/team.md"; }
crlf() { sed 's/$/'"$(printf '\r')"'/' "$P/team.md" > "$P/team.new"; mv "$P/team.new" "$P/team.md"; }
extra_wrong_name() { sed 's/^name: example-arch$/name: something-else/' "$EXAMPLE/templates/example-arch.md" > "$P/templates/bad-extra.md"; }
extra_long_name() { sed 's/^name: example-arch$/name: bad-extra-abcdefghijklmnopqrstuvwxyz/' "$EXAMPLE/templates/example-arch.md" > "$P/templates/bad-extra-abcdefghijklmnopqrstuvwxyz.md"; }
extra_space_name() { sed 's/^name: example-arch$/name: bad extra/' "$EXAMPLE/templates/example-arch.md" > "$P/templates/bad extra.md"; }

echo "1. syntax"
OUT=$(sh -n "$INSTALL" 2>&1)
check "sh -n install.sh" 0 "$?"

echo "2. without --with-team"
new_home; all_agent_homes
run
check "exit status" 0 "$RC"
check "no team report" 0 "$(team_lines | wc -l | tr -d ' ')"
if [ -e "$H/.agents" ]; then bad "nothing installed" "$H/.agents exists"; else ok "nothing installed"; fi

echo "3. --with-skills still installs herdr-cowork"
new_home; all_agent_homes
run --with-skills
check "exit status" 0 "$RC"
if cmp -s "$REPO/skills/herdr-cowork/SKILL.md" "$H/.agents/skills/herdr-cowork/SKILL.md"; then
  ok "the copy equals the repo's SKILL.md"
else
  bad "the copy equals the repo's SKILL.md" "it differs"
fi
for agent in .claude .codex .gemini .config/opencode .pi/agent; do
  link_ok "herdr-cowork link $agent" "$H/$agent/skills/herdr-cowork" "$H/.agents/skills/herdr-cowork"
done

echo "3b. --with-skills and --with-team together"
new_home; all_agent_homes; hc_home
run --with-team --team example --with-skills
check "exit status" 0 "$RC"
link_ok "herdr-cowork is linked" "$H/.claude/skills/herdr-cowork" "$H/.agents/skills/herdr-cowork"
link_ok "the team skill is linked beside it" "$H/.claude/skills/herdr-example" "$(skill_dir herdr-example)"

echo "4. --with-team without --team"
new_home; before=$(entries)
run --with-team
check "exit status" 2 "$RC"
has "says what is missing" "--with-team needs --team"
has "lists the known team packs" "$EXAMPLE"
check "zero writes" "$before" "$(entries)"

echo "5. --team without --with-team"
new_home; before=$(entries)
run --team example
check "exit status" 2 "$RC"
has "says how the flag is used" "--team is only used with --with-team"
check "zero writes" "$before" "$(entries)"
run --team ""
check "an empty value counts as given" 2 "$RC"

echo "6. --team without a value"
new_home; before=$(entries)
run --with-team --team
check "exit status" 2 "$RC"
has "says the flag needs a value" "--team needs a value"
check "zero writes" "$before" "$(entries)"
run --with-team --team --dry-run
check "another flag is not taken as the value" 2 "$RC"
has "and it still says so" "--team needs a value"
check "zero writes" "$before" "$(entries)"
run --bogus
check "an unknown flag" 2 "$RC"
has "the usage line lists the new flags" "--with-team, --team <name|path>"

echo "7. an unknown team"
new_home; before=$(entries)
run --with-team --team nope
check "exit status" 1 "$RC"
has "says it was not found" "team pack not found: nope"
check "zero writes" "$before" "$(entries)"
run --with-team --team "$H/nowhere"
check "a path that does not exist: exit status" 1 "$RC"
has "and it is reported as not found" "team pack not found: $H/nowhere"
check "zero writes" "$before" "$(entries)"

echo "8. dry run"
new_home; all_agent_homes; hc_home; before=$(entries)
S=$(skill_dir herdr-example)
run --with-team --team example --dry-run
check "exit status" 0 "$RC"
has "names the team pack" "[dry] team herdr-example: team pack $EXAMPLE"
has "reports the install" "[dry] team herdr-example: $S install"
has "reports the agent links" "[dry] team herdr-example: skill links to create: claude codex gemini opencode pi"
has "reports the hc links" "[dry] team herdr-example: hc template links to create: example-arch.md example-dev.md example-review.md example-run.md example-test.md"
check "zero writes" "$before" "$(entries)"

echo "9. a fresh install"
run --with-team --team example
check "exit status" 0 "$RC"
has "says it installed" "team herdr-example: installed to $S"
expected_skill "$EXAMPLE" herdr-example > "$WORK/expected.md"
if cmp -s "$WORK/expected.md" "$S/SKILL.md"; then
  ok "SKILL.md is the assembled file"
else
  bad "SKILL.md is the assembled file" "it differs from protocol + boundary + the body of team.md"
fi
check "exactly one real name line" 1 "$(grep -c '^name: herdr-example$' "$S/SKILL.md")"
check "no placeholder left" 0 "$(grep -c 'TEAM-SKILL' "$S/SKILL.md")"
check "the fixed sentence names this skill and herdr-cowork" 1 "$(grep -c '不加载调度类的 skill（herdr-cowork、herdr-example）' "$S/SKILL.md")"
for pair in "README.md:$REPO/skills/herdr-backend/README.md" "team.md:$EXAMPLE/team.md"; do
  if cmp -s "${pair#*:}" "$S/${pair%%:*}"; then ok "the copy of ${pair%%:*} is exact"
  else bad "the copy of ${pair%%:*} is exact" "it differs"; fi
done
if diff -rq -x .DS_Store "$EXAMPLE/templates" "$S/templates" >/dev/null 2>&1; then
  ok "the copy of templates/ is exact"
else
  bad "the copy of templates/ is exact" "it differs"
fi
for agent in .claude .codex .gemini .config/opencode .pi/agent; do
  link_ok "agent link $agent" "$H/$agent/skills/herdr-example" "$S"
done
for key in arch dev review test run; do
  t="example-$key.md"
  if [ -L "$(hc_link "$t")" ] \
     && [ "$(readlink "$(hc_link "$t")")" = "../../../.agents/skills/herdr-example/templates/$t" ] \
     && cmp -s "$S/templates/$t" "$(hc_link "$t")"; then
    ok "hc link $t"
  else
    bad "hc link $t" "missing, not relative to the skill directory, or not readable through the link"
  fi
done

echo "10. running again changes nothing"
run --with-team --team example
check "exit status" 0 "$RC"
has "the skill directory is up to date" "team herdr-example: $S up to date"
lacks "nothing to create" "to create"
# Ten links: five agents and five templates. One kept or skipped link would be a regression.
check "all ten links are up to date" 10 "$(team_lines | grep -c ': up to date$')"
check "no team link is kept or skipped" 0 "$(team_lines | grep -c 'kept\|skipped')"

echo "11. a kept skill directory that lacks a template says so"
rm "$S/templates/example-test.md"
run --with-team --team example
has "the directory is kept" "team herdr-example: $S kept (differs; rerun with --yes to overwrite)"
has "the missing template is reported" "example-test.md: skipped (that template is not installed in the kept skill dir)"
lacks "and is not listed as work to do" "hc template links to create"
run --with-team --team example --yes
if [ -f "$S/templates/example-test.md" ] && cmp -s "$WORK/expected.md" "$S/SKILL.md"; then ok "restored with --yes"
else bad "restored with --yes" "the template or SKILL.md is still missing"; fi

echo "12. a changed SKILL.md is kept, and --yes restores it"
printf '# a local edit\n' >> "$S/SKILL.md"
printf 'keep me\n' > "$S/notes.txt"
# Correct links written another way, absolute here, must not be rebuilt.
rm "$H/.claude/skills/herdr-example"
ln -s "$S" "$H/.claude/skills/herdr-example"
rm "$(hc_link example-arch.md)"
ln -s "$S/templates/example-arch.md" "$(hc_link example-arch.md)"
run --with-team --team example
has "the agent link still counts as correct" "claude: up to date"
has "the hc link still counts as correct" "example-arch.md: up to date"
has "kept without --yes" "team herdr-example: $S kept (differs; rerun with --yes to overwrite)"
check "the file is untouched" "# a local edit" "$(tail -n 1 "$S/SKILL.md")"
run --with-team --team example --yes
has "replaced with --yes" "team herdr-example: $S replace"
if cmp -s "$WORK/expected.md" "$S/SKILL.md"; then ok "SKILL.md is restored"
else bad "SKILL.md is restored" "it still differs"; fi
check "a file the installer does not manage is kept" "keep me" "$(cat "$S/notes.txt")"
check "a correct agent link is not rebuilt" "$S" "$(readlink "$H/.claude/skills/herdr-example")"
check "a correct hc link is not rebuilt" "$S/templates/example-arch.md" "$(readlink "$(hc_link example-arch.md)")"

echo "12b. edits made in the installed directory: reported, overwritten from the pack, kept by an in-place upgrade"
new_home; all_agent_homes; hc_home
S=$(skill_dir herdr-example)
run --with-team --team example
printf '仓别名：demo2→/nowhere/demo2\n' >> "$S/team.md"
sed 's/^command: .*$/command: echo my-model/' "$S/templates/example-run.md" > "$S/run.new"
mv "$S/run.new" "$S/templates/example-run.md"
run --with-team --team example
has "the difference from the pack is reported" "its team.md or templates/ differ from the team pack's (edited in place, or an older pack)"
has "and so is the way to keep it" "To keep them, run with --team $S"
check "SKILL.md does not hold the edit yet" 0 "$(grep -c 'demo2' "$S/SKILL.md")"
run --with-team --team "$S" --yes
check "an in-place upgrade keeps the edited template" "command: echo my-model" "$(grep '^command:' "$S/templates/example-run.md")"
check "and assembles the edited team.md into SKILL.md" 1 "$(grep -c 'demo2' "$S/SKILL.md")"
printf '仓别名：demo3→/nowhere/demo3\n' >> "$S/team.md"
run --with-team --team example --yes
has "overwriting from the pack is announced" "--yes overwrites them"
check "and the edit is gone" 0 "$(grep -c 'demo3' "$S/team.md")"

echo "13. the remaining rows of the three decision tables"
new_home; all_agent_homes; hc_home
S=$(skill_dir herdr-example)
HC="$H/.config/herdr-core/templates"
REL="../../../.agents/skills/herdr-example"
printf 'elsewhere\n' > "$H/other.md"
# hc: a dangling link, a link that points elsewhere, a directory.
ln -s "$H/gone.md" "$HC/example-arch.md"
ln -s "$H/other.md" "$HC/example-dev.md"
mkdir "$HC/example-test.md"
# agents: a link that points elsewhere, a real directory with a file in it, a regular file.
mkdir -p "$H/.claude/skills"
ln -s "$H" "$H/.claude/skills/herdr-example"
mkdir -p "$H/.codex/skills/herdr-example"
printf 'mine\n' > "$H/.codex/skills/herdr-example/notes.txt"
mkdir -p "$H/.gemini/skills"
printf 'mine too\n' > "$H/.gemini/skills/herdr-example"
run --with-team --team example
check "exit status" 0 "$RC"
check "a dangling hc link is rebuilt" "$REL/templates/example-arch.md" "$(readlink "$HC/example-arch.md")"
has "an hc link pointing elsewhere is kept and reported" "example-dev.md: kept (link points elsewhere; --yes replaces it)"
check "and left as it was" "$H/other.md" "$(readlink "$HC/example-dev.md")"
has "a directory in the hc templates is kept and reported" "example-test.md: kept (not a symlink; --yes never replaces it)"
check "and is still a directory" "directory" "$(isdir "$HC/example-test.md")"
has "an agent link pointing elsewhere is kept and reported" "claude: kept (link points elsewhere; --yes replaces it)"
check "and is left as it was" "$H" "$(readlink "$H/.claude/skills/herdr-example")"
has "a real directory at an agent link position is kept and reported" "codex: kept (a real directory; --yes deletes it and links in its place)"
check "and its file is still there" "mine" "$(cat "$H/.codex/skills/herdr-example/notes.txt")"
has "a regular file at an agent link position is kept and reported" "gemini: kept (a regular file; --yes deletes it and links in its place)"
check "and its content is still there" "mine too" "$(cat "$H/.gemini/skills/herdr-example")"
run --with-team --team example --yes
has "the directory --yes deletes is named" "codex: deletes your directory $H/.codex/skills/herdr-example and links in its place"
has "the file --yes deletes is named" "gemini: deletes your file $H/.gemini/skills/herdr-example and links in its place"
has "the hc link --yes replaces is named" "example-dev.md: replaces the link that points elsewhere"
link_ok "with --yes an agent link pointing elsewhere is rebuilt" "$H/.claude/skills/herdr-example" "$S"
link_ok "with --yes a real directory at an agent link position is replaced" "$H/.codex/skills/herdr-example" "$S"
link_ok "with --yes a regular file at an agent link position is replaced" "$H/.gemini/skills/herdr-example" "$S"
check "with --yes an hc link pointing elsewhere is rebuilt" "$REL/templates/example-dev.md" "$(readlink "$HC/example-dev.md")"
check "a directory in the hc templates survives --yes" "directory" "$(isdir "$HC/example-test.md")"

echo "14. regular files already in hc's directory"
new_home; all_agent_homes; hc_home
cp "$EXAMPLE/templates/example-arch.md" "$(hc_link example-arch.md)"
printf 'mine\n' > "$(hc_link example-dev.md)"
run --with-team --team example
has "an identical file is reported as swapped" "example-arch.md: a regular file identical"
has "a different file is reported as kept" "example-dev.md: kept (a regular file that differs"
if [ -L "$(hc_link example-arch.md)" ]; then ok "an identical file became a link"
else bad "an identical file became a link" "it is not a symlink"; fi
run --with-team --team example --yes
if [ -f "$(hc_link example-dev.md)" ] && [ ! -L "$(hc_link example-dev.md)" ] && [ "$(cat "$(hc_link example-dev.md)")" = mine ]; then
  ok "a different file survives --yes"
else
  bad "a different file survives --yes" "it was replaced or changed"
fi

echo "15. a kept skill directory: an hc file counts as identical only to the installed template"
new_home; all_agent_homes; hc_home
S=$(skill_dir herdr-example)
run --with-team --team example
sed 's/^command: .*$/command: echo my-model/' "$S/templates/example-run.md" > "$S/run.new"
mv "$S/run.new" "$S/templates/example-run.md"
# Two regular files where hc looks for templates: one equal to the pack's template, one
# equal to the installed (edited) template.
rm "$(hc_link example-run.md)"
cp "$EXAMPLE/templates/example-run.md" "$(hc_link example-run.md)"
rm "$(hc_link example-test.md)"
cp "$S/templates/example-test.md" "$(hc_link example-test.md)"
run --with-team --team example
has "the directory is kept" "team herdr-example: $S kept (differs; rerun with --yes to overwrite)"
if [ ! -L "$(hc_link example-run.md)" ] && cmp -s "$EXAMPLE/templates/example-run.md" "$(hc_link example-run.md)"; then
  ok "a file equal to the pack's template, not to the installed one, is kept as it is"
else
  bad "a file equal to the pack's template, not to the installed one, is kept as it is" "it was swapped"
fi
has "and that is reported" "example-run.md: kept (a regular file that differs"
check "a file equal to the installed template is swapped" "../../../.agents/skills/herdr-example/templates/example-test.md" "$(readlink "$(hc_link example-test.md)")"

echo "16. hc is not installed"
new_home; all_agent_homes
run --with-team --team example
check "exit status" 0 "$RC"
has "the hc links are skipped and reported" "hc templates skipped"
has "and the remedy is given" "create it and rerun"
if [ -e "$H/.config/herdr-core" ]; then bad "no hc directory is created" "$H/.config/herdr-core exists"
else ok "no hc directory is created"; fi
link_ok "the skill is still installed and linked" "$H/.claude/skills/herdr-example" "$(skill_dir herdr-example)"

echo "17. one agent is not installed"
new_home; hc_home
mkdir -p "$H/.claude" "$H/.codex" "$H/.gemini" "$H/.config/opencode"
run --with-team --team example
has "that agent is reported as skipped" "pi: skipped ($H/.pi/agent not installed)"
if [ -e "$H/.pi" ]; then bad "the missing agent is not created" "$H/.pi exists"
else ok "the missing agent is not created"; fi
link_ok "claude is linked" "$H/.claude/skills/herdr-example" "$(skill_dir herdr-example)"

echo "18. the skill directory is a symlink"
new_home; all_agent_homes; hc_home
mkdir -p "$H/.agents/skills" "$H/elsewhere"
ln -s "$H/elsewhere" "$(skill_dir herdr-example)"
run --with-team --team example
check "exit status" 0 "$RC"
has "kept without --yes" "kept (is a symlink; never touched, even with --yes)"
has "and the reason no links are made" "links skipped (the skill dir is a symlink to a place without a SKILL.md; fix or remove it yourself; --yes never touches it)"
lacks "no advice to use --yes" "rerun with --yes"
run --with-team --team example --yes
check "exit status with --yes" 0 "$RC"
has "kept with --yes" "kept (is a symlink; never touched, even with --yes)"
if [ -L "$(skill_dir herdr-example)" ] && [ ! -e "$H/elsewhere/SKILL.md" ]; then
  ok "the symlink and its target are untouched"
else
  bad "the symlink and its target are untouched" "something was written"
fi

echo "18b. the place of the skill directory is taken by a regular file"
new_home; all_agent_homes; hc_home
S=$(skill_dir herdr-example)
mkdir -p "$H/.agents/skills"
printf 'mine\n' > "$S"
run --with-team --team example
check "exit status" 0 "$RC"
has "kept without --yes" "team herdr-example: $S kept (is not a directory; never touched, even with --yes)"
has "and no link is made to it" "links skipped ($S is not a directory; move it away yourself)"
lacks "no advice to use --yes" "rerun with --yes to replace it"
if [ -L "$H/.claude/skills/herdr-example" ] || [ -e "$H/.claude/skills/herdr-example" ]; then
  bad "no agent link is made" "$H/.claude/skills/herdr-example exists"
else
  ok "no agent link is made"
fi
run --with-team --team example --yes
check "exit status with --yes" 0 "$RC"
has "kept with --yes" "kept (is not a directory; never touched, even with --yes)"
check "the file is untouched" "mine" "$(cat "$S")"

echo "19. a team skill directory that holds no SKILL.md gets no links"
new_home; all_agent_homes; hc_home
S=$(skill_dir herdr-example)
mkdir -p "$S"
cp "$EXAMPLE/team.md" "$S/team.md"
printf 'not a skill yet\n' > "$S/notes.txt"
run --with-team --team example
check "exit status" 0 "$RC"
has "kept without --yes" "team herdr-example: $S kept (differs; rerun with --yes to overwrite)"
has "the reason is reported" "links skipped (the kept copy in $S has no readable SKILL.md; rerun with --yes to replace it)"
lacks "no agent link is planned" "skill links to create"
lacks "no hc link is planned" "hc template links to create"
if [ -e "$H/.claude/skills/herdr-example" ] || [ -L "$H/.claude/skills/herdr-example" ]; then
  bad "no agent link is made" "$H/.claude/skills/herdr-example exists"
else
  ok "no agent link is made"
fi
if [ -e "$(hc_link example-arch.md)" ] || [ -L "$(hc_link example-arch.md)" ]; then
  bad "no hc link is made" "$(hc_link example-arch.md) exists"
else
  ok "no hc link is made"
fi
check "the file is untouched" "not a skill yet" "$(cat "$S/notes.txt")"
run --with-team --team example --yes
has "replaced with --yes" "team herdr-example: $S replace"
link_ok "then the agent link is made" "$H/.claude/skills/herdr-example" "$S"
check "and the file the installer does not manage is still there" "not a skill yet" "$(cat "$S/notes.txt")"

echo "19b. the place of the skill directory is taken by a directory that is not a team skill"
new_home; all_agent_homes; hc_home
S=$(skill_dir herdr-example)
mkdir -p "$S"
printf 'mine\n' > "$S/SKILL.md"
before=$(entries)
run --with-team --team example
check "exit status" 1 "$RC"
has "refused, and it says why" "$S already exists and is not a team skill (no team.md in it); give this team another name in team.md"
check "zero writes" "$before" "$(entries)"
run --with-team --team example --yes
check "refused with --yes too" 1 "$RC"
check "zero writes" "$before" "$(entries)"
run --with-team --team example --dry-run
check "and reported by a dry run" 1 "$RC"
check "the file is untouched" "mine" "$(cat "$S/SKILL.md")"
run --with-skills --with-team --team example --yes
check "with --with-skills in the same run it is still refused" 1 "$RC"
if [ -e "$H/.agents/skills/herdr-cowork" ]; then bad "nothing at all is written, the vendored skill included" "it was installed"
else ok "nothing at all is written, the vendored skill included"; fi

echo "20. --team given as a directory"
new_home; all_agent_homes; hc_home
run --with-team --team "$EXAMPLE"
check "exit status" 0 "$RC"
has "names that directory as the pack" "team herdr-example: team pack $EXAMPLE"
if [ -f "$(skill_dir herdr-example)/SKILL.md" ]; then ok "installed from it"
else bad "installed from it" "no SKILL.md"; fi

echo "21. a team pack of one's own, found by name"
new_home; all_agent_homes; hc_home
make_pack "$H/.config/herdr-teams/t1" t1 t1
run --with-team --team t1
check "exit status" 0 "$RC"
has "found under the local directory" "team t1: team pack $H/.config/herdr-teams/t1"
check "assembled under that name" 1 "$(grep -c '^name: t1$' "$(skill_dir t1)/SKILL.md")"
if [ -L "$(hc_link t1-run.md)" ]; then ok "its templates are linked for hc"
else bad "its templates are linked for hc" "t1-run.md is missing"; fi

echo "21b. the skill is named by the pack, not by the pack's directory"
new_home; all_agent_homes; hc_home
make_pack "$H/.config/herdr-teams/backend" herdr-backend be
run --with-team --team backend
check "exit status" 0 "$RC"
check "installed under the name the pack gives" 1 "$(grep -c '^name: herdr-backend$' "$(skill_dir herdr-backend)/SKILL.md")"
check "the fixed sentence carries that name" 1 "$(grep -c '不加载调度类的 skill（herdr-cowork、herdr-backend）' "$(skill_dir herdr-backend)/SKILL.md")"
link_ok "the agent link carries that name" "$H/.claude/skills/herdr-backend" "$(skill_dir herdr-backend)"
check "the hc link points into that directory" "../../../.agents/skills/herdr-backend/templates/be-run.md" "$(readlink "$(hc_link be-run.md)")"
if [ -e "$(skill_dir backend)" ]; then bad "not under the directory's name" "$(skill_dir backend) exists"
else ok "not under the directory's name"; fi

echo "21c. two teams with different prefixes live side by side"
new_home; all_agent_homes; hc_home
make_pack "$H/.config/herdr-teams/backend" herdr-backend be
run --with-team --team example
run --with-team --team backend
check "exit status" 0 "$RC"
for pair in "herdr-example:example-run.md" "herdr-backend:be-run.md"; do
  link_ok "agent link ${pair%%:*}" "$H/.claude/skills/${pair%%:*}" "$(skill_dir "${pair%%:*}")"
  check "hc link of ${pair%%:*}" "../../../.agents/skills/${pair%%:*}/templates/${pair#*:}" "$(readlink "$(hc_link "${pair#*:}")")"
done
run --with-team --team example
has "the first team is still up to date" "team herdr-example: $(skill_dir herdr-example) up to date"

echo "22. a pack that exists locally and in the repo: the local one wins"
new_home; all_agent_homes; hc_home
make_pack "$H/.config/herdr-teams/example" herdr-example example
run --with-team --team example
check "exit status" 0 "$RC"
has "the local pack is the one used" "team herdr-example: team pack $H/.config/herdr-teams/example"
lacks "and not the repo's copy" "team herdr-example: team pack $EXAMPLE"

echo "23. a pack named like a directory of the repo"
new_home; all_agent_homes; hc_home
make_pack "$H/.config/herdr-teams/mods" mods mods
# Started from the repo's root, where a directory called mods exists.
OUT=$(cd "$REPO" && HOME="$H" HERDR_APP_HOME="$H/.config/herdr-app" PATH="$H/bin:$TOOLS:/usr/bin:/bin" LC_ALL=C /bin/sh "$INSTALL" --with-team --team mods 2>&1)
RC=$?
check "exit status" 0 "$RC"
has "found by name, not taken for the repo's mods/" "team mods: team pack $H/.config/herdr-teams/mods"
if [ -f "$(skill_dir mods)/SKILL.md" ]; then ok "installed"; else bad "installed" "no SKILL.md"; fi

echo "24. --team given as a relative path"
new_home; all_agent_homes; hc_home
make_pack "$H/packs/rel" rel rel
# The installer changes into the repo's directory itself; a relative path is the caller's.
OUT=$(cd "$H" && HOME="$H" HERDR_APP_HOME="$H/.config/herdr-app" PATH="$H/bin:$TOOLS:/usr/bin:/bin" LC_ALL=C /bin/sh "$INSTALL" --with-team --team packs/rel 2>&1)
RC=$?
check "exit status" 0 "$RC"
has "resolved against the caller's directory" "team rel: team pack $H/packs/rel"
if [ -f "$(skill_dir rel)/SKILL.md" ]; then ok "installed"; else bad "installed" "no SKILL.md"; fi

echo "25. two teams must not share a prefix"
new_home; all_agent_homes; hc_home
run --with-team --team example
make_pack "$H/.config/herdr-teams/other" other example
before=$(entries)
run --with-team --team other
check "exit status" 1 "$RC"
has "the skill that owns the prefix is named" "prefix 'example' is already used by the team skill 'herdr-example'"
check "zero writes" "$before" "$(entries)"
check "the first team's hc link is untouched" "../../../.agents/skills/herdr-example/templates/example-arch.md" "$(readlink "$(hc_link example-arch.md)")"
if [ -e "$(skill_dir other)" ]; then bad "the second team is not installed" "$(skill_dir other) exists"
else ok "the second team is not installed"; fi
run --with-team --team other --yes
check "also refused with --yes" 1 "$RC"
check "zero writes" "$before" "$(entries)"
run --with-team --team other --dry-run
check "and reported by a dry run" 1 "$RC"
has "with the same message" "prefix 'example' is already used by the team skill 'herdr-example'"

echo "26. invalid team packs"
rejects_pack "no name" "'name' must be lowercase letters and digits separated by single hyphens" drop_name
rejects_pack "no prefix" "'prefix' must be set" drop_prefix
rejects_pack "a required section is missing" "required section '### 工作区' missing" drop_section
rejects_pack "a template is missing" "templates/bad-run.md missing from the team pack" drop_template
rejects_pack "a template's name does not match its file" "frontmatter 'name' must be bad-run" wrong_name

echo "26b. a skill name and a prefix that break the rules"
new_home; all_agent_homes; hc_home
make_pack "$H/.config/herdr-teams/Bad Name" "Bad Name" t9
before=$(entries)
run --with-team --team "$H/.config/herdr-teams/Bad Name"
check "a skill name with other characters: exit status" 1 "$RC"
has "and the message names the field" "team.md: 'name' must be lowercase letters and digits separated by single hyphens (got 'Bad Name')"
check "zero writes" "$before" "$(entries)"
make_pack "$H/.config/herdr-teams/t11" herdr-cowork t11
before=$(entries)
run --with-team --team t11 --yes
check "the vendored skill's name is refused, with --yes too" 1 "$RC"
has "and it says why" "team.md: 'name' must not be herdr-cowork: that is the name of the skill installed by --with-skills"
check "zero writes" "$before" "$(entries)"
# The limit for a skill name is 64 characters. The samples are 26 + 26 + 13 and
# 26 + 26 + 12 letters, and their length is checked here rather than trusted.
name65="abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklm"
name64="abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijkl"
check "the long sample has 65 characters" 65 "${#name65}"
check "the other sample has 64 characters" 64 "${#name64}"
make_pack "$H/.config/herdr-teams/t12" "$name65" t12
before=$(entries)
run --with-team --team t12
check "a skill name of 65 characters: exit status" 1 "$RC"
has "and the message gives the limit" "team.md: 'name' is longer than 64 characters, which is the limit for a skill name"
check "zero writes" "$before" "$(entries)"
make_pack "$H/.config/herdr-teams/t14" "$name64" t14
run --with-team --team t14
check "a skill name of 64 characters is accepted" 0 "$RC"
make_pack "$H/.config/herdr-teams/t10" t10 abcdefghijklmnopqrstuvwxyz0123456
before=$(entries)
run --with-team --team t10
check "a prefix too long for an hc template name: exit status" 1 "$RC"
has "and the message says why" "'prefix' is longer than 25 characters, hc limits template names to 32"
check "zero writes" "$before" "$(entries)"

echo "26c. the frontmatter of team.md, and templates beyond the five"
rejects_pack "the frontmatter is not closed" "frontmatter is not closed by a --- line" no_close
rejects_pack "team.md uses Windows line endings" "uses Windows line endings (CRLF)" crlf
rejects_pack "an extra template's name does not match its file" "frontmatter 'name' must be bad-extra" extra_wrong_name
rejects_pack "an extra template's name is too long for hc" "must be at most 32 characters and hold no whitespace" extra_long_name
rejects_pack "an extra template's name holds a space" "must be at most 32 characters and hold no whitespace" extra_space_name

echo "27. a template dropped from the pack"
new_home; all_agent_homes; hc_home
P="$H/.config/herdr-teams/t2"
make_pack "$P" t2 t2
sed 's/^name: example-arch$/name: t2-extra/' "$EXAMPLE/templates/example-arch.md" > "$P/templates/t2-extra.md"
run --with-team --team t2
S=$(skill_dir t2)
if [ -L "$(hc_link t2-extra.md)" ]; then ok "the extra template is linked at first"
else bad "the extra template is linked at first" "t2-extra.md is not linked"; fi
rm "$P/templates/t2-extra.md"
before=$(entries)
run --with-team --team t2 --yes --dry-run
has "a dry run lists the stale template" "templates to remove from the installed dir: t2-extra.md"
has "and the hc link that would dangle" "hc links to remove, they would dangle: t2-extra.md"
check "and writes nothing" "$before" "$(entries)"
run --with-team --team t2 --yes
if [ ! -e "$S/templates/t2-extra.md" ]; then ok "the stale template is removed"
else bad "the stale template is removed" "it is still there"; fi
if [ ! -e "$(hc_link t2-extra.md)" ] && [ ! -L "$(hc_link t2-extra.md)" ]; then ok "its dangling hc link is removed"
else bad "its dangling hc link is removed" "it is still there"; fi
has "the removal is reported" "removed dangling hc link"

echo "28. upgrading with --team pointing at the installed directory"
sed 's/^command: .*$/command: echo my-model/' "$S/templates/t2-arch.md" > "$S/arch.new"
mv "$S/arch.new" "$S/templates/t2-arch.md"
printf '# a local edit\n' >> "$S/SKILL.md"
printf '# an older README\n' > "$S/README.md"
run --with-team --team "$S" --yes
check "exit status" 0 "$RC"
check "a locally changed command survives" "command: echo my-model" "$(grep '^command:' "$S/templates/t2-arch.md")"
if cmp -s "$REPO/skills/herdr-backend/README.md" "$S/README.md"; then ok "README.md, which is the repo's, is brought up to date"
else bad "README.md, which is the repo's, is brought up to date" "it still differs"; fi
expected_skill "$S" t2 > "$WORK/expected-t2.md"
if cmp -s "$WORK/expected-t2.md" "$S/SKILL.md"; then ok "SKILL.md is reassembled"
else bad "SKILL.md is reassembled" "it differs"; fi
run --with-team --team "$S"
has "and the directory is up to date afterwards" "team t2: $S up to date"

echo "28b. an in-place upgrade removes the hc link of an extra template that is gone"
new_home; all_agent_homes; hc_home
P="$H/.config/herdr-teams/t3"
make_pack "$P" t3 t3
sed 's/^name: example-arch$/name: t3-extra/' "$EXAMPLE/templates/example-arch.md" > "$P/templates/t3-extra.md"
run --with-team --team t3
S=$(skill_dir t3)
if [ -L "$(hc_link t3-extra.md)" ]; then ok "the extra template is linked at first"
else bad "the extra template is linked at first" "t3-extra.md is not linked"; fi
rm "$S/templates/t3-extra.md"
printf '# a local edit\n' >> "$S/SKILL.md"
run --with-team --team "$S" --yes --dry-run
has "a dry run lists the link that would be removed" "hc links to remove, they would dangle: t3-extra.md"
run --with-team --team "$S" --yes
check "exit status" 0 "$RC"
if [ ! -L "$(hc_link t3-extra.md)" ] && [ ! -e "$(hc_link t3-extra.md)" ]; then ok "the hc link of the template that is gone is removed"
else bad "the hc link of the template that is gone is removed" "it is still there"; fi

echo
echo "passed $pass, failed $fail"
[ "$fail" = 0 ]
