#!/usr/bin/env sh
# Table test for check-skills.sh, driven by fixture skill trees.
set -u

here=$(dirname "$0")
subject="$here/check-skills.sh"
failures=0

# Build a one-skill tree in $1 with frontmatter $2 and body $3.
make_skill() {
  root=$1
  desc=$2
  body=$3
  mkdir -p "$root/skills/sample"
  {
    printf -- '---\n'
    printf 'name: sample\n'
    printf 'description: %s\n' "$desc"
    printf -- '---\n\n'
    printf '# Sample\n\n%s\n' "$body"
  } > "$root/skills/sample/SKILL.md"
}

# Add a named skill to an existing tree in $1 (skill name $2, frontmatter $3,
# body $4). Lets a case put more than one skill under the same skills/ root —
# make_skill above stays single-skill and untouched for every case that only
# needs one.
add_skill() {
  root=$1
  name=$2
  desc=$3
  body=$4
  mkdir -p "$root/skills/$name"
  {
    printf -- '---\n'
    printf 'name: %s\n' "$name"
    printf 'description: %s\n' "$desc"
    printf -- '---\n\n'
    printf '# %s\n\n%s\n' "$name" "$body"
  } > "$root/skills/$name/SKILL.md"
}

expect() {
  want=$1
  desc=$2
  root=$(mktemp -d)
  make_skill "$root" "$3" "$4"
  sh "$subject" "$root" >/dev/null 2>&1
  got=$?
  rm -rf "$root"
  if [ "$got" -ne "$want" ]; then
    printf 'FAIL want=%s got=%s %s\n' "$want" "$got" "$desc" >&2
    failures=$((failures + 1))
  fi
}

good_trap='## Traps

**A pending check reports `conclusion: ""`, not `null`.** jq substitutes only
on false and null, so `.conclusion // "PENDING"` returns the empty string and
every "is it still running" test passes. Gate on `.status != "COMPLETED"`.'

expect 0 'a task-shaped description passes' \
  'Use when a pull request looks green but will not merge.' "$good_trap"

expect 1 'a contents-shaped description fails' \
  'Notes and tips about continuous integration.' "$good_trap"

expect 1 'a trap paragraph with no evidence fails' \
  'Use when a pull request looks green but will not merge.' \
  '## Traps

**Gate on `.status`.** Otherwise it breaks.'

expect 1 'a source-project noun fails' \
  'Use when deploying course_shelf to the NAS.' "$good_trap"

expect 1 'a dangling relative link fails' \
  'Use when a pull request looks green but will not merge.' \
  "$good_trap

See [the driver](driver.mjs)."

# Rule 5 needs two skills in one tree, which expect()/make_skill can't build,
# so these two cases drive check-skills.sh directly instead of through expect().

root=$(mktemp -d)
add_skill "$root" alpha 'Use when a pull request looks green but will not merge.' "$good_trap"
add_skill "$root" beta 'Use when a pull request looks green but will not merge.' "$good_trap"
out=$(sh "$subject" "$root" 2>&1 >/dev/null)
got=$?
rm -rf "$root"
if [ "$got" -ne 1 ]; then
  printf 'FAIL want=1 got=%s two skills sharing a trigger fails\n' "$got" >&2
  failures=$((failures + 1))
fi
case $out in
  *alpha*) has_alpha=1 ;;
  *) has_alpha=0 ;;
esac
case $out in
  *beta*) has_beta=1 ;;
  *) has_beta=0 ;;
esac
if [ "$has_alpha" -ne 1 ] || [ "$has_beta" -ne 1 ]; then
  printf 'FAIL two skills sharing a trigger: message does not name both skills: %s\n' "$out" >&2
  failures=$((failures + 1))
fi

root=$(mktemp -d)
add_skill "$root" alpha 'Use when a pull request looks green but will not merge.' "$good_trap"
add_skill "$root" beta 'Use before cutting a release to confirm nothing regressed.' "$good_trap"
sh "$subject" "$root" >/dev/null 2>&1
got=$?
rm -rf "$root"
if [ "$got" -ne 0 ]; then
  printf 'FAIL want=0 got=%s two skills with distinct triggers pass\n' "$got" >&2
  failures=$((failures + 1))
fi

if [ "$failures" -gt 0 ]; then
  printf '%s failing case(s)\n' "$failures" >&2
  exit 1
fi
echo 'all cases pass'
