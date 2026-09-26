# `backend` — the server

## Preconditions

- `core` installed: the workspace globs, the build graph, and the base
  TypeScript config.
- A decorator-based Node framework with a dependency-injection container,
  over an ORM with its own migration tool. This module is written for
  NestJS and Prisma, concretely, in every trap below; the conventions hold
  for any pair with those two capabilities, the names in the traps do not.
- `specs` installed, if this server is to validate requests and responses
  against the contract at runtime and type its own request and response
  bodies from the generated client. Two steps below are marked
  `(Only with specs.)` for exactly this reason — skip both together if not,
  and name both of them, by name, in the project's `CLAUDE.md`: a reader who
  finds no validator mounted will otherwise assume it was forgotten rather
  than declined on purpose.
- A database reachable, from `docker` or from wherever this project runs one.
- No existing `apps/backend`.

## Steps

1. **Scaffold the server by calling its framework's own generator into
   `apps/backend`, then delete whatever sample module it leaves behind.** Do
   not hand-write the scaffold from memory of what it emits — a generator's
   output changes between its own major versions, and a hand-copied guess is
   exactly the kind of frozen file this recipe exists not to be. The
   generator has no idea it just ran inside a workspace: delete every
   per-package **lint and formatter** configuration it wrote (`core`
   configures both once, at the workspace root, and a second config next to
   it is a second, competing answer to the same question — today's scaffold
   writes one of each, under whichever names its current defaults use), and
   rewrite the tsconfig pair it scaffolded to `core`'s own split —
   `tsconfig.json` extending `../../tsconfig.base.json` with everything
   included and `noEmit: true`; `tsconfig.build.json` extending that, with
   `rootDir`/`outDir` set and `include` re-declared as `["src"]` — since a
   freshly generated tsconfig extends nothing of this workspace's.

   Rewrite it, do not replace it wholesale: **carry the decorator options
   the generator set into the new file.** `core`'s base config has none —
   it is shared with packages that use no decorators — so a literal rewrite
   to "extends the base, plus `noEmit`" silently drops
   `emitDecoratorMetadata` and `experimentalDecorators`, and the failure
   that produces is the one in the metadata trap below: nothing throws at
   build time, and a constructor parameter comes back `undefined` inside
   the handler that uses it.

   Give the package the scripts every step from here on assumes exist,
   replacing whatever the generator wrote:

   ```json
   {
     "scripts": {
       "build": "tsc -p tsconfig.build.json",
       "typecheck": "tsc --noEmit",
       "test": "vitest run",
       "lint": "eslint ."
     }
   }
   ```

   No `postinstall` yet. It generates the ORM's client and belongs in Step
   8, written in the same edit that installs the ORM's CLI — write it here
   and the *next* `pnpm add` into this package runs it, finds no CLI, and
   aborts the install (`sh: line 1: <the CLI>: command not found`,
   `ELIFECYCLE`). Every dependency this module adds from here on goes
   through that command, so the whole module stops on its second step.

   `vitest` is this recipe's test runner for every package that has tests;
   add it as a dev dependency here, since nothing `core` installs brings a
   test runner with it. Delete whatever different one the generator wired by
   default — many default to a different runner entirely, config file and
   dev dependencies included — or `test` names two runners and only one of
   them is real.

2. **Make one class the only reader of the process environment.** Everything
   else injects it. It exposes a `required(name)` that throws on a missing or
   empty value, and any parsed value validates its own shape:

   ```ts
   private required(name: string): string {
     const value = process.env[name];
     if (value === undefined || value === '') throw new Error(`${name} is required`);
     return value;
   }
   ```

   Failing loudly at boot is the point. A server that starts with half its
   configuration missing fails later, further away, and looks like a
   different bug. Parse numbers rather than coercing them: `Number('abc')`
   is `NaN`, and binding a port of `NaN` binds a random free one — which
   starts, passes its own health check, and answers on a port nothing in the
   deployment knows about.

3. **Version the URI under a global prefix**, so a controller declaring
   version `1` serves `/api/v1/...`. Never hand-write the prefix into a
   route decorator; it is configuration, and a hand-written copy drifts from
   it silently the first time the prefix or the default version changes.

