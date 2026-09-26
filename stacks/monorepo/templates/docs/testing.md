# Testing

<!--
Reduced from the modules this stack actually installed, not copied from
another project. Delete a section whose module this project declined
(`backend`, `ci`) the same way the stack block does, and do not leave a
heading with nothing under it.

A line marked "general practice" here is not something this recipe's own
steps or checks enforce — it travels because it is worth writing down once,
not because a script fails without it. A line naming `backend`, `specs` or
`ci` is backed by a step or a trap in that module. No coverage ratchet
travels with this template — see the note at the end of this file for why,
before adding one back.
-->

## The pyramid

Unit, integration, one end-to-end proof is general testing practice; this
stack backs two concrete pieces of it, not the shape as a whole:

- **Unit** — handler and pure domain function tests, with ports mocked.
  General practice; nothing this stack installs specifies a mocking
  convention (see "Don't mock what you own," below, which is general
  practice too).
- **Integration** — through the real persistence layer, against a database
  whose name ends in `_test`. That guard is real: `backend`'s test-database
  check (the stack block's own trap) refuses to run against anything else.
- **One end-to-end proof, against a live server.** `ci`'s own tier: its
  Preconditions ask for an unauthenticated health route before this is wired
  in, and its own step places the proof script the workflow's live-server job
  runs. Nothing below this tier exercises the controller in a real pipeline,
  the body-parser ordering, or the error filter as installed — each of those
  is a property of the whole request pipeline, not of any one handler tested
  in isolation.

## Don't mock what you own

Mock ports — the interfaces the domain depends on — not the persistence
layer and not the HTTP layer: a test that mocks the thing it is supposed to
be proving passes and fails together with an implementation detail that was
never the point. General testing practice; no module in this stack specifies
a mocking convention, but the seam it names (a port) is the one `backend`
does establish (Modules and inversion of control, `handbook.md`).

## Definition of done

A change is done when all of this holds:

1. Code and tests merged via a PR — no direct push. General practice.
2. `pnpm -w exec turbo run lint typecheck test` is green. The tasks
   themselves are `core`'s; requiring them green before merge is general
   practice.
3. A route or channel change updated `packages/specs/openapi/openapi.yaml`
   (or the async contract) first, and the regenerated client landed in its
   own commit. `specs`'s own ordering rule and commit convention.
4. No `TODO` without an issue reference; no suppressed lint or type error
   without a reason written beside it. General practice.
5. Every new handler that reads a row, computes from it, and writes it back
   takes the lock `handbook.md`'s Persistence section describes, and has a
   test that proves it — staged, not raced (see below). `backend`'s own
   trap, both halves.

## The PR checklist

Backed by a step or a trap in this stack:

- [ ] No route without an OpenAPI (or AsyncAPI) entry first (`specs`).
- [ ] No hand-edited file under a generated-output directory (`specs`).
- [ ] A read-modify-write handler takes its row lock, and the concurrency
      test for it was watched failing with the lock removed (`backend`).

General practice — not enforced by anything this stack installs, carried
because it is worth checking anyway:

- [ ] No `any` used to escape a type error.
- [ ] Public, exported function signatures carry explicit return types.
- [ ] Every new handler has a unit test with its ports mocked.
- [ ] Error paths render, not just the happy path.
- [ ] No PII or secret in a log line.

## Lessons a checklist can't carry

**A test that passes with and without the code it covers is worse than no
test**, because it reads as coverage. The only way to know is to break the
code and watch the test fail. This caught a vacuous assertion at the moment
of writing once, and a round later three more times. General testing
practice — no module in this stack states it, and it travels because it is
worth writing down once.

**Strengthening a test is changing a test** and deserves the same proof. A
positive control added in the wrong place can make the assertion true for a
legitimate reason and silently stop measuring. General testing practice,
same standing as the lesson above.

**A concurrency test must be staged, not raced, and watched failing.** Two
operations arriving out of order *sequentially* is not concurrency, and a
test of it reads exactly like coverage of concurrency while proving nothing
about it — a test built this way passed here while the read-modify-write
defect it should have caught (Persistence, `handbook.md`) went unnoticed
through several rounds of review. Stage it instead: one client pauses inside
its transaction immediately after the read, the other is released from its
first statement. Then verify both directions — with the lock removed it must
fail every time, with the lock in place it must pass every time. Five of
five and ten of ten is what a staged version of this test actually produced.
`backend`'s own trap and Verify step.

**Make sure the suite actually runs, and runs from a clean checkout.** A
workflow written when the repository held one kind of test does not widen
itself as workspaces appear, and a green pipeline running a tenth of the
tests looks exactly like a green pipeline. A suite that passes on every
developer machine can still fail instantly from a clean checkout — the ORM's
client generation wired to `postinstall` rather than to a CI step exists
because of exactly this (see the stack block's traps). `ci`'s own traps,
both halves.

## On coverage

No ratchet number for coverage travels with this template, and none should be
added back without a reason attached. Such a number is a snapshot of one
repository's baseline on one day — copied into another repository it either
blocks correct work on the day it is too high, or teaches people to lower it
on the day it is too low, and both are worse than measuring coverage and
reading the number.
