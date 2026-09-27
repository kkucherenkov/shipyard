#!/usr/bin/env sh
# Table test for check-stack.sh, driven by fixture stack trees.
#
# The rules under test are deliberately NOT check-skills.sh's. A stack recipe
# installs real software and must name it; what it must never carry is an
# identity noun (a name that means one existing repository) or a pinned
# version.
set -u

here=$(dirname "$0")
subject="$here/check-stack.sh"
failures=0

# Long enough to clear R3's length floor under "## Declining this module"
# without naming a real module — used by fixtures that are not testing that
# floor themselves (the dedicated cases near the bottom of this file are).
decline_filler='Filler long enough to clear the same length floor a real decline section has to clear: this fixture is not testing that floor, so nothing here names an actual module, but the paragraph itself has to be substantial to get past R3 regardless.'

# Build a one-module stack tree in $1. $2 is the SKILL.md body, $3 the body of
# modules/sample.md. Frontmatter is fixed and valid so a case only ever
# exercises the rule it names.
#
# sample.md always declares "- Requires: nothing." under ## Preconditions, to
# match the "nothing" its table row carries: R9 compares the two and every
# case below would otherwise fail on a rule it is not testing.
#
# sample.md always carries all six headings in canonical order, with an inert
# but full-length filler under "## Declining this module" (R3 now floors that
# section's length, same as R5 floors a Traps paragraph), and SKILL.md gets a
# table row naming it. Every R1/R2/R5/R6/R7 case below drops its tested
# snippet into this same modules/sample.md, and R3/R4 (added by Task 2) both
# scan modules/ regardless of which case put a file there — with no filler,
# no matching row, and no ordering, adding R3/R4 would fail all of them on
# something they were never testing. Only the R5 traps cases declare their
# own "## Traps" section; when module_body does, it is slotted in at the
# right point in canonical order rather than prepended, or the six headings
# would come out of order and R3's new order check would fire instead of R5.
make_stack() {
  root=$1
  skill_body=$2
  module_body=$3
  mkdir -p "$root/stacks/monorepo/skills/monorepo-stack/modules"
  {
    printf -- '---\n'
    printf 'name: monorepo-stack\n'
    printf 'description: Use when scaffolding a monorepo or adding a module.\n'
    printf -- '---\n\n'
    printf '# Monorepo stack\n\n## The modules\n\n'
    printf '| Module | Provides | Requires |\n| --- | --- | --- |\n'
    printf '| [`sample`](modules/sample.md) | something | nothing |\n\n'
    printf '%s\n' "$skill_body"
  } > "$root/stacks/monorepo/skills/monorepo-stack/SKILL.md"
  {
    printf '# sample\n\n'
    if printf '%s\n' "$module_body" | grep -qxF '## Traps'; then
      traps_block=$module_body
    else
      printf '%s\n\n' "$module_body"
      traps_block='## Traps

Filler.'
    fi
    printf '## Preconditions\n\n- Requires: nothing.\n\nFiller.\n\n'
    printf '## Steps\n\nFiller.\n\n'
    printf '## What the consumer decides\n\nFiller.\n\n'
    printf '%s\n\n' "$traps_block"
    printf '## Declining this module\n\n%s\n\n' "$decline_filler"
    printf '## Verify\n\nFiller.\n'
  } > "$root/stacks/monorepo/skills/monorepo-stack/modules/sample.md"
}

# Build a stack whose SKILL.md declares modules $2 (space separated) and whose
# modules/ directory contains files for $3 (space separated). The two lists
# differ in the R4 cases and match everywhere else. Every row says "nothing"
# under Requires and every module file declares the same, so R9 stays quiet
# unless a case sets out to trip it.
make_graph() {
  root=$1
  mkdir -p "$root/stacks/monorepo/skills/monorepo-stack/modules"
  {
    printf -- '---\nname: monorepo-stack\n'
    printf 'description: Use when scaffolding a monorepo or adding a module.\n'
    printf -- '---\n\n# Monorepo stack\n\n## The modules\n\n'
    printf '| Module | Provides | Requires |\n| --- | --- | --- |\n'
    for m in $2; do
      printf '| [`%s`](modules/%s.md) | something | nothing |\n' "$m" "$m"
    done
  } > "$root/stacks/monorepo/skills/monorepo-stack/SKILL.md"
  for m in $3; do
    {
      printf '# %s\n\n## Preconditions\n\n- Requires: nothing.\n\n## Steps\n\n1. Do it.\n\n' "$m"
      printf '## What the consumer decides\n\nNames.\n\n## Traps\n\nNone yet.\n\n'
      printf '## Declining this module\n\n%s\n\n' "$decline_filler"
      printf '## Verify\n\nIt exists.\n'
    } > "$root/stacks/monorepo/skills/monorepo-stack/modules/$m.md"
  done
}

