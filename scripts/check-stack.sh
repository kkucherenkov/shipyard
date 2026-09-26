#!/usr/bin/env sh
# Validate the stack plugin under <root>/stacks/, and check the root
# .claude-plugin/marketplace.json for identity nouns (R1 only).
#
# A stack recipe is not a process skill and does not take check-skills.sh's
# rules. That script forbids naming a framework, which is the one thing a
# recipe must do. What a recipe must never carry is an IDENTITY noun — a name
# that means exactly one existing repository — or a version pinned into an
# install specifier, because a pin is a statement about the Tuesday it was
# written and the recipe outlives it.
set -u

root=${1:-.}
failures=0

fail() {
  printf 'FAIL %s: %s\n' "$1" "$2" >&2
  failures=$((failures + 1))
}

# Reports failures (if any) or the given all-clear message, then exits.
# Shared by every early-return point below so a failure recorded before one
# of them (the marketplace check, in particular) is never masked by an
# unrelated "ok" printed on the way out.
finish() {
  if [ "$failures" -gt 0 ]; then
    printf '%s problem(s)\n' "$failures" >&2
    exit 1
  fi
  echo "$1"
  exit 0
}

# R1's identity-noun pattern, shared between the per-file loop below and the
# root marketplace check so the two lists cannot drift apart. Centrifugo is
# on this list because the global constraints name it and
# scripts/check-skills.sh already bans it for layer 1 — layer 2 must not be
# the weaker gate on a noun both layers share. The card-id shape allows one
# or two digits per field: a card numbered E1-F3 is as much an identity noun
# as a padded E15-F03.
identity_nouns='course.?shelf|@app/|@todoer/|\btodoer\b|dockge|\bnas\b|\bE[0-9]{1,2}-F[0-9]{1,2}\b|centrifugo'

# R1 also covers the root .claude-plugin/marketplace.json. check-skills.sh
# scans only skills/*/SKILL.md and commands/*.md; the loop below scans only
# stacks/. Nothing was checking the one file a stranger reads before
# installing anything, and the marketplace description and keywords are the
# most visible place an identity noun could ship. R1 only: check-skills.sh's
# own noun list bans the technology nouns a stack plugin's marketplace entry
# may legitimately need to name, so this check does not move there.
marketplace_json="$root/.claude-plugin/marketplace.json"
if [ -f "$marketplace_json" ] && grep -qiE "$identity_nouns" "$marketplace_json"; then
  fail "$marketplace_json" 'carries an identity noun (source project or first consumer)'
fi

stack_root="$root/stacks"
[ -d "$stack_root" ] || finish 'no stacks/ to check'

files=$(find "$stack_root" -type f \( -name '*.md' -o -name '*.json' \
  -o -name '*.yml' -o -name '*.yaml' \) | sort)
[ -n "$files" ] || finish 'stack ok'

oldifs=$IFS
IFS='
'
set -f
for f in $files; do
  dir=$(dirname "$f")

  # R1. Identity nouns. Not technology nouns: a recipe that installs Nest has
  # to be able to say Nest. What it may never say is the name of the project
  # it was extracted from, or of the project it was first proved against — a
  # recipe that names its consumer is a fork of it.
  if grep -qiE "$identity_nouns" "$f"; then
    fail "$f" 'carries an identity noun (source project or first consumer)'
  fi

  # R2. A version in an install specifier. Three shapes, and only three: a
  # package specifier (pkg@1.2.3), a container image tag, major-only or
  # major.minor (postgres:18-alpine or postgres:18.1-alpine), and a
  # dependency's quoted range or pin inside a manifest block. A floor written
  # "24.15+" matches none of them. A version quoted inside a trap as evidence
  # ("we saw it on \"1.13.4\" before the bump") matches none of them either:
  # it is a bare quoted string in prose, never a "key": "value" pair. Nor
  # does a manifest's own "version" field ("version": "0.0.0" in a template
  # package.json snippet, or "version": "0.1.0" in this plugin's own
  # plugin.json) — the third shape excludes the literal key "version" by
  # name, because that key names the manifest's own identity, never a
  # dependency it depends on. This is a semantic distinction (the key name),
  # not a path-based one, so it needs no separate carve-out for
  # .claude-plugin/*.json and applies identically to a template package.json
  # snippet inside a module file.
  version_pin=0
  grep -qE '[A-Za-z0-9._/-]@[0-9]+\.[0-9]+' "$f" && version_pin=1
  grep -qE 'image: *[A-Za-z0-9./_-]+:[0-9]+(\.[0-9]+)?' "$f" && version_pin=1
  if grep -oE '"[A-Za-z0-9@/_.-]+" *: *"[~^]?[0-9]+\.[0-9]+\.[0-9]+"' "$f" \
       | grep -qvE '^"version" *:'; then
    version_pin=1
  fi
  if [ "$version_pin" -eq 1 ]; then
    fail "$f" 'pins a version in an install specifier (D12: a floor, or nothing)'
  fi

  case $f in *.md) ;; *) continue ;; esac

  # R5. Every trap keeps its evidence. Same 200-character floor check-skills.sh
  # applies to layer 1, and for the same reason: an instruction stripped of the
  # observation that earned it is an instruction the next reader overrides.
  short_traps=$(awk '
    /^## Traps/ { inside = 1; next }
    /^## / { inside = 0 }
    inside && /^\*\*/ {
      para = $0
      while ((getline line) > 0 && line != "") para = para " " line
      if (length(para) < 200) print para
    }
  ' "$f")
  if [ -n "$short_traps" ]; then
    inner_ifs=$IFS
    IFS='
'
    for short in $short_traps; do
      [ -n "$short" ] && fail "$f" "trap without evidence: $(printf '%s' "$short" | cut -c1-60)..."
    done
    IFS=$inner_ifs
  fi

  # R7. Every relative link resolves. A recipe that names a file it does not
  # have costs the whole session that trusts it.
  links=$(grep -o '](\([^)#][^)]*\))' "$f" | sed 's/^](//; s/)$//')
  if [ -n "$links" ]; then
    inner_ifs=$IFS
    IFS='
'
    for link in $links; do
      case $link in http*|mailto:*) continue ;; esac
      target=$(printf '%s' "$link" | sed 's/#.*//')
      [ -z "$target" ] && continue
      [ -e "$dir/$target" ] || [ -e "$root/$target" ] || fail "$f" "dangling link: $target"
    done
    IFS=$inner_ifs
  fi
done
set +f
IFS=$oldifs

# R6. No pnpm script the recipe never tells anyone to create. The failure this
# catches is documented rather than imagined: a consumer's own docs described a
# three-command pipeline of which one command had never existed in that
# repository, and the reader who ran the documented line got a missing-script
# error. Namespaced script names (word:word) are the shape this stack uses, and
# matching only those keeps the rule precise enough to have no exceptions.
used=$(grep -rhoE 'pnpm (run )?[a-z][a-z-]*:[a-z][a-z-]*' "$stack_root" \
  | sed 's/^pnpm \(run \)\?//' | sort -u)
declared=$(grep -rhoE '"[a-z][a-z-]*:[a-z][a-z-]*" *:' "$stack_root" \
  | sed 's/^"//; s/"[[:space:]]*:$//' | sort -u)
if [ -n "$used" ]; then
  inner_ifs=$IFS
  IFS='
'
  set -f
  for script in $used; do
    printf '%s\n' "$declared" | grep -qx "$script" \
      || fail "$stack_root" "recipe runs \`pnpm $script\` but never creates that script"
  done
  set +f
  IFS=$inner_ifs
fi

finish 'stack ok'
