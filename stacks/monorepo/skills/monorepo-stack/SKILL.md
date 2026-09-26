---
name: monorepo-stack
description: Use before scaffolding a new monorepo, and again whenever a module is added to one that already exists — a server, a CLI, a contract package, local services, or the CI gates for them. Covers which modules exist, what each requires, and why a declined module leaves nothing behind.
---

# Monorepo stack

A monorepo is not one scaffold. It is a set of parts with real dependencies
between them, and a given project wants some of them. This skill installs those
parts one at a time.

Two things are true of every part and are the reason this is a recipe rather
than a template repository:

**Versions rot; conventions do not.** Anything whose correctness expires — a
dependency version, the exact shape a generator emits this month — is installed
by calling the upstream generator, never by copying a frozen file. Anything
whose correctness does not expire — the CI structure, an agent definition, the
convention documents, the block written into `CLAUDE.md` — travels as a file
template. No version number appears anywhere in this recipe except a floor, and
a floor always arrives with the convention that justifies it: "Node 24.15+,
because `node:sqlite`" is a statement about a capability, while "Node 24.15.0"
is a statement about a Tuesday.

**Omit, never disable.** A module this project declined leaves nothing behind:
no file emitted switched-off, no commented-out target, no stub, no `if:` guard
on a CI job, no heading with nothing under it. This is not tidiness. A skipped
CI job reports green, and a required check that never started is absent from
`gh pr checks` entirely rather than pending — so a disabled gate reads as a
passing one from both directions. The same holds for prose: an empty section
reads, to a machine, exactly like a filled one.

## Before installing anything

Read what is already here. Every module below states its preconditions and what
to check for, and every module can be installed into a workspace that already
has others. There is no idempotency machinery and none is wanted: this is a set
of instructions, and the instruction is to look before acting.

## The modules

A module's name — the table's first column, and the `<name>` in
`modules/<name>.md` — is lowercase letters, digits, and hyphens only.

| Module | Provides | Requires |
| --- | --- | --- |
| [`core`](modules/core.md) | Package-manager workspace, build graph, base TypeScript config, lint, format | nothing |
| [`docker`](modules/docker.md) | A compose file for the services the project develops against, on non-colliding host ports | nothing |
| [`specs`](modules/specs.md) | An OpenAPI contract, its linter, and a typed client generated from it and shipped as built output | `core` |
| [`backend`](modules/backend.md) | An HTTP server validated against the contract at runtime, its schema, its write ordering and its authentication | `core` (and `specs`, for the runtime validator) |
| [`cli`](modules/cli.md) | A command-line client consuming the generated client, with a local store and an outbox | `specs` |
| [`ci`](modules/ci.md) | Gates matched to the modules the project installed, each a separately named check | whatever is present |

Four more modules belong in this table and are not written: a browser client, a
component package, a design-token pipeline, and a mobile client. They are absent
rather than listed as planned, because a table that advertises a module nobody
wrote misleads exactly the reader it is for. Each unblocks when a project
actually installs it.

### How to read `Requires`

`Requires` is a hard dependency, not a suggestion. A module whose requirement is
absent does not degrade — it produces debris. A contract package with no server
is a validator with nothing to validate; a token pipeline with no consumer emits
files nobody reads, and the first search of the new repository reports every
token as dangling.

So: if a requested module names a requirement this workspace does not have, say
so and ask, rather than installing the requirement silently. Installing two
modules when one was asked for is how a scaffold ends up holding things nobody
chose.

## Installing a module

The same procedure whether this is the first module in an empty directory or
the fifth added in month six.

1. **Read the module file.** Each one is `modules/<name>.md`, with the same six
   sections in the same order.
2. **Check its preconditions against what is here**, by reading the tree, not by
   asking. A module states what it needs to find and what it must not overwrite.
3. **Stop if a requirement is missing** and say which one, rather than pulling it
   in.
4. **Follow the steps.** Where a step says to call a generator, call it — do not
   write out what you remember it emitting.
5. **Run the module's `## Verify` section.** Every check there has an expected
   answer that cannot be produced by accident; a step that "looks right" is not
   a verification.
6. **Write the module's row into the project's `CLAUDE.md`**, between
   `<!-- STACK:BEGIN -->` and `<!-- STACK:END -->`, from
   [`../../templates/claude-md-block.md`](../../templates/claude-md-block.md).
   Nothing outside those markers is yours to rewrite.

There is no idempotency machinery and none is wanted. This is a set of
instructions to a reader who can look at the tree first, and step 2 is that
reader looking.

## Declining a module, and adding it later

A project that declines a module gets nothing from it: no file, no script, no
job, no heading. Every module file's `## Declining this module` section says
what that costs and — this is the part that matters — **names the steps in other
modules that disappear with it.** A module whose decline forces an edit to a
different module's files is a design defect in this recipe, not a decision for
the project to live with. If you find one, fix the recipe.

Adding a module in month six is this same procedure run again for that one
module. It is not a second plugin and not a migration: the preconditions in step
2 exist precisely so a module can be installed into a workspace that has been
running for months.

## Templates

Four files travel as templates rather than as instructions, because their
correctness does not expire with a major version.

| Template | Written to | When |
| --- | --- | --- |
| [`claude-md-block.md`](../../templates/claude-md-block.md) | between `<!-- STACK:BEGIN -->` and `<!-- STACK:END -->` in the project's `CLAUDE.md` | after every module install, rewriting only that region |
| [`docs/handbook.md`](../../templates/docs/handbook.md) | `docs/handbook.md` (or wherever the project keeps convention docs) | once, with `backend` |
| [`docs/testing.md`](../../templates/docs/testing.md) | `docs/testing.md` | once, with the first module that adds tests |
| [`workflows/test.yml`](../../templates/workflows/test.yml) | `.github/workflows/test.yml` | once, with `ci` |

Two more — a design-system document and an i18n document — belong to modules
this plugin does not yet have, and are absent rather than shipped empty.

Delete from each template every section whose module the project declined, and
replace every `<PLACEHOLDER>`. For the first three, `grep -noE '<[A-Z][^>]*>'
<file>` printing nothing is the check — the narrower `<[A-Z_ ]*>` misses a
placeholder that contains a comma, an apostrophe or a hyphen
(`claude-md-block.md` ships four of the first two and one of the third), and a
grep that only proves the letters-only placeholders were replaced is a check
that passes over a `CLAUDE.md` still carrying the rest. That anchor does not
carry over to `workflows/test.yml`: most of its placeholders start lowercase
(`<the major from engines.node>`, `<health path>`), so `ci.md:166` prescribes
`grep -n '<[^>]*>' .github/workflows/test.yml` for that file instead — and
only that file, since the unanchored form matches the literal
`<!-- STACK:BEGIN -->` / `<!-- STACK:END -->` markers `claude-md-block.md`
ships on purpose.
