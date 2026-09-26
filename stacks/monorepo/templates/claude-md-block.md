<!--
Written between <!-- STACK:BEGIN --> and <!-- STACK:END --> in the project's
CLAUDE.md, and nowhere else. Nothing outside those markers belongs to this
plugin.

Delete every section whose module this project declined. Do not leave a heading
with nothing under it: an empty section reads, to a machine, exactly like a
filled one, and to a person like an oversight to fix.
-->

## The stack

A <PACKAGE MANAGER> workspace under <TASK RUNNER>. <N> packages, and the
contract package is upstream of everything that consumes it.

| Path | What |
| --- | --- |
| `packages/specs` | The contract: the OpenAPI document and the client generated from it. |
| `apps/backend` | <FRAMEWORK> over <DATABASE>. <THE WRITE SURFACE, IN ONE LINE>. |
| `apps/cli` | <WHAT IT IS FOR, AND WHO CALLS IT>. |
| `scripts/<PROOF>.sh` | The end-to-end proof. CI runs it against a live server. |

Design and rationale live in `docs/`. Where the code and a document disagree,
<WHICH DOCUMENT IS BINDING>.

### Contract first, always

A route changes in `packages/specs/openapi/openapi.yaml` **before** it changes
in the server — the runtime validator rejects drift, so a mismatch surfaces as a
400 nobody expected rather than as a failing test.

```sh
pnpm spec:validate && pnpm spec:codegen
```

Generated artefacts land in their own commit.

### Running it

```sh
pnpm install                     # also generates the ORM client (see below)
docker compose -f docker/compose.yml up -d
pnpm -w exec turbo run build typecheck test
pnpm lint
```

<SERVICE> is published on **<REMAPPED PORT>**, remapped from the container's
<DEFAULT PORT> so it does not collide with a developer's own.

```sh
<REQUIRED ENVIRONMENT VARIABLES, ONE PER LINE>
```

### Tests need a database whose name ends in `_test`

`apps/backend/<TEST SETUP FILE>` aborts the run otherwise, and prints the two
commands that create one. The guard exists because the DB-backed specs truncate
every table in `beforeEach` with no regard for what is in them — they destroyed
the development database once before the guard was added.

### Traps, each of which cost real time

<!--
Keep every trap's evidence: what was observed, what it looked like, and what it
cost. A trap compressed to an instruction is a trap the next reader overrides.
Delete the ones whose module this project declined; add the project's own as
they are found.
-->

1. **`migrate deploy` does not generate the ORM client** — only `migrate dev`
   does, and `migrate dev` is interactive so CI never runs it. The client comes
   from the server package's `postinstall`. Without it the ORM's namespace
   silently degrades to a stub: the compiler loses its error and isolation-level
   types, transaction callbacks take an implicit `any`, and the DB-backed specs
   throw on import and are reported as `(0 test)` — which is neither a pass nor
   a failure and scrolls past as neither.
2. **The task runner filters each task's environment.** A variable set in the
   shell or on a CI job reaches a task only if that task declares it in
   `turbo.json`. Put it on the task, never in `globalEnv`, which drags it into
   the cache keys of tasks that never read it.
3. **The body parser must be registered before the contract validator.** The
   framework registers its own inside `listen()`, which runs after every
   `app.use()`, so the validator reads an undefined body and rejects **every**
   POST with a 400 complaining the body is missing. `main.ts` does this
   deliberately; do not reorder it.
4. **`scripts/<PROOF>.sh` has an `sh` shebang.** Nothing non-POSIX belongs in
   it — `set -o pipefail` is not POSIX and `dash` rejected it until 0.5.12, and
   `dash` is what `/bin/sh` points at on the runner.
5. **<THE PROJECT'S SINGLE WRITE SURFACE, IF IT HAS ONE>** — so every invariant a
   client could violate is enforced there or nowhere. List them.
6. **<ANY HAND-WRITTEN SQL THE ORM CANNOT SEE>.** The schema does not know it
   exists, so every generated migration touching those models drops it —
   silently, since nothing fails at migration time or at boot. Read the generated
   SQL of every such migration before applying it, and say here exactly what to
   delete from it.
