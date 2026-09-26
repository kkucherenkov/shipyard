# Testing

<!--
Reduced from the modules this stack actually installed. No coverage
threshold travels with this template — see the note at the end of this file
for why, before adding one back.
-->

## The pyramid

- **Unit** — every handler and pure domain function, with ports mocked. The
  bulk of the suite.
- **Integration** — controller through handler through repository, against a
  real, disposable database.
- **One end-to-end proof, against a live server.** Nothing below it exercises
  the controller in a real pipeline, the body-parser ordering, the error
  filter, or the contract validator — each of those is a property of the
  whole request pipeline, not of any one handler tested in isolation.

## Don't mock what you own

Mock ports — the interfaces the domain depends on. Don't mock the
persistence layer, and don't mock the HTTP layer: a test that mocks the thing
it is supposed to be proving passes and fails together with an implementation
detail that was never the point.

## Definition of done

A change is done when all of this holds:

1. Code and tests merged via a PR — no direct push.
2. `pnpm -w exec turbo run lint typecheck test` is green.
3. A route or channel change updated `packages/specs/openapi/openapi.yaml`
   (or the async contract) first, and the regenerated client landed in its
   own commit.
4. No `TODO` without an issue reference; no suppressed lint or type error
   without a reason written beside it.
5. Every new handler that reads a row, computes from it, and writes it back
   takes the lock `handbook.md`'s Persistence section describes, and has a
   test that proves it — staged, not raced (see below).

## The PR checklist

- [ ] No route without an OpenAPI (or AsyncAPI) entry first.
- [ ] No hand-edited file under a generated-output directory.
- [ ] No `any` used to escape a type error.
- [ ] Public, exported function signatures carry explicit return types.
- [ ] A read-modify-write handler takes its row lock, and the concurrency
      test for it was watched failing with the lock removed.
- [ ] Every new handler has a unit test with its ports mocked.
- [ ] Error paths render, not just the happy path.
- [ ] No PII or secret in a log line.

## Lessons a checklist can't carry

**A test that passes with and without the code it covers is worse than no
test**, because it reads as coverage. The only way to know is to break the
code and watch the test fail. This caught a vacuous assertion at the moment
of writing once, and a round later three more times.

**Strengthening a test is changing a test** and deserves the same proof. A
positive control added in the wrong place can make the assertion true for a
legitimate reason and silently stop measuring.

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

**Make sure the suite actually runs, and runs from a clean checkout.** A
workflow written when the repository held one kind of test does not widen
itself as workspaces appear, and a green pipeline running a tenth of the
tests looks exactly like a green pipeline. A suite that passes on every
developer machine can still fail instantly from a clean checkout — the ORM's
client generation wired to `postinstall` rather than to a CI step exists
because of exactly this (see the stack block's traps).

## On coverage

No ratchet number for coverage travels with this template, and none should be
added back without a reason attached. Such a number is a snapshot of one
repository's baseline on one day — copied into another repository it either
blocks correct work on the day it is too high, or teaches people to lower it
on the day it is too low, and both are worse than measuring coverage and
reading the number.
