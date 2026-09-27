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

# R3, R4 and R8 all belong to one stack's own skill directory, and walk every
# stack under stacks/ generically — the same way the find above collects
# $files across all of stacks/ rather than one hardcoded plugin — so a second
# stack directory cannot silently escape any of the three.
for skill_dir in "$stack_root"/*/skills/*/; do
  [ -d "$skill_dir" ] || continue
  skill_dir=${skill_dir%/}
  skill_file="$skill_dir/SKILL.md"

  # R8. The stack skill's own frontmatter is checked by nothing else:
  # check-skills.sh globs only <root>/skills/*/SKILL.md, which a nested
  # stacks/*/skills/*/SKILL.md never matches. Mirrors check-skills.sh's rules
  # 1 and 2 exactly — a non-empty name:, a description carrying a trigger
  # phrase — rather than widening that script's own glob, which would also
  # drag its forbidden-technology-noun rule onto a file whose entire job is
  # naming the technologies a recipe installs.
  #
  # Extracted from the frontmatter block only, the first line through the
  # next "---". This file's own examples are expected to contain a body line
  # reading "name: <module-name>" or "description: ...", so a skill with no
  # name: in its frontmatter at all must not pass because one of its examples
  # happens to start with the same word. check-skills.sh reads its keys the
  # same way, out of a shared frontmatter() helper; the two scripts stay
  # separate because their rule sets are disjoint by design, so the five
  # lines of awk are duplicated rather than sourced from a third file.
  if [ -f "$skill_file" ]; then
    frontmatter=$(awk '
      NR == 1 && /^---[[:space:]]*$/ { infm = 1; next }
      infm && /^---[[:space:]]*$/ { closed = 1; exit }
      infm { buf = buf $0 "\n" }
      END { if (closed) printf "%s", buf }
    ' "$skill_file")
    name_val=$(printf '%s\n' "$frontmatter" | sed -n 's/^name: *//p' | head -1)
    [ -n "$name_val" ] || fail "$skill_file" 'frontmatter is missing a non-empty name:'
    desc_val=$(printf '%s\n' "$frontmatter" | sed -n 's/^description: *//p' | head -1)
    printf '%s' "$desc_val" | grep -qiE 'use (when|before|after|while)' \
      || fail "$skill_file" 'description does not name a triggering task (needs "use when/before/after")'
  fi

  [ -d "$skill_dir/modules" ] || continue

  # R3. Every module file carries the same six headings, in this order,
  # spelled the same way, and "## Declining this module" says enough to be
  # useful rather than merely present. The heading this rule exists for is
  # "## Declining this module": a module whose files are reached by another
  # module's script cannot be omitted without editing that other module, and
  # the only way to find out is to make somebody write down what a decline
  # removes. A module file that never says, or says it in one line ("just
  # don't install it"), has a seam in it — so the same length floor R5
  # already puts under a Traps paragraph goes under this heading too.
  for m in "$skill_dir"/modules/*.md; do
    [ -e "$m" ] || continue
    for heading in '## Preconditions' '## Steps' '## What the consumer decides' \
      '## Traps' '## Declining this module' '## Verify'; do
      grep -qxF "$heading" "$m" || fail "$m" "missing required heading: $heading"
    done

    # The six headings must appear in that order. present_headings is the
    # canonical list filtered down to whichever of the six this file actually
    # has (order not yet meaningful); actual_order is what grep finds in file
    # order. If a required heading is entirely missing, both lists drop it
    # equally, so only a genuine reordering — not an absence already reported
    # above — trips this.
    canonical='## Preconditions
## Steps
## What the consumer decides
## Traps
## Declining this module
## Verify'
    present_headings=$(grep -xE '## (Preconditions|Steps|What the consumer decides|Traps|Declining this module|Verify)' "$m" | sort -u)
    ph=$(mktemp)
    printf '%s\n' "$present_headings" > "$ph"
    expected_order=$(printf '%s\n' "$canonical" | grep -Fxf "$ph")
    actual_order=$(grep -xE '## (Preconditions|Steps|What the consumer decides|Traps|Declining this module|Verify)' "$m")
    rm -f "$ph"
    if [ "$expected_order" != "$actual_order" ]; then
      fail "$m" 'required headings are out of order (want: Preconditions, Steps, What the consumer decides, Traps, Declining this module, Verify)'
    fi

    # "## Declining this module" must say enough to name what disappears, not
    # merely exist. Same technique and floor as R5's Traps check, applied to
    # the whole section instead of a bold-led paragraph, since a decline
    # section is not written as a trap.
    decline_len=$(awk '
      /^## Declining this module/ { inside = 1; next }
      /^## / { inside = 0 }
      inside { body = body $0 " " }
      END { print length(body) }
    ' "$m")
    if [ "$decline_len" -lt 200 ]; then
      fail "$m" '## Declining this module says too little to name what a decline removes'
    fi
  done

  # R4. The module table in SKILL.md and the files under modules/ are the same
  # set, over the alphabet a module name is allowed to use: lowercase letters,
  # digits, and hyphens (SKILL.md states this). A table row with no file sends
  # a reader to a page that does not exist; a file with no row is a module
  # nobody can find, which is the same as not having written it.
  tabled=$(grep -oE '\(modules/[a-z0-9-]+\.md\)' "$skill_file" 2>/dev/null \
    | sed 's|(modules/||; s|\.md)||' | sort -u)
  present=$(find "$skill_dir/modules" -name '*.md' -exec basename {} .md \; | sort -u)
  if [ "$tabled" != "$present" ]; then
    # Process substitution (<(...)) is not POSIX; the runner's /bin/sh is not
    # guaranteed to be bash, so the two sides go through temp files instead.
    # Only write a side that is actually non-empty: printf '%s\n' "" still
    # emits one blank line, which grep -vxF then reports as a spurious
    # "only" entry and defeats the ${var:-none} fallback below.
    t=$(mktemp); p=$(mktemp)
    [ -n "$tabled" ] && printf '%s\n' "$tabled" > "$t"
    [ -n "$present" ] && printf '%s\n' "$present" > "$p"
    only_tabled=$(grep -vxF -f "$p" "$t" | tr '\n' ' ')
    only_present=$(grep -vxF -f "$t" "$p" | tr '\n' ' ')
    rm -f "$t" "$p"
    fail "$skill_dir" "module table and modules/ disagree — tabled only: ${only_tabled:-none}; present only: ${only_present:-none}"
  fi

  # R9. The table's Requires column and the module's own declaration name the
  # same modules. Requires is the only machine-readable record of an
  # inter-module dependency in the whole recipe, and until this rule existed no
  # rule read it: R4 above extracts the (modules/<name>.md) link out of a row
  # and stops, so a row could claim one dependency set while the module's own
  # ## Preconditions claimed another and both gates stayed green. Two rows were
  # wrong that way when this was written, and one of them let the table permit
  # a combination the module could not serve.
  #
  # Prose cannot be diffed against prose: a module's Preconditions legitimately
  # mention a module they do not depend on (a database "from `docker` or from
  # wherever this project runs one"), so a rule reading the whole section
  # reports a dependency that is not one. The module therefore declares its
  # set on one line and the prose bullets below go on explaining it. The
  # declaration is strict — every backticked token on it must be a real module
  # — while the table cell stays prose and only its module names are read, so a
  # cell may say "`core`'s `lint`, `typecheck`, `test` and `build` tasks"
  # without those four becoming dependencies.
  names=$(mktemp)
  [ -n "$present" ] && printf '%s\n' "$present" > "$names"
  for m in "$skill_dir"/modules/*.md; do
    [ -e "$m" ] || continue
    mname=$(basename "$m" .md)

    req_line=$(awk '
      /^## Preconditions/ { inside = 1; next }
      /^## / { inside = 0 }
      inside && /^- Requires:/ { print; exit }
    ' "$m")
    if [ -z "$req_line" ]; then
      fail "$m" '## Preconditions carries no "- Requires:" line to check the table against'
      continue
    fi

    # A backticked token on the declaration line that is not a module is a
    # typo in the one place a typo would otherwise read as "depends on
    # nothing". Checked separately from the comparison below, which does not
    # look at backticks at all.
    for tok in $(printf '%s' "$req_line" | grep -oE '`[a-z0-9-]+`' | tr -d '`'); do
      grep -qxF "$tok" "$names" \
        || fail "$m" "\"- Requires:\" names \`$tok\`, which is not a module"
    done

    # Both sides are compared on whole-word module names, backticked or not.
    # Reading only backticked tokens made the rule agree with itself for the
    # wrong reason: "- Requires: core." against a cell reading "core", neither
    # in backticks, came out as nothing == nothing and passed.
    declared=$(printf '%s' "$req_line" | tr -c 'a-z0-9-' '\n' | grep -xF -f "$names" | sort -u)

    # The cell is found by the Requires column of the table header, on a row
    # that is a table row. Matching the first line that merely contains
    # "(modules/<name>.md)" caught prose above the table instead, and on a
    # line with no "|" at all awk's $(NF-1) is the whole line — so a sentence
    # naming a module produced a cell that happened to agree with the
    # declaration, and R9 reported nothing on a table that genuinely
    # disagreed. A row written without its trailing "|" moved the count by
    # one and read the Provides column.
    cell=$(awk -F'|' -v n="$mname" '
      !col && /^[[:space:]]*\|/ {
        for (i = 1; i <= NF; i++) {
          f = $i
          gsub(/^[[:space:]]+|[[:space:]]+$/, "", f)
          if (f == "Requires") { col = i; next }
        }
      }
      col && /^[[:space:]]*\|/ && index($0, "(modules/" n ".md)") {
        if (col <= NF) print $col
        exit
      }
    ' "$skill_file")
    if [ -z "$(printf '%s' "$cell" | tr -d '[:space:]')" ]; then
      fail "$m" 'no module-table row with a Requires cell for this module'
      continue
    fi
    tabled_req=$(printf '%s' "$cell" | tr -c 'a-z0-9-' '\n' | grep -xF -f "$names" | sort -u)

    if [ "$declared" != "$tabled_req" ]; then
      fail "$m" "Requires disagrees with the module table — module declares: $(printf '%s' "${declared:-nothing}" | tr '\n' ' '); table row says: $(printf '%s' "${tabled_req:-nothing}" | tr '\n' ' ')"
    fi
  done
  rm -f "$names"
done

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