# want=$1, label=$2, msg=$3 (a substring the FAIL output must contain when
# want=1; ignored when empty) — same contract as expect() below, for the same
# reason given in its own comment: an R4 case that names a table row with no
# file also trips R7's dangling-link check on that same row, so the exit code
# alone would not prove R4 (rather than R7) is what fired.
# tabled modules=$4, files present=$5.
expect_graph() {
  want=$1
  label=$2
  msg=$3
  root=$(mktemp -d)
  make_graph "$root" "$4" "$5"
  out=$(sh "$subject" "$root" 2>&1 >/dev/null)
  got=$?
  rm -rf "$root"
  if [ "$got" -ne "$want" ]; then
    printf 'FAIL want=%s got=%s %s\n' "$want" "$got" "$label" >&2
    failures=$((failures + 1))
    return
  fi
  if [ -n "$msg" ]; then
    case $out in
      *"$msg"*) ;;
      *)
        printf 'FAIL %s: exit code matched but message did not contain "%s": %s\n' \
          "$label" "$msg" "$out" >&2
        failures=$((failures + 1))
        ;;
    esac
  fi
}

# want=$1, label=$2, msg=$3, same contract as expect_graph() above — but the
# caller builds an arbitrary fixture tree at $root beforehand instead of going
# through make_stack/make_graph, for cases neither of those can express (a
# malformed frontmatter, a specific heading order). Exists so every ad hoc
# case gets the same want/got-then-message short-circuit as expect_graph:
# without the `return` on a want/got mismatch, one broken fixture reports as
# two failures instead of one.
expect_root() {
  want=$1
  label=$2
  msg=$3
  out=$(sh "$subject" "$root" 2>&1 >/dev/null)
  got=$?
  rm -rf "$root"
  if [ "$got" -ne "$want" ]; then
    printf 'FAIL want=%s got=%s %s\n' "$want" "$got" "$label" >&2
    failures=$((failures + 1))
    return
  fi
  if [ -n "$msg" ]; then
    case $out in
      *"$msg"*) ;;
      *)
        printf 'FAIL %s: exit code matched but message did not contain "%s": %s\n' \
          "$label" "$msg" "$out" >&2
        failures=$((failures + 1))
        ;;
    esac
  fi
}

# want=$1, label=$2, msg=$3 (a substring the FAIL output must contain when
# want=1; ignored when empty), skill_body=$4, module_body=$5.
#
# Checking only the exit code let a case go green because a DIFFERENT rule
# fired than the one it names — harmless while five rules exist, a real risk
# once Task 2 adds R3 and R4 next to the same file. Capturing stderr and
# asserting the message pins each case to its own rule, the way
# check-skills.test.sh's duplicate-trigger case already does
# (`out=$(sh "$subject" "$root" 2>&1 >/dev/null)`).
expect() {
  want=$1
  label=$2
  msg=$3
  root=$(mktemp -d)
  make_stack "$root" "$4" "$5"
  out=$(sh "$subject" "$root" 2>&1 >/dev/null)
  got=$?
  rm -rf "$root"
  if [ "$got" -ne "$want" ]; then
    printf 'FAIL want=%s got=%s %s\n' "$want" "$got" "$label" >&2
    failures=$((failures + 1))
    return
  fi
  if [ -n "$msg" ]; then
    case $out in
      *"$msg"*) ;;
      *)
        printf 'FAIL %s: exit code matched but message did not contain "%s": %s\n' \
          "$label" "$msg" "$out" >&2
        failures=$((failures + 1))
        ;;
    esac
  fi
}

# --- R1: identity nouns ---
expect 1 'rejects the source project by name' 'carries an identity noun' \
  '' 'Copied from course_shelf.'
expect 1 'rejects the source package scope' 'carries an identity noun' \
  '' 'Import from @app/specs.'
expect 1 'rejects the consumer by name' 'carries an identity noun' \
  '' 'As todoer does it.'
expect 1 'rejects the consumer package scope' 'carries an identity noun' \
  '' 'Import from @todoer/specs.'
expect 1 'rejects a card id' 'carries an identity noun' \
  '' 'Tracked as E15-F03 on the board.'
