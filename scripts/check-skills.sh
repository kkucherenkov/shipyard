#!/usr/bin/env sh
# Validate every skill under <root>/skills/.
#
# Six rules, each of which encodes a way a skill can be syntactically perfect
# and still useless. The expensive one is rule 2: a skill is selected by its
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

  # 1. Frontmatter must carry a non-empty name.
  name_val=$(sed -n 's/^name: *//p' "$skill" | head -1)
  if [ -z "$name_val" ]; then
    fail "$skill" 'frontmatter is missing a non-empty name:'
  fi

  desc=$(sed -n 's/^description: *//p' "$skill" | head -1)

  # 2. The description must name a task, not the contents.
  if ! printf '%s' "$desc" | grep -qiE 'use (when|before|after|while)'; then
    fail "$skill" 'description does not name a triggering task (needs "use when/before/after")'
  fi

  # 3. No nouns from the repository these procedures were extracted from.
  if grep -rqiE 'course.?shelf|@app/|apps/(backend|web|mobile)|packages/(specs|ui)|centrifugo|prisma|nestjs|nuxt|dockge|\bnas\b|\bE[0-9]{2}-F[0-9]{2}\b' "$dir"; then
    fail "$skill" 'carries a noun from the source project'
  fi

  # 4. Every trap keeps its evidence. A paragraph under ## Traps shorter than
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
    set -f
    for short in $short_traps; do
      [ -n "$short" ] && fail "$skill" "trap without evidence: $(printf '%s' "$short" | cut -c1-60)..."
    done
    set +f
    IFS=$oldifs
  fi

  # 5. Every relative link resolves. A skill that names a file it does not have
  #    costs the whole session that trusts it. Same variable-capture fix as
  #    rule 4, for the same reason.
  links=$(grep -o '](\([^)#][^)]*\))' "$skill" | sed 's/^](//; s/)$//')
  if [ -n "$links" ]; then
    oldifs=$IFS
    IFS='
'
    set -f
    for link in $links; do
      case $link in
        http*|mailto:*) continue ;;
      esac
      target=$(printf '%s' "$link" | sed 's/#.*//')
      [ -z "$target" ] && continue
      [ -e "$dir/$target" ] || [ -e "$root/$target" ] || fail "$skill" "dangling link: $target"
    done
    set +f
    IFS=$oldifs
  fi
done

# 6. No two skills may claim the same trigger, or the choice between them is
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
    set -f
    for trig in $dup_triggers; do
      # Passed to awk through the environment, not -v: -v runs escape-sequence
      # processing on its value, so a trigger containing a backslash would
      # never match the literal $1 == t comparison.
      colliding=$(printf '%s\n' "$trigger_hits" \
        | TRIG="$trig" awk -F '\t' '$1 == ENVIRON["TRIG"] { print $2 }' \
        | tr '\n' ',' | sed 's/,$//; s/,/, /g')
      fail 'skills/' "two skills claim the same trigger ($trig): $colliding"
    done
    set +f
    IFS=$oldifs
  fi
fi

if [ "$failures" -gt 0 ]; then
  printf '%s problem(s)\n' "$failures" >&2
  exit 1
fi
echo 'skills ok'