4. **Mount your own body parser explicitly, ahead of anything else added to
   the request pipeline, and disable the framework's built-in one at
   creation.** This matters even before `specs` is installed — it is also
   where the body size limit is set, see the trap on that below — and it
   becomes load-bearing the moment the step below marked
   `(Only with specs.)` that mounts a contract validator is added too:
   mounted before this step's parser has run, the validator reads an empty
   body; mounted after it, it reads the real one. See the trap below for the
   specific way this fails.

5. **`(Only with specs.)` Mount the contract validator against the spec
   package's document**, resolved **through that package's name** rather
   than by a relative path out of this package's build output — which is
   why `specs`' own Step 5 exports the document, and where a workspace that
   builds, typechecks and lints clean still dies at boot. With request and
   response validation on and **security validation off**. Authentication is a framework guard's job;
   letting the validator reject first turns a 401 into a 500 and hides which
   layer refused.

6. **`(Only with specs.)` Type every controller's request and response
   bodies from the generated client's types, not from a hand-written
   interface or the framework's own inferred shape.** A hand-written type can
   drift from the contract the moment either one changes without the other,
   and nothing catches it until a client hits the mismatch at runtime; a
   type imported from the generated client turns that same drift into a
   compile error in the commit that caused it.

7. **Install a global exception filter** that reads the status off either a
   framework exception or **anything else carrying a numeric `status`**, and
   renders the error schema the contract declares. Detect that second shape
   by its numeric `status` — and, if you also require the `message` to be a
   string because the filter reads it, require exactly that and nothing
   more. What the shape test must **not** do is exclude `Error` instances:
   the trap below explains what that costs, and it costs it on the first
   request. The second shape is only ever
   thrown by the contract validator — the `(Only with specs.)` step above
   that mounts it — so without `specs` that branch simply never fires; the
   filter itself is not one of this module's two removable steps, and stays
   regardless, since every route still throws framework exceptions on its
   own. It logs 5xx at `error` with the original object and its stack, and
   4xx at `warn` with no stack. See the two traps below: this filter is
   wrong in two specific ways that pass review.

8. **Add the ORM**, with its CLI and its client **exact-pinned to the same
   version** — not a caret on either — and pick that version from the
   *client's* release channel rather than from whatever each half's default
   tag resolves to. Check the channel before installing: the two halves are
   published separately and their default tags can sit on different majors,
   one of them a release candidate. Then wire the client-generation command
   to the package's own `postinstall`, in this step, never to a CI step —
   and make sure it does not need a connection string to run (the trap on
   that below).

9. **Put whatever the synchronisation design needs on every synchronised
   table** — a version counter, per-field timestamps, a monotonic sequence, a
   soft-delete marker — and read the trap about hand-written SQL before
   adding anything the ORM cannot express.

10. **Take a per-subject advisory lock as the first statement of every write
    transaction**, and use `SELECT … FOR UPDATE` wherever a handler reads a
    row, computes from it, and writes it back. In PostgreSQL:

    ```sql
    SELECT pg_advisory_xact_lock(<a namespace id>, hashtext(<subject id>::text));
    ```

    The namespace id only keeps this lock's keyspace separate from any other
    advisory lock the project takes; the subject id is the same value the
    write already scopes its rows by. A database without an equivalent
    transaction-scoped advisory lock needs the same guarantee some other way
    — a row lock on a per-subject row taken first, ahead of anything else in
    the transaction, is the general shape underneath the Postgres call.

11. **For authentication**: identical answers for an unknown account and a
    wrong secret, constant-time comparison including the length check the
    comparison function requires, an asynchronous key derivation, and a
    guard that takes the identity from the token and from nothing else a
    request can influence.

12. **Add the test-database guard.** Export a function — call it
    `assertTestDatabase(url)` — from `vitest.setup.ts` at the package root,
    and point `vitest.config.ts`'s `test.setupFiles` at it, so it loads
    before every spec file runs rather than being opted into by the specs
    that need it. It refuses the whole run when the database name does not
    end in `_test`, and its message prints the two commands that create one.

## What the consumer decides

The framework, the ORM, the entities and their relations, the retention
rules, the error schema, the lock's key shape, the token format, and the
schedule of any batch job.

## Traps

**The framework registers its own body parser inside `listen()`, which runs
after every `app.use()`.** So a contract validator registered the obvious way
reads an undefined body and rejects **every** POST with a 400 complaining the
body is missing a required property. It presents as "the contract is wrong",
and it is not — the contract never saw a body. Disable the built-in parser at
creation and mount your own ahead of anything else, validator included. This
was found a task late, after a change to the ordering made every POST answer
400 and the task that introduced it verified two GET requests and saw
nothing.

