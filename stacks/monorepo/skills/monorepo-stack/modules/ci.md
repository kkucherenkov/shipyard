# `ci` — the gates, and what a gate has to refuse

## Preconditions

- At least one other module installed. This module's content is derived from
  which ones.
- A repository hosted somewhere that runs workflows.
- `core`'s `lint`, `typecheck`, `test` and `build` tasks present, since every
  gate is one of them.

## Steps

1. **Copy [`../../../templates/workflows/test.yml`](../../../templates/workflows/test.yml)**
   to `.github/workflows/test.yml` — singular: the file names one workflow
   regardless of how many jobs it declares, and picking one spelling here
   keeps the template, this step, and its Verify from drifting into two names
   for the same file — and **delete the job blocks and steps for every module
   this project declined.** The template marks each with a comment naming its
   module. Delete — never comment out, never guard with an `if:`.

2. **Replace every placeholder** in the copied file. Run
   `grep -n '<[^>]*>' .github/workflows/test.yml` and treat the output as the
   list of what remains; an empty result is the check, not a reading of the
   file.

3. **Keep each gate a separate job with its own name**, so a red check names
   its own cause. Lint needs no database and should not wait on one.

4. **Write the job names into the project's `CLAUDE.md` under
   `## Quality gates`**, spelled exactly as branch protection will spell them.
   This list is read by tooling, not decorative: a required check that has
   not started is absent from the check list rather than pending, so a gate
   that counts checks reads an unstarted one as passing.

5. **If the project has an end-to-end proof script**, give it an `sh`
   shebang and keep it POSIX.

6. **Declare each task's environment variables on the task in `turbo.json`**,
   not in `globalEnv` and not only on the CI job.

## What the consumer decides

The runner, how the database is provisioned, the timeouts, whether there is
an end-to-end proof script at all, and which of the named jobs branch
protection actually requires.

## Traps

**A suite that passes everywhere is not yet a suite that runs from a clean
checkout, and the difference is invisible to every local command.** The
server here typechecked and passed 83 tests on every developer machine and
failed instantly on the first honest CI run, because the ORM's client
generation was wired to nothing: `migrate deploy` — the command a CI job
reaches for, since `migrate dev` is interactive — applies migrations and does
not generate the client, while `migrate dev` does. A client generated once
during development sat in `node_modules` and made the repository look
buildable for as long as nobody started from zero. Run the generator from the
**package's own `postinstall`**, never from a CI step: a CI step fixes the
pipeline and leaves a fresh clone and the image build broken, while
`postinstall` fixes all three in one line. The general rule is worth more
than the instance: every generated artefact the build reads must be produced
by something the install runs, because the machine that has it will never
tell you it is missing.

**The failure above does not read as a missing artefact, which is why it
survives.** Against a stub client the ORM's types quietly degrade: the
namespace loses its error and isolation-level types, transaction callbacks
take an implicit `any`, and the spec files that import the client throw
during collection and are reported as `(0 test)` — a count that is neither a
pass nor a failure and scrolls past as neither.

**The task runner filters each task's environment, so a variable set on the
job does not reach the task.** The next red run after the one above had a
clean typecheck and 26 of 83 tests failing on a missing `DATABASE_URL` — a
variable the workflow sets on the job where every step can see it. The suite
passed under a direct package-filtered run and failed under the task runner
with the identical environment, and CI runs the latter. Declare the variable
on the task. Not in `globalEnv`: `env` is part of the cache key, which is
right for the task that reads the database and wrong for `build` and
`typecheck`, which would then miss cache on every change to a connection
string they never touch.

**A workflow written when the repository held one kind of test does not
widen itself as workspaces appear.** A green pipeline that runs a tenth of
the tests looks exactly like a green pipeline. Check what the job actually
executed — the count, not the colour — every time a package is added.

**The test-database guard is a repair, not defensive programming.** The
DB-backed specs truncate several tables in `beforeEach` with no regard for
what is in them, and they destroyed a development database once before the
guard existed. `backend`'s `assertTestDatabase`, loaded from `vitest.setup.ts`
through `vitest.config.ts`'s `test.setupFiles`, is that repair: any recipe
that ships truncating specs must ship it in the same module, because the gap
between the two is exactly one afternoon of somebody's data. It lives in the
shared setup file rather than in the specs that wipe, because a guard a new
spec has to remember to opt into is a guard a new spec will not have. And the
marker is a database **name** rather than an opt-out variable — a variable
exported once in a shell survives into every later command in that shell,
including the one run against the wrong database. A name cannot be exported.
This module's job is to feed that guard a name that satisfies it: the service
container's `POSTGRES_DB` above ends in `_test` for exactly this reason.

**A proof script with an `sh` shebang and a bash-ism passes on the author's
machine and fails on the runner, and the failure looks like the thing being
proved is broken.** The concrete cost: `set -o pipefail` is not POSIX and
`dash` rejected it outright until 0.5.12, which is the shell `/bin/sh` points
at on the usual runner image. The same applies to process substitution and
to `for x in $var` relying on word-splitting. Capture a command's output into
a variable and parse it afterwards rather than piping, so the exit status
stays the command's and `set -e` can see it.

**Gates must be separate checks with separate names.** One job named "CI"
that runs lint, typecheck, tests and a proof script reports one red square
for four unrelated causes, and the first thing anyone does with it is open
the log to find out which — every time. Separate names also make branch
protection expressible: you cannot require "the tests but not the proof" out
of one job.

## Declining this module

A project with no hosted CI declines it, and nothing else changes: no other
module's steps reference a workflow file, and no script reads one. What the
project loses is the only place several of the traps above are caught at
all — say so in its `CLAUDE.md` rather than leaving the gap silent.

## Verify

1. Open a pull request and confirm each gate appears as its **own** named
   check. Count them against the job list; a job that failed to parse does
   not appear and its absence is not an error anywhere.
2. `grep -n '<[^>]*>' .github/workflows/test.yml` prints nothing.
3. The proof script parses under the runner's shell, not yours:
   `dash -n scripts/<proof>.sh` (or `sh -n` where `/bin/sh` is dash).
4. From a **fresh clone into an empty directory**, `pnpm install
   --frozen-lockfile && pnpm -w exec turbo run build typecheck test` exits
   `0`. This is the clean-checkout trap checked rather than trusted, and it
   cannot be run in the working tree that has been building all along.
5. The number of tests the CI run reports matches what a local run reports.
   A suite that silently collected nothing reports `(0 test)`, which is
   neither a pass nor a failure.