expect 1 'rejects a card id with an unpadded field' 'carries an identity noun' \
  '' 'Tracked as E15-F3 on the board.'
expect 1 'rejects centrifugo' 'carries an identity noun' \
  '' 'Add a Centrifugo service to the compose file.'
expect 0 'allows a technology noun' '' \
  '' 'Install NestJS and Prisma under apps/backend.'

# R2 excludes only the literal JSON key "version" from its manifest-block
# shape (below), which is why a manifest's own version field needs no
# separate carve-out — but R1 must still see the whole file. The
# description/keywords fields are the marketplace's user-facing copy, the
# first thing a stranger reads. A rule that skips the file an identity noun
# actually appears in is exactly how layer 1 shipped one (packages/ui)
# undetected.
root=$(mktemp -d)
make_stack "$root" '' ''
mkdir -p "$root/stacks/monorepo/.claude-plugin"
cat > "$root/stacks/monorepo/.claude-plugin/plugin.json" <<'JSON'
{
  "name": "monorepo-stack",
  "description": "As todoer does it.",
  "version": "0.1.0"
}
JSON
out=$(sh "$subject" "$root" 2>&1 >/dev/null)
got=$?
rm -rf "$root"
if [ "$got" -ne 1 ]; then
  printf 'FAIL want=1 got=%s an identity noun inside the plugin manifest fails\n' "$got" >&2
  failures=$((failures + 1))
fi
case $out in
  *'carries an identity noun'*) ;;
  *)
    printf 'FAIL an identity noun inside the plugin manifest: message did not name the reason: %s\n' "$out" >&2
    failures=$((failures + 1))
    ;;
esac
case $out in
  *'pins a version'*)
    printf 'FAIL an identity noun inside the plugin manifest: R2 fired on its own "version" field: %s\n' "$out" >&2
    failures=$((failures + 1))
    ;;
  *) ;;
esac

# The same manifest, clean of identity nouns, still carries its own
# "version": "0.1.0" — confirms R2's exemption holds without R1 objecting.
root=$(mktemp -d)
make_stack "$root" '' ''
mkdir -p "$root/stacks/monorepo/.claude-plugin"
cat > "$root/stacks/monorepo/.claude-plugin/plugin.json" <<'JSON'
{
  "name": "monorepo-stack",
  "description": "A monorepo stack plugin.",
  "version": "0.1.0"
}
JSON
out=$(sh "$subject" "$root" 2>&1 >/dev/null)
got=$?
rm -rf "$root"
if [ "$got" -ne 0 ]; then
  printf 'FAIL want=0 got=%s a clean manifest keeps its own version field\n' "$got" >&2
  failures=$((failures + 1))
fi
if [ -n "$out" ]; then
  printf 'FAIL a clean manifest keeps its own version field: expected no output, got: %s\n' "$out" >&2
  failures=$((failures + 1))
fi

# --- R1 also covers the root marketplace.json ---
# check-skills.sh scans only skills/ and commands/; check-stack.sh's loop
# above scans only stacks/. Nothing was checking the file a stranger reads
# before installing anything. R1 only: check-skills.sh's own noun list bans
# the technology nouns a stack plugin's marketplace entry may legitimately
# need to name, so this stays out of that script.
root=$(mktemp -d)
make_stack "$root" '' ''
mkdir -p "$root/.claude-plugin"
cat > "$root/.claude-plugin/marketplace.json" <<'JSON'
{
  "name": "shipyard",
  "description": "As todoer does it.",
  "plugins": []
}
JSON
out=$(sh "$subject" "$root" 2>&1 >/dev/null)
got=$?
rm -rf "$root"
if [ "$got" -ne 1 ]; then
  printf 'FAIL want=1 got=%s an identity noun in the root marketplace.json fails\n' "$got" >&2
  failures=$((failures + 1))
fi
case $out in
  *'carries an identity noun'*) ;;
  *)
    printf 'FAIL an identity noun in the root marketplace.json: message did not name the reason: %s\n' "$out" >&2
    failures=$((failures + 1))
    ;;
esac

# --- R2: pinned versions ---
expect 1 'rejects a pinned dependency specifier' 'pins a version in an install specifier' \
  '' 'Run pnpm add prisma@6.19.3 here.'
expect 1 'rejects a pinned image tag' 'pins a version in an install specifier' \
  '' '    image: postgres:18.1-alpine'
expect 1 'rejects a major-only pinned image tag' 'pins a version in an install specifier' \
  '' '    image: postgres:18-alpine'