**The contract validator rejects with something the framework's own filter
does not recognise, and "it is a plain object" is the wrong way to
recognise it.** The default exception filter reads the status only off its
own exception type, so every validator rejection — a 400 on a bad body, a
404 on an undeclared route — surfaces as an unhandled 500. That much is
stable. What is not stable is the shape: the validator used here throws
named `Error` subclasses (`Bad Request`, `Not Found`) that carry a numeric
`status`, and a filter whose shape test *excludes* `Error` instances —
which "a plain object, not a framework exception" invites — therefore
matches none of them. Measured on a
live server, three for three: a body with an extra property, a variant
missing its discriminated field, and an undeclared route all came back
`500` with `Internal Server Error` in the body — and the 400s were logged
at `error`, with stacks. Test for the numeric `status` and nothing else,
and read the trap below before deciding what the response may then say.

**The filter must distinguish a 4xx message from a 5xx one, and the defect
that proves it recurs in every codebase that writes one.** The rule: a 4xx
may carry the message, because it describes what the caller did wrong and
the caller already knows it; a 5xx never does, because it describes what
broke inside and the caller has no business seeing it. The filter here was
written for the validator's plain object and detected that shape by asking
whether the value has a string `message`. A plain `Error` satisfies that
test identically — so a filter aimed at one narrow source silently took on
every other, and the distinction between "our message, meant for the
client" and "someone else's message that happens to be a string" existed
nowhere in the types. Both halves failed together: the exception was exposed
to an untrusted client **and** invisible in the log, because replacing the
default filter also removed its logging. A fix that only suppresses the leak
trades one failure for the other, so the test is two assertions — the 5xx
body does not contain the thrown message, **and** the logger received it. A
test that checks only the body passes on a filter that has gone silent.

**The dependency-injection metadata polyfill must be imported before
anything else in the entry point, including before the framework's own
factory call.** It patches a global that every decorator reads from at
class-definition time, so a module evaluated before the import runs collects
no metadata at all. Nothing throws at boot: the process starts, every route
answers, and the only symptom is a constructor parameter typed by another
provider coming back `undefined` inside the handler that uses it — a
container that resolved nothing, which reads exactly like a bug in that
handler rather than in an import three files away.

**The framework's default success status for a write can silently fight the
contract.** A framework that defaults a POST handler to 201 while the
contract declares 200 for the same operation sends a response the operation
has no schema for; with a `default` error schema in place (see `specs`), the
validator does not crash, but it checks a real success body against the
shape reserved for errors and rejects a request that did everything right.
Set the status the contract declares, explicitly, on every handler whose
framework default disagrees with it.

**An ORM cannot always express what the design needs, and the hand-written
part becomes a standing hazard.** One sequence shared across several tables
has no declarative form here, so its SQL was hand-written into a migration.
The schema therefore does not know the default exists, and every later
migration touching those models generates SQL that drops it — silently:
nothing fails at migration time, nothing fails at boot, and the column
starts coming back null. Write the warning in **both** places, the schema
and the migration, and read the generated SQL of every later migration
touching those models before applying it.

**Verify a hand-written migration with a query that has an expected
answer.** "Remember to append the SQL" is an instruction somebody can follow
and not notice failed. In PostgreSQL, `SELECT nextval(...), nextval(...)`
returning two consecutive numbers is a check that cannot be passed by
accident. This mattered because the symptom of the omission appeared two
tasks later, in correct-looking code, as a cursor that never advanced.

**Pin an ORM's CLI and client to the same exact version, not a range on
either.** They ship a binary protocol between them, so a range says "any of
these is compatible" about a pair for which that is simply untrue. The
drift fails neither the build nor the typecheck — it fails at runtime.
Adding them one command at a time (`pnpm add` for the client, then
`pnpm add -D` for the CLI) can itself leave them a patch apart if a new
release lands between the two calls; check both entries after, and the tell
is an asymmetry inside one file — one of the pair exact, the other a range.
Observed here, and it is worse than a patch: installing both by name put a
caret range on the client's current major in `dependencies` and an exact
prerelease of the *next* major on the CLI in `devDependencies`, because the
two packages' default tags had drifted a whole major apart and one of them
pointed at a release candidate. The mismatch did not present as a version
problem — the CLI had dropped the generate subcommand between majors, so
`postinstall` failed with `No command registered for \`generate\``, which
reads as a typo in the script. The asymmetry in the manifest was the only
honest signal, and it was right there in the diff.

