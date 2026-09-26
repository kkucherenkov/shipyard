#!/usr/bin/env sh
# Validate every skill under <root>/skills/.
#
# Five rules, each of which encodes a way a skill can be syntactically perfect
# and still useless. The expensive one is the first: a skill is selected by its
# description alone, so a description that summarises the contents instead of
# naming a task is never read at the moment it would have helped.
set -u

root=${1:-.}
failures=0

fail() {
  printf 'FAIL %s: %s\n' "$1" "$2" >&2
  failures=$((failures + 1))
}

for skill in "$root"/skills/*/SKILL.md; do
  [ -e "$skill" ] || continue
  dir=$(dirname "$skill")

  desc=$(sed -n 's/^description: *//p' "$skill" | head -1)

  # 1. The description must name a task, not the contents.
  if ! printf '%s' "$desc" | grep -qiE 'use (when|before|after|while)'; then
    fail "$skill" 'description does not name a triggering task (needs "use when/before/after")'
  fi

  # 2. No nouns from the repository these procedures were extracted from.
  if grep -rqniE 'course.?shelf|@app/|apps/(backend|web|mobile)|packages/specs|centrifugo|prisma|nestjs|nuxt|dockge' "$dir"; then
    fail "$skill" 'carries a noun from the source project'
  fi

  # 3. Every trap keeps its evidence. A paragraph under ## Traps shorter than
  #    200 characters is an instruction without the observation that earned it,
  #    and an instruction without evidence is ignored.
  #    Captured into a variable (not piped into `while`) so `fail` runs in this
  #    shell and `failures` survives the loop.
  short_traps=$(awk '
    /^## Traps/ { inside = 1; next }
    /^## / { inside = 0 }
    inside && /^\*\*/ {
      para = $0
      while ((getline line) > 0 && line != "") para = para " " line
      if (length(para) < 200) print para
    }
  ' "$skill")
  if [ -n "$short_traps" ]; then
    oldifs=$IFS
    IFS='
'
    for short in $short_traps; do
      [ -n "$short" ] && fail "$skill" "trap without evidence: $(printf '%s' "$short" | cut -c1-60)..."
    done
    IFS=$oldifs
  fi

  # 4. Every relative link resolves. A skill that names a file it does not have
  #    costs the whole session that trusts it. Same variable-capture fix as
  #    rule 3, for the same reason.
  links=$(grep -o '](\([^)#][^)]*\))' "$skill" | sed 's/^](//; s/)$//')
  if [ -n "$links" ]; then
    oldifs=$IFS
    IFS='
'
    for link in $links; do
      case $link in
        http*|mailto:*) continue ;;
      esac
      target=$(printf '%s' "$link" | sed 's/#.*//')
      [ -z "$target" ] && continue
      [ -e "$dir/$target" ] || [ -e "$root/$target" ] || fail "$skill" "dangling link: $target"
    done
    IFS=$oldifs
  fi
done

# 5. No two skills may claim the same trigger, or the choice between them is
#    arbitrary and half of what they carry becomes unreachable. The message
#    names every skill that collided, not just the trigger text — a message
#    naming only one skill leaves the reader guessing which pair it is.
trigger_hits=$(
  for f in "$root"/skills/*/SKILL.md; do
    [ -e "$f" ] || continue
    trig=$(sed -n 's/^description: *//p' "$f" | head -1 | tr 'A-Z' 'a-z' \
      | grep -oE 'use (when|before|after|while)[^.,;]*' | head -1)
    [ -n "$trig" ] && printf '%s\t%s\n' "$trig" "$f"
  done
)
if [ -n "$trigger_hits" ]; then
  dup_triggers=$(printf '%s\n' "$trigger_hits" | cut -f1 | sort | uniq -d)
  if [ -n "$dup_triggers" ]; then
    oldifs=$IFS
    IFS='
'
    for trig in $dup_triggers; do
      colliding=$(printf '%s\n' "$trigger_hits" \
        | awk -F '\t' -v t="$trig" '$1 == t { print $2 }' \
        | tr '\n' ',' | sed 's/,$//; s/,/, /g')
      fail 'skills/' "two skills claim the same trigger ($trig): $colliding"
    done
    IFS=$oldifs
  fi
fi

if [ "$failures" -gt 0 ]; then
  printf '%s problem(s)\n' "$failures" >&2
  exit 1
fi
echo 'skills ok'
