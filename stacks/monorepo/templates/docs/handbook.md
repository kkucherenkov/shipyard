# Handbook — backend conventions

<!--
Reduced from the modules this stack actually installed, not copied from
another project. Delete a section whose module this project declined
(`backend`, `specs`) the same way the stack block does, and do not leave a
heading with nothing under it.

A line marked "general practice" here is not something this recipe's own
steps or checks enforce — it travels because it is worth writing down once,
not because a script fails without it. Everything else is backed by a step or
a trap in this stack's `backend` or `specs` module.
-->

## Hard bans

Rejected in review, no exceptions:

- **No reading `process.env` outside the configuration class.** Everything
  else injects it. The class fails loudly at boot on a missing or empty
  value — a server that starts with half its configuration missing fails
  later, further away, and looks like a different bug.
- **No `any` used to escape a type error.** Narrow with `unknown` instead.
  General practice — nothing this stack installs enforces it beyond review.
- **No route without a contract entry first.** A route implemented before its
  `packages/specs/openapi/openapi.yaml` entry compiles, typechecks, and passes
  review; the drift is invisible until a real request hits it and comes back
  a 400 nobody wrote a test for.
- **No hand-edited file under `packages/specs/src/generated/`.** That
  directory is the contract's generator output and the reviewable artefact;
  a hand edit to it is silently gone the next time codegen runs.
- **No applied migration edited in place.** Editing applied SQL desyncs the
  migration tool's own checksum of that file, and the repair is a manual
  write to its bookkeeping table — a fresh clone refuses to migrate at all
  until someone does. Commentary goes beside a migration, never inside it.

## TypeScript

- **Explicit return types on every exported function.** General practice —
  the workspace's own lint configuration does not add a rule for it beyond
  the recommended type-checked set.
- **`noUncheckedIndexedAccess` stays on.** The case it exists for looks
  exactly like a false positive: code indexing a record by a key the type
  does not guarantee is present — a per-field timestamp map keyed by field
  name, for instance — compiles silently without the flag and hands the next
  line an `undefined` typed as a value, in precisely the case the surrounding
  logic exists to handle. The compiler is the only thing that could have
  pointed at it.

## Modules and inversion of control

The server assumes a decorator-based framework with a dependency-injection
container — that is a precondition of this stack's `backend` module, not an
incidental detail. The idiom that follows: a port is an interface the domain
depends on, an adapter is the concrete class that implements it, and the
container wires the two together — nothing constructs its own dependency with
`new`. This stack does not itself enforce that split; the one instance of it
the stack does enforce is the configuration class above, which is the same
rule applied to one specific dependency — every other class receives its
configuration through the container instead of reading `process.env` itself.

## Persistence

- **A read-modify-write takes a row lock in the same transaction —
  `SELECT … FOR UPDATE`, or the database's equivalent.** Without it, two
  concurrent updates to *different* fields of the same row can lose one of
  them silently: the loser's own timestamp gets overwritten by the winner's
  write, so a last-write-wins comparison built to repair exactly this can no
  longer tell which write is newer. Raising the isolation level trades this
  for a serialisation failure on an edit the design promises is
  conflict-free; narrowing the `UPDATE` to the changed column repairs the
  timestamp but not a version counter, and leaves the comparison running
  against a stale snapshot. Neither is a substitute for the lock.
- **Shape a read's selection for the use case, and avoid a query per row.**
  General persistence practice — the stack supplies the ORM and the lock
  above, not a batching or selection helper of its own.

## Validation

**The contract validates the wire.** The generated runtime validator checks a
request or response against `openapi.yaml` before either side's own code
runs — mount it with request and response validation **on** and security
validation **off**: authentication is a framework guard's job, and letting
the validator reject first turns a 401 into a 500 and hides which layer
actually refused.

**The application validates the invariant.** Anything the wire shape alone
cannot express — a lock that must be held, a rule that spans two fields, a
state transition that depends on what is already in the database — is the
handler's job, not the schema's. This half is general practice rather than
something the stack's own steps check; the concrete instance the stack does
check is the read-modify-write lock above.

## Errors

A global exception filter reads the status off either a framework exception
or the contract validator's own rejection, and renders the error schema the
contract declares. Two rules on the message, not one: a 4xx may carry it,
because it describes what the caller did wrong and the caller already knows
that; a 5xx never does, because it describes what broke inside and the
caller has no business seeing it. Log the 5xx's real message and stack at
`error`; log the 4xx at `warn`, with no stack.

A refused write — a stale version, a rule the schema gained after the row
was written — is the system doing exactly what it was designed to do. Log it
at `warn`, never `error`; `error` is for what a retry cannot fix and a human
should look at.

Split retryable from not by whether a retry could succeed, never by
exception class: a constraint violation and a type error live in different
classes and both mean "retrying will not help"; a timeout and a deadlock
share a class with the constraint violation and both mean "retrying will."
Keep a named set of retryable codes with the criterion written beside it, and
apply the criterion to the whole vocabulary, not only to the codes somebody
happened to name.

## API conventions

- **URI versioning under a global prefix**, so a controller declaring
  version `1` serves `/api/v1/...`. Configure the prefix once; a hand-written
  copy of it in a route decorator drifts from the real one the first time
  either changes.
- **One shared error schema**, referenced as the `default` response on every
  operation. Without a `default`, a response status with no schema makes the
  response validator throw *inside* the response, after the error filter has
  already run.
- Operation-id casing and a pagination shape (cursor vs. offset, the envelope
  fields) are general API-design conventions. Neither the contract's linter
  nor the runtime validator this stack mounts enforces either one — pick a
  convention and write it down once the project has enough endpoints for
  consistency to matter.

## Migrations

- **An applied migration is immutable.** Commentary goes beside it, never
  inside it (Hard bans, above).
- **Read the generated SQL before applying it, whenever a hand-written
  default exists.** An ORM cannot always express what a schema needs — a
  sequence shared across several tables, for instance — so the hand-written
  part becomes a standing hazard: the schema does not know it exists, and a
  later migration touching those models can generate SQL that drops it —
  silently, since nothing fails at migration time or at boot.
