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