**A `postinstall` that generates the ORM's client must not need a connection
string, because the install runs where there is no database.** Step 8 puts
generation in `postinstall` precisely so a fresh clone and an image build
get the client for free — and both of those, plus the lint job in `ci`'s own
workflow template, run the install with no `DATABASE_URL` set. An ORM whose
configuration resolves the connection string eagerly then fails the install
itself, not a later step: `PrismaConfigEnvError: Cannot resolve environment
variable: DATABASE_URL`, before a single package is linked. Attach the URL
to the ORM's config only when it is present, so `generate` runs without one
and the migration commands still get it. This reads as a database problem
and is a packaging one, which is why it is worth the sentence.

**An applied migration is immutable.** Commentary goes beside it, never
inside it: editing applied SQL desyncs the migration tool's own checksum of
that file, and the repair is a manual write to its bookkeeping table — the
next `migrate deploy` (or the ORM's equivalent) on a fresh clone refuses to
run at all until someone does, because the tool can no longer tell whether
the file it holds is the one it applied.

**The per-subject advisory lock is not defence in depth here — without it, a
pull can permanently skip a row.** A write takes its place in the monotonic
sequence from Step 9 and commits some time after that number is issued; two
overlapping writes of one subject can take their numbers in one order and
commit in the other, because nothing on its own serialises them. A pull that
has already seen the higher number filters everything from then on by
`seq > cursor`, and the row that committed second, carrying the lower
number, never satisfies that filter again — it is not delayed, it is gone
from that client's point of view, and silently: no error, no retry, nothing
in a log to point at. This is worth carrying as a default rather than an
option a project opts into after finding the gap, because a client that
queues writes while offline and replays them on reconnect turns overlapping
writes of one subject from a rare accident into routine traffic.

**A read-modify-write without a row lock loses one of two concurrent updates
to different fields of the same row.** This survived eight per-task reviews
here and was found only by a whole-branch one: a handler read a row,
computed from it, and wrote every column back inside a transaction at the
default isolation level, with no lock. Two concurrent updates to *different*
fields lost one of them, 39 times out of 40 — and the loser's per-field
timestamp was clobbered along with its value, so the row ended up holding
the **new timestamp against the old value**. Last-write-wins is the
mechanism meant to repair exactly this, and it cannot repair a row whose
timestamp lies; the client had been told the write applied, so it would
never retry. Take `SELECT … FOR UPDATE` in the same transaction. Two
alternatives both lose: raising the isolation level turns an ordinary
concurrent edit — the case the design promises is conflict-free — into a
serialisation failure the client must retry, and narrowing the `UPDATE` to
the changed column repairs the timestamp but not the version counter and
leaves the comparison running against a stale snapshot.

**A rules module wrapped in a per-item transaction must never throw.** If it
can, one malformed item fails the whole batch, the caller retries the same
batch, and a client that retries by default is stuck forever behind its own
bad item. Write "never throws for any object input" into the module's doc
comment as an invariant, state what it excludes, and then check every
property access, every date construction and every key enumeration against
it. The invariant held only in someone's head is the one that breaks.

**Split database errors by whether a retry could succeed, not by exception
class.** Those are orthogonal: a constraint violation and a type error live
in different classes and both mean "retrying will not help"; a timeout and a
deadlock share a class with the constraint violation and both mean
"retrying will". Getting it backwards either fails a whole batch on bad data
or turns a transient blip into a permanent refusal the person is shown and
the client discards. Keep a named set of retryable codes with the criterion
written beside it, and apply the criterion to the **whole** vocabulary, not
only to the codes somebody happened to name.

**Guard protocol-owned columns — a version counter, a sequence, a
soft-delete marker — by an explicit list, not by key order.** An object
spread that happens to place literals after a computed key protects some
fields by accident. The accident survives until somebody reorders the
lines a change later touches for an unrelated reason, and then nothing
fails: the field is simply writable by a client again, with no test that
was checking key order to fail.

**"Identical answers for an unknown account and a wrong secret" includes
time.** Answering an unknown address without doing the key-derivation work
makes the two paths differ by two orders of magnitude, which enumerates
every account on the instance with a stopwatch and no statistics. Do the
same work on the not-found path against a fixed dummy salt and hash of the
same lengths. A review that checks only the message and the status records
this property as satisfied. And derive the key **asynchronously**: a
synchronous key-derivation function on an unauthenticated endpoint is a
denial-of-service amplifier on the very server whose job is answering
requests.

**A refused write is logged at `warn`, never `error`.** A rejected
operation — a stale version, a value that fails a rule the schema gained
after the row was written — is the system doing exactly what it was
designed to do, and logging it at `error` pages whoever is on call for
every user who submits a stale edit. `error` is reserved for what a retry
cannot fix and a human should look at: a database that refused to answer at
all. Get the level backwards and either the rotation drowns in refusals
nobody needs to act on, or a genuine outage sits at `warn` where nobody is
watching for it.

**A batch job that touches many subjects must keep going when one of them
fails, and name the one that did.** Aborting the whole run on the first
failure looks safer and is not: a job that runs once against every subject
on the instance would otherwise let one malformed row cost every other
subject that run, with nothing in the log to say which one broke it. Catch
inside the per-subject loop, log the failing subject's identifier, and let
the loop continue; the job's return value is how many succeeded, not
whether all of them did.

**The body limit and the contract's own maximum must agree, in both
directions.** A limit below what the contract calls legal rejects legal
requests — a batch at the contract's declared maximum size can exceed a
framework's default limit by itself. A limit raised for one route raises it
for the unauthenticated ones too, so bound the fields in the contract
itself rather than trusting the transport limit to do it.

## Declining this module

A workspace with no server declines it. What disappears elsewhere:

- `specs` keeps every step; its contract is still generated and consumed,
  just not enforced at runtime by anything here.
- `ci` must have its database service, its `env:` block carrying
  `DATABASE_URL`, its migration step, and its three-step live-server proof
  (start, prove, stop) **deleted** from the workflow template — not
  commented out and not guarded — and the comment naming this module's
  `postinstall` in its lint job's install step removed too, since once this
  module is gone that comment describes a script that no longer exists.
- `docker`'s database service is probably unwanted too, but that is a
  question for the project rather than a consequence.

Nothing in another module writes a file under `apps/backend`, and this
module emits nothing outside it.

## Verify

1. **Two assertions on the error filter, not one**: a request that makes a
   handler throw returns a 5xx whose body does **not** contain the thrown
   message, **and** the logger received that message. Write both; a test
   that checks only the body passes on a filter that has gone silent.
2. A POST carrying a body reaches its handler with a value from that body
   already on it — assert the handler observed a specific field, not merely
   that the response wasn't 400. This is the body-parser ordering proved on
   its own terms: with `specs` declined there is no validator left to turn
   an unparsed body into a 400, so a check that only looks at the response
   status would pass whether or not the parser runs, and prove nothing about
   the ordering it exists to protect. No GET request proves this either way.
3. If `specs` is installed: every class of contract rejection comes back
   with its own status, from a running server — not a unit test of the
   filter. A body with an extra property and a variant missing a required
   field both answer `400`; an undeclared route answers `404`; the response
   content type is the error media type the contract declares. Check the
   status codes, not merely that something non-2xx came back: the filter
   defect above answers every one of these `500`, which is non-2xx too.
4. If `specs` is installed: change the contract's schema for a field on an
   operation whose controller already types its body from the generated
   client, and watch that controller fail to typecheck without a matching
   edit. This proves the typing is real rather than a hand-written lookalike
   that happens to compile today.
5. If a hand-written default was added to a migration: in PostgreSQL,
   `SELECT nextval('<sequence>'), nextval('<sequence>')` returns two
   consecutive numbers.
6. The server refuses to start with a required variable unset, and the
   error names the variable.
7. Concurrency is verified **staged, not raced**: one client pauses inside
   its transaction immediately after the read, the other is released from
   its first statement, which makes the interleaving deterministic instead
   of timing-dependent. Then watch it both ways — with the lock removed it
   must fail every time, with the lock in place it must pass every time.
   Five of five and ten of ten is what was run here. A concurrency test
   nobody has watched fail is the least trustworthy kind of test there is,
   and a test of two operations arriving out of order *sequentially* is not
   a test of concurrency at all, though it reads exactly like one.
8. `pnpm --filter <scope>/backend test` refuses to run when the database
   name does not end in `_test`, and prints the two commands that create
   one.