expect 1 'rejects a pinned range in a manifest block' 'pins a version in an install specifier' \
  '' '    "typescript": "^5.6.3"'
expect 0 'allows a floor with its reason' '' \
  '' 'Node 24.15+, because node:sqlite removes the native dependency.'
expect 0 'allows a version quoted as evidence' '' \
  '' 'set -o pipefail is not POSIX; dash rejected it until 0.5.12.'
expect 0 'spares a version inside quote marks, used as trap evidence' '' \
  '' 'Turbo 2.0 silently cached it; we saw it on "1.13.4" before the bump.'
expect 0 "spares a template package.json's own version field" '' \
  '' '{ "name": "@acme/specs", "version": "0.0.0" }'

# --- R5: a trap keeps its evidence ---
short_trap='## Traps

**Use a non-default host port.** Otherwise there is a collision.'
expect 1 'rejects a trap with no evidence' 'trap without evidence' '' "$short_trap"

long_trap='## Traps

**Publish the database on a non-default host port.** A developer very likely
already has one listening on the default, and the failure that produces is not
a refused connection but a successful connection to the wrong database — which
reads as a data bug for as long as it takes somebody to notice which instance
they are talking to. A recipe that says "use a non-default port" without that
sentence gets overridden by the next person who finds it inconvenient.'
expect 0 'accepts a trap that carries its evidence' '' '' "$long_trap"

# --- R6: no script the recipe never creates ---
phantom='Run `pnpm spec:validate && pnpm spec:bundle`.

```json
{ "scripts": { "spec:validate": "redocly lint openapi/openapi.yaml" } }
```'
expect 1 'rejects a pnpm script with no matching key' 'never creates that script' '' "$phantom"

real='Run `pnpm spec:validate`.

```json
{ "scripts": { "spec:validate": "redocly lint openapi/openapi.yaml" } }
```'
expect 0 'accepts a pnpm script the recipe creates' '' '' "$real"

# --- R7: relative links resolve ---
expect 1 'rejects a dangling relative link' 'dangling link' \
  '' 'See [the core module](modules/core.md).'
expect 0 'accepts a link that resolves' '' \
  '' 'See [the sample module](sample.md).'

# --- R4: the table and the directory are the same set ---
expect_graph 0 'table and directory agree' '' 'core docker' 'core docker'
expect_graph 1 'table names a module with no file' 'tabled only: docker' \
  'core docker' 'core'
expect_graph 1 'directory holds a module the table omits' 'present only: docker' \
  'core' 'core docker'
expect_graph 0 'accepts a module name with digits' '' 'web2' 'web2'
expect_graph 1 'table row missing while the module file is present' \
  'tabled only: none; present only: core' '' 'core'

# --- R3: every module file carries the six headings, in order ---
root=$(mktemp -d)
mkdir -p "$root/stacks/monorepo/skills/monorepo-stack/modules"
{
  printf -- '---\nname: monorepo-stack\n'
  printf 'description: Use when scaffolding a monorepo or adding a module.\n'
  printf -- '---\n\n# Monorepo stack\n\n## The modules\n\n'
  printf '| Module | Provides | Requires |\n| --- | --- | --- |\n'
  printf '| [`core`](modules/core.md) | a workspace | nothing |\n'
} > "$root/stacks/monorepo/skills/monorepo-stack/SKILL.md"
{
  printf '# core\n\n## Preconditions\n\n- Requires: nothing.\n\n## Steps\n\n1. Do it.\n\n'
  printf '## What the consumer decides\n\nNames.\n\n## Traps\n\nNone yet.\n\n'
  printf '## Verify\n\nIt exists.\n'
} > "$root/stacks/monorepo/skills/monorepo-stack/modules/core.md"
expect_root 1 'a module file with no "## Declining this module"' \
  'missing required heading: ## Declining this module'

# --- R3: the six headings must appear in that order ---
root=$(mktemp -d)
mkdir -p "$root/stacks/monorepo/skills/monorepo-stack/modules"
{
  printf -- '---\nname: monorepo-stack\n'
  printf 'description: Use when scaffolding a monorepo or adding a module.\n'
  printf -- '---\n\n# Monorepo stack\n\n## The modules\n\n'
  printf '| Module | Provides | Requires |\n| --- | --- | --- |\n'
  printf '| [`core`](modules/core.md) | a workspace | nothing |\n'
} > "$root/stacks/monorepo/skills/monorepo-stack/SKILL.md"
{
  # Traps swapped ahead of Preconditions: every heading is present, none is
  # too short, but the order is wrong.
  printf '# core\n\n## Traps\n\nNone yet.\n\n## Preconditions\n\n- Requires: nothing.\n\n'
  printf '## Steps\n\n1. Do it.\n\n## What the consumer decides\n\nNames.\n\n'
  printf '## Declining this module\n\n%s\n\n## Verify\n\nIt exists.\n' "$decline_filler"
} > "$root/stacks/monorepo/skills/monorepo-stack/modules/core.md"
expect_root 1 'headings present but out of order' 'out of order'

