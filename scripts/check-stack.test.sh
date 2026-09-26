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

expect() {
  want=$1
  label=$2
  root=$(mktemp -d)
  make_stack "$root" "$3" "$4"
  sh "$subject" "$root" >/dev/null 2>&1
  got=$?
  rm -rf "$root"
  if [ "$got" -ne "$want" ]; then
    printf 'FAIL want=%s got=%s %s\n' "$want" "$got" "$label" >&2
    failures=$((failures + 1))
  fi
}

# --- R1: identity nouns ---
expect 1 'rejects the source project by name' '' 'Copied from course_shelf.'
expect 1 'rejects the source package scope' '' 'Import from @app/specs.'
expect 1 'rejects the consumer by name' '' 'As todoer does it.'
expect 1 'rejects the consumer package scope' '' 'Import from @todoer/specs.'
expect 1 'rejects a card id' '' 'Tracked as E15-F03 on the board.'
expect 0 'allows a technology noun' '' 'Install NestJS and Prisma under apps/backend.'

# R2 exempts .claude-plugin/*.json from the version-pin rule (D13 requires
# plugin.json to carry "version", and that is not an install specifier), but
# R1 must still see it — the manifest's description/keywords are the
# marketplace's user-facing copy, the first thing a stranger reads. A rule
# that skips the file an identity noun actually appears in is exactly how
# layer 1 shipped one (packages/ui) undetected.
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
sh "$subject" "$root" >/dev/null 2>&1
got=$?
rm -rf "$root"
if [ "$got" -ne 1 ]; then
  printf 'FAIL want=1 got=%s an identity noun inside the plugin manifest fails\n' "$got" >&2
  failures=$((failures + 1))
fi

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
sh "$subject" "$root" >/dev/null 2>&1
got=$?
rm -rf "$root"
if [ "$got" -ne 0 ]; then
  printf 'FAIL want=0 got=%s a clean manifest keeps its own version field\n' "$got" >&2
  failures=$((failures + 1))
fi

# --- R2: pinned versions ---
expect 1 'rejects a pinned dependency specifier' '' 'Run pnpm add prisma@6.19.3 here.'
expect 1 'rejects a pinned image tag' '' '    image: postgres:18.1-alpine'
expect 1 'rejects a pinned range in a manifest block' '' '    "typescript": "^5.6.3"'
expect 0 'allows a floor with its reason' '' 'Node 24.15+, because node:sqlite removes the native dependency.'
expect 0 'allows a version quoted as evidence' '' 'set -o pipefail is not POSIX; dash rejected it until 0.5.12.'

# --- R5: a trap keeps its evidence ---
short_trap='## Traps

**Use a non-default host port.** Otherwise there is a collision.'
expect 1 'rejects a trap with no evidence' '' "$short_trap"

long_trap='## Traps

**Publish the database on a non-default host port.** A developer very likely
already has one listening on the default, and the failure that produces is not
a refused connection but a successful connection to the wrong database — which
reads as a data bug for as long as it takes somebody to notice which instance
they are talking to. A recipe that says "use a non-default port" without that
sentence gets overridden by the next person who finds it inconvenient.'
expect 0 'accepts a trap that carries its evidence' '' "$long_trap"

# --- R6: no script the recipe never creates ---
phantom='Run `pnpm spec:validate && pnpm spec:bundle`.

```json
{ "scripts": { "spec:validate": "redocly lint openapi/openapi.yaml" } }
```'
expect 1 'rejects a pnpm script with no matching key' '' "$phantom"

real='Run `pnpm spec:validate`.

```json
{ "scripts": { "spec:validate": "redocly lint openapi/openapi.yaml" } }
```'
expect 0 'accepts a pnpm script the recipe creates' '' "$real"

# --- R7: relative links resolve ---
expect 1 'rejects a dangling relative link' '' 'See [the core module](modules/core.md).'
expect 0 'accepts a link that resolves' '' 'See [the sample module](sample.md).'

if [ "$failures" -gt 0 ]; then
  printf '%s failing case(s)\n' "$failures" >&2
  exit 1
fi
echo 'check-stack tests ok'
