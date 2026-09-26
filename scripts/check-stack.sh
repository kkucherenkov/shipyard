#!/usr/bin/env sh
# Validate the stack plugin under <root>/stacks/.
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
stack_root="$root/stacks"
[ -d "$stack_root" ] || { echo 'no stacks/ to check'; exit 0; }

fail() {
  printf 'FAIL %s: %s\n' "$1" "$2" >&2
  failures=$((failures + 1))
}

files=$(find "$stack_root" -type f \( -name '*.md' -o -name '*.json' \
  -o -name '*.yml' -o -name '*.yaml' \) | sort)
[ -n "$files" ] || { echo 'stack ok'; exit 0; }

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
  if grep -qiE 'course.?shelf|@app/|@todoer/|\btodoer\b|dockge|\bnas\b|\bE[0-9]{2}-F[0-9]{2}\b' "$f"; then
    fail "$f" 'carries an identity noun (source project or first consumer)'
  fi

  # R2. A version in an install specifier. Three shapes, and only three: a
  # package specifier, a container image tag, and a quoted range in a manifest
  # block. A floor written "24.15+" matches none of them, and neither does a
  # version quoted inside a trap as evidence ("dash rejected it until 0.5.12"),
  # which is a fact about history rather than an instruction.
  #
  # A plugin's own .claude-plugin/*.json is exempt from THIS rule only: D13
  # requires plugin.json to carry "version", and a manifest's own version is
  # not an install specifier — nothing installs a plugin.json the way it
  # installs a dependency. R1 does NOT get this exemption: the manifest's
  # description/keywords fields are the marketplace's user-facing copy, the
  # first thing a stranger reads, and layer 1 already shipped an identity
  # noun (packages/ui) through a noun rule that skipped the file the noun
  # actually appeared in. Do not widen this skip to cover R1 too.
  case $f in
    */.claude-plugin/*.json) ;;
    *)
      if grep -qE '[A-Za-z0-9._/-]@[0-9]+\.[0-9]+|image: *[A-Za-z0-9./_-]+:[0-9]+\.[0-9]+|"[~^]?[0-9]+\.[0-9]+\.[0-9]+"' "$f"; then
        fail "$f" 'pins a version in an install specifier (D12: a floor, or nothing)'
      fi
      ;;
  esac

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

if [ "$failures" -gt 0 ]; then
  printf '%s problem(s)\n' "$failures" >&2
  exit 1
fi
echo 'stack ok'