# --- R3: "## Declining this module" must say enough to be useful ---
root=$(mktemp -d)
mkdir -p "$root/stacks/monorepo/skills/monorepo-stack/modules"
{
  printf -- '---\nname: monorepo-stack\n'
  printf 'description: Use when scaffolding a monorepo or adding a module.\n'
  printf -- '---\n\n# Monorepo stack\n\n## The modules\n\n'
  printf '| Module | Provides | Requires |\n| --- | --- | --- |\n'
  printf '| [`core`](modules/core.md) | a workspace | nothing |\n'
} > "$root/stacks/monorepo/skills/monorepo-stack/SKILL.md"
{
  printf '# core\n\n## Preconditions\n\n- Requires: nothing.\n\n## Steps\n\n1. Do it.\n\n'
  printf '## What the consumer decides\n\nNames.\n\n## Traps\n\nNone yet.\n\n'
  printf '## Declining this module\n\n## Verify\n\nIt exists.\n'
} > "$root/stacks/monorepo/skills/monorepo-stack/modules/core.md"
expect_root 1 'an empty decline section' \
  '## Declining this module says too little'

root=$(mktemp -d)
mkdir -p "$root/stacks/monorepo/skills/monorepo-stack/modules"
{
  printf -- '---\nname: monorepo-stack\n'
  printf 'description: Use when scaffolding a monorepo or adding a module.\n'
  printf -- '---\n\n# Monorepo stack\n\n## The modules\n\n'
  printf '| Module | Provides | Requires |\n| --- | --- | --- |\n'
  printf '| [`core`](modules/core.md) | a workspace | nothing |\n'
} > "$root/stacks/monorepo/skills/monorepo-stack/SKILL.md"
{
  printf '# core\n\n## Preconditions\n\n- Requires: nothing.\n\n## Steps\n\n1. Do it.\n\n'
  printf '## What the consumer decides\n\nNames.\n\n## Traps\n\nNone yet.\n\n'
  printf '## Declining this module\n\nJust don'"'"'t install it.\n\n'
  printf '## Verify\n\nIt exists.\n'
} > "$root/stacks/monorepo/skills/monorepo-stack/modules/core.md"
expect_root 1 'a one-line decline section' \
  '## Declining this module says too little'

# --- R8: the stack skill's own frontmatter (checked by nothing else) ---
root=$(mktemp -d)
mkdir -p "$root/stacks/monorepo/skills/monorepo-stack"
{
  printf -- '---\nname:\n'
  printf 'description: Use when scaffolding a monorepo or adding a module.\n'
  printf -- '---\n\n# Monorepo stack\n'
} > "$root/stacks/monorepo/skills/monorepo-stack/SKILL.md"
expect_root 1 'a stack skill with no name in frontmatter' \
  'frontmatter is missing a non-empty name'

root=$(mktemp -d)
mkdir -p "$root/stacks/monorepo/skills/monorepo-stack"
{
  printf -- '---\nname: monorepo-stack\n'
  printf 'description: Scaffolds a monorepo and adds modules to one.\n'
  printf -- '---\n\n# Monorepo stack\n'
} > "$root/stacks/monorepo/skills/monorepo-stack/SKILL.md"
expect_root 1 'a stack skill description with no trigger phrase' \
  'does not name a triggering task'

# --- R8: only the frontmatter block counts, not the whole file — a body
# line that merely starts "name:" or "description:" (plausible in a file
# whose job is teaching someone to author a module) must not stand in for
# the frontmatter key ---
root=$(mktemp -d)
mkdir -p "$root/stacks/monorepo/skills/monorepo-stack"
{
  printf -- '---\n'
  printf 'description: Use when scaffolding a monorepo or adding a module.\n'
  printf -- '---\n\n# Monorepo stack\n\n'
  printf 'A module file'"'"'s own frontmatter reads:\n\nname: sample-module\n'
} > "$root/stacks/monorepo/skills/monorepo-stack/SKILL.md"
expect_root 1 'a body line starting "name:" outside the frontmatter block' \
  'frontmatter is missing a non-empty name'

