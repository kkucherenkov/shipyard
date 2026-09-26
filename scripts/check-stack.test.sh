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

# Build a one-module stack tree in $1. $2 is the SKILL.md body, $3 the body of
# modules/sample.md. Frontmatter is fixed and valid so a case only ever
# exercises the rule it names.
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
    printf '# Monorepo stack\n\n%s\n' "$skill_body"
  } > "$root/stacks/monorepo/skills/monorepo-stack/SKILL.md"
  printf '# sample\n\n%s\n' "$module_body" \
    > "$root/stacks/monorepo/skills/monorepo-stack/modules/sample.md"
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

if [ "$failures" -gt 0 ]; then
  printf '%s failing case(s)\n' "$failures" >&2
  exit 1
fi
echo 'check-stack tests ok'