root=$(mktemp -d)
mkdir -p "$root/stacks/monorepo/skills/monorepo-stack"
{
  printf -- '---\nname: monorepo-stack\n---\n\n# Monorepo stack\n\n'
  printf 'A module file'"'"'s own description might read:\n\n'
  printf 'description: Use when adding a component.\n'
} > "$root/stacks/monorepo/skills/monorepo-stack/SKILL.md"
expect_root 1 'a body line starting "description:" outside the frontmatter block' \
  'does not name a triggering task'

# R9: the module table's Requires cell and the module's own declaration name
# the same modules. Two modules, because a dependency needs something to
# depend on: `core` requires nothing, `sample`'s cell is $4 and its own
# declaration line is $5.
# $6, optional: prose placed ABOVE the table, for the case where it carries a
# (modules/<name>.md) link of its own. $7, optional: set to "no-pipe" to write
# sample's row without its trailing "|". Both exist because a review got R9 to
# pass on a genuine disagreement through each of them.
expect_requires() {
  want=$1
  label=$2
  msg=$3
  cell=$4
  declaration=$5
  preamble=${6:-}
  row_shape=${7:-}
  root=$(mktemp -d)
  mods="$root/stacks/monorepo/skills/monorepo-stack/modules"
  mkdir -p "$mods"
  {
    printf -- '---\nname: monorepo-stack\n'
    printf 'description: Use when scaffolding a monorepo or adding a module.\n'
    printf -- '---\n\n# Monorepo stack\n\n'
    [ -n "$preamble" ] && printf '%s\n\n' "$preamble"
    printf '## The modules\n\n'
    printf '| Module | Provides | Requires |\n| --- | --- | --- |\n'
    printf '| [`core`](modules/core.md) | something | nothing |\n'
    if [ "$row_shape" = no-pipe ]; then
      printf '| [`sample`](modules/sample.md) | something | %s\n' "$cell"
    else
      printf '| [`sample`](modules/sample.md) | something | %s |\n' "$cell"
    fi
  } > "$root/stacks/monorepo/skills/monorepo-stack/SKILL.md"
  for m in core sample; do
    if [ "$m" = core ]; then
      own='- Requires: nothing.'
    else
      own=$declaration
    fi
    {
      printf '# %s\n\n## Preconditions\n\n' "$m"
      [ -n "$own" ] && printf '%s\n\n' "$own"
      printf '## Steps\n\n1. Do it.\n\n'
      printf '## What the consumer decides\n\nNames.\n\n## Traps\n\nNone yet.\n\n'
      printf '## Declining this module\n\n%s\n\n' "$decline_filler"
      printf '## Verify\n\nIt exists.\n'
    } > "$mods/$m.md"
  done
  out=$(sh "$subject" "$root" 2>&1 >/dev/null)
  got=$?
  rm -rf "$root"
  if [ "$got" -ne "$want" ]; then
    printf 'FAIL want=%s got=%s %s\n' "$want" "$got" "$label" >&2
    failures=$((failures + 1))
    return
  fi
  if [ -n "$msg" ]; then
    case $out in
      *"$msg"*) ;;
      *)
        printf 'FAIL %s: message did not mention it: %s\n' "$label" "$out" >&2
        failures=$((failures + 1))
        ;;
    esac
  fi
}

expect_requires 0 'cell and declaration agreeing on one module passes' ''   '`core`' '- Requires: `core`.'

expect_requires 0 'a cell naming non-module things alongside the module passes' ''   '`core`'"'"'s `lint` and `build` tasks' '- Requires: `core`.'

expect_requires 1 'a cell that omits a declared module fails'   'Requires disagrees with the module table'   'nothing' '- Requires: `core`.'

expect_requires 1 'a cell that adds a module the declaration omits fails'   'Requires disagrees with the module table'   '`core`' '- Requires: nothing.'

expect_requires 1 'a module with no declaration line fails'   'carries no "- Requires:" line'   'nothing' ''

expect_requires 1 'a declaration naming something that is not a module fails'   'which is not a module'   '`core`' '- Requires: `core`, `tokens`.'

# A line above the table naming a module file is prose, not that module's row.
# Reading the first line that merely contained "(modules/<name>.md)" made R9
# compare the declaration against a sentence, and on a line with no "|" at all
# awk's $(NF-1) is the whole line — so the sentence agreed and a table that
# genuinely disagreed passed.
expect_requires 1 'prose above the table is not the module row' \
  'Requires disagrees with the module table' \
  'nothing' '- Requires: `core`.' \
  'The contract package [the sample module](modules/sample.md) builds on `core`.'

# Module names count whether or not they are in backticks. Reading only
# backticked tokens let both sides come out empty for different reasons and
# agree.
expect_requires 1 'an unbackticked module name in the cell still counts' \
  'Requires disagrees with the module table' \
  'core' '- Requires: nothing.'

expect_requires 0 'an unbackticked name on both sides agrees' '' \
  'core' '- Requires: core.'

# A row without its trailing "|" has one field fewer. Counting back from the
# end read the Provides column and compared the declaration against it.
expect_requires 1 'a row with no trailing pipe is still read at its Requires column' \
  'Requires disagrees with the module table' \
  'nothing' '- Requires: `core`.' '' no-pipe

expect_requires 0 'a row with no trailing pipe passes when the two sides agree' '' \
  '`core`' '- Requires: `core`.' '' no-pipe

# Capitalisation in a cell must not delete the name. tr's complement is
# bytewise, so "Core" split into the token "ore" and stopped being a module.
expect_requires 1 'a capitalised module name in the cell still counts' \
  'Requires disagrees with the module table' \
  'Core' '- Requires: nothing.'

# A module cannot depend on itself, and a declaration that mentions its own
# name in passing reported a dependency nobody wrote.
expect_requires 0 'a declaration naming its own module in prose is not a dependency' '' \
  '`core`' '- Requires: `core`; sample stands alone otherwise.'

# A row is found by its Module cell, not by the link appearing anywhere on it.
# `core`'s row below carries a link to sample inside its own Requires cell,
# and matching the first table row containing "(modules/sample.md)" handed
# sample that cell: it reads as `core`, which is what sample declares, so the
# two agreed while sample's real row said nothing. Both rows here are
# internally consistent except sample's, so a pass is a pass for one reason.
root=$(mktemp -d)
mods="$root/stacks/monorepo/skills/monorepo-stack/modules"
mkdir -p "$mods"
{
  printf -- '---\nname: monorepo-stack\n'
  printf 'description: Use when scaffolding a monorepo or adding a module.\n'
  printf -- '---\n\n# Monorepo stack\n\n## The modules\n\n'
  printf '| Module | Provides | Requires |\n| --- | --- | --- |\n'
  printf '| [`core`](modules/core.md) | something | [`core`](modules/sample.md) |\n'
  printf '| [`sample`](modules/sample.md) | something | nothing |\n'
} > "$root/stacks/monorepo/skills/monorepo-stack/SKILL.md"
# Both declare the same pair, which is what the stolen cell reads as: the
# thief's cell is a link, so the module name in its path joins the set. Under
# the old lookup sample was handed that cell and agreed with it; under the new
# one sample reads its own row, which says nothing, and the two disagree.
for mod in core sample; do
  {
    printf '# %s\n\n## Preconditions\n\n- Requires: `core`, `sample`.\n\n' "$mod"
    printf '## Steps\n\n1. Do it.\n\n'
    printf '## What the consumer decides\n\nNames.\n\n## Traps\n\nNone yet.\n\n'
    printf '## Declining this module\n\n%s\n\n' "$decline_filler"
    printf '## Verify\n\nIt exists.\n'
  } > "$mods/$mod.md"
done
expect_root 1 'a link in a neighbour Requires cell does not steal that row' \
  'sample.md'

# A CRLF file must not slip past the frontmatter rules. Tolerating trailing
# whitespace on the fence is what lets one in, and once inside, "name:" with
# no value yields "\r", which is not empty.
root=$(mktemp -d)
mkdir -p "$root/stacks/monorepo/skills/monorepo-stack"
{
  printf -- '---\r\nname:\r\n'
  printf 'description: Use when scaffolding a monorepo or adding a module.\r\n'
  printf -- '---\r\n\r\n# Monorepo stack\r\n'
} > "$root/stacks/monorepo/skills/monorepo-stack/SKILL.md"
expect_root 1 'a CRLF file with an empty name: value still fails' \
  'frontmatter is missing a non-empty name'

# A self-link in a module's own Requires cell is a typo, not a dependency to
# be quietly dropped. Dropping it on the table side made `sample` in sample's
# own cell read as nothing and agree with "- Requires: nothing."
expect_requires 1 "a module's own name in its Requires cell is not discarded" \
  'Requires disagrees with the module table' \
  '`sample`' '- Requires: nothing.'

# A Module cell that names a second module in passing must not hand that
# module its row. Searching the cell for the link, rather than extracting the
# one link in it and comparing, meant core's row answered for sample as well:
# sample was handed "nothing", which is what it declares, while its own row
# said `core`.
root=$(mktemp -d)
mods="$root/stacks/monorepo/skills/monorepo-stack/modules"
mkdir -p "$mods"
{
  printf -- '---\nname: monorepo-stack\n'
  printf 'description: Use when scaffolding a monorepo or adding a module.\n'
  printf -- '---\n\n# Monorepo stack\n\n## The modules\n\n'
  printf '| Module | Provides | Requires |\n| --- | --- | --- |\n'
  printf '| [`core`](modules/core.md), which [`sample`](modules/sample.md) extends | something | nothing |\n'
  printf '| [`sample`](modules/sample.md) | something | `core` |\n'
} > "$root/stacks/monorepo/skills/monorepo-stack/SKILL.md"
for mod in core sample; do
  {
    printf '# %s\n\n## Preconditions\n\n- Requires: nothing.\n\n' "$mod"
    printf '## Steps\n\n1. Do it.\n\n'
    printf '## What the consumer decides\n\nNames.\n\n## Traps\n\nNone yet.\n\n'
    printf '## Declining this module\n\n%s\n\n' "$decline_filler"
    printf '## Verify\n\nIt exists.\n'
  } > "$mods/$mod.md"
done
expect_root 1 'a second module link in a Module cell does not hand over that row' \
  'sample.md'

# The declaration is read from ## Preconditions alone. A "- Requires:" line
# under a later heading is prose about some other module, and letting it count
# would put the rule back where it started: reading a dependency out of a
# sentence that was not declaring one. Built inline, because expect_requires
# only ever writes its declaration under ## Preconditions.
root=$(mktemp -d)
mods="$root/stacks/monorepo/skills/monorepo-stack/modules"
mkdir -p "$mods"
{
  printf -- '---\nname: monorepo-stack\n'
  printf 'description: Use when scaffolding a monorepo or adding a module.\n'
  printf -- '---\n\n# Monorepo stack\n\n## The modules\n\n'
  printf '| Module | Provides | Requires |\n| --- | --- | --- |\n'
  printf '| [`core`](modules/core.md) | something | nothing |\n'
  printf '| [`sample`](modules/sample.md) | something | nothing |\n'
} > "$root/stacks/monorepo/skills/monorepo-stack/SKILL.md"
{
  printf '# core\n\n## Preconditions\n\n- Requires: nothing.\n\n## Steps\n\n1. Do it.\n\n'
  printf '## What the consumer decides\n\nNames.\n\n## Traps\n\nNone yet.\n\n'
  printf '## Declining this module\n\n%s\n\n' "$decline_filler"
  printf '## Verify\n\nIt exists.\n'
} > "$mods/core.md"
{
  printf '# sample\n\n## Preconditions\n\nNothing in particular.\n\n'
  printf '## Steps\n\n- Requires: `core`.\n\n1. Do it.\n\n'
  printf '## What the consumer decides\n\nNames.\n\n## Traps\n\nNone yet.\n\n'
  printf '## Declining this module\n\n%s\n\n' "$decline_filler"
  printf '## Verify\n\nIt exists.\n'
} > "$mods/sample.md"
expect_root 1 'a "- Requires:" line under ## Steps is not a declaration' \
  'carries no "- Requires:" line'

# The block counts only when a closing "---" is found. Without that, a fence
# the author typed with a trailing space leaves every following line inside
# the "frontmatter", and the body line handed back the key it was supposed to
# stop standing in for.
root=$(mktemp -d)
mkdir -p "$root/stacks/monorepo/skills/monorepo-stack"
{
  printf -- '---\n'
  printf 'description: Use when scaffolding a monorepo or adding a module.\n'
  printf -- '--- \n\n# Monorepo stack\n\nname: invented-in-the-body\n'
} > "$root/stacks/monorepo/skills/monorepo-stack/SKILL.md"
expect_root 1 'a closing fence with a trailing space does not close the block' \
  'frontmatter is missing a non-empty name'

if [ "$failures" -gt 0 ]; then
  printf '%s failing case(s)\n' "$failures" >&2
  exit 1
fi
echo 'check-stack tests ok'
