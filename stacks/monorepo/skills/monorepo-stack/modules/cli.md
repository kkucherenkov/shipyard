# `cli` — a command-line client

The module that costs almost nothing, entirely because `specs` already exists.

## Preconditions

- `core` and `specs` installed. Without `specs` this is a different module and
  this recipe does not have it: a CLI written against a hand-maintained client
  is not cheap and does not stay in agreement with the server.
- This module is TypeScript for the same reason, not as a default: its whole
  cost comes from consuming `specs`' generated client in the language that
  client is generated in. A command-line client in a different language is a
  sibling module this recipe does not have, not a variant of this one.
- No existing `apps/cli`.

## Steps

1. **Create `apps/cli/package.json`** as a private package depending on the
   contract package from the workspace, with a `bin` entry pointing at its
   built entry point. That entry point's first line is a `#!/usr/bin/env
   node` shebang — the line a `bin` script needs in order to run directly
   rather than only through `node dist/index.js` — and the TypeScript
   compiler preserves it verbatim in the emitted file. Give the package
   `core`'s own two-tsconfig split, `tsconfig.json` and
   `tsconfig.build.json`, and the scripts every turbo task from here on
   assumes exist:

   ```json
   {
     "name": "<scope>/cli",
     "private": true,
     "type": "module",
     "bin": { "<binary name>": "./dist/index.js" },
     "scripts": {
       "build": "tsc -p tsconfig.build.json",
       "typecheck": "tsc --noEmit",
       "test": "vitest run",
       "lint": "eslint ."
     },
     "dependencies": {
       "<scope>/specs": "workspace:^"
     }
   }
   ```

   `vitest` is this recipe's test runner for every package that has tests;
   add it as a dev dependency here too, since nothing `core` installs brings
   one — and `@types/node`, which this package needs more than most, since
   its store comes out of the runtime's own standard library. A script this
   file does not declare is a task `turbo run` never sees for this package —
   it drops silently out of every workspace-wide `build`, `typecheck`,
   `test` or `lint`, rather than failing one.

   **Declare `test` in the same commit as the package's first spec, not
   before.** The runner exits non-zero when it finds no test files, so a
   declared-but-empty `test` script fails the whole workspace run from the
   moment this package exists — and the obvious repair, a flag that passes
   when nothing was collected, manufactures exactly the silent hole `ci`'s
   own traps are about. The Verify list below is five behaviours; write one
   of them as the first spec.

2. **Read and validate the whole configuration in one place, at startup**,
   and refuse to start rather than failing at first use. Same reasoning as
   the server's configuration class, and the same failure if skipped: a
   process that runs with half its configuration fails later, further away.

3. **Treat exit codes as part of the interface.** A caller must be able to
   tell from the code alone whether to retry, to fix its input, or to stop.
   Write the table into the CLI's own help output, not only into a document.

4. **Parse arguments so that everything after the positional is content.** A
   `-h` inside a task title is part of the title, not a request for help.

5. **Give it a local store holding two things**: a replica of the server's
   rows, and an outbox of operations not yet acknowledged. Prefer a store the
   runtime has built in over one that needs compiling — that choice is what
   keeps the CLI from being the hardest thing in the workspace to install,
   and it is the one place this recipe names a version floor (see the
   traps).

6. **Present reads as the outbox overlaid on the replica**, and guard unknown
   identifiers on every read path.

## What the consumer decides

The argument parser, the output format, the exit-code vocabulary, the runtime
floor, and the store.

## Traps

**The runtime floor is a real constraint and belongs in the recipe as a
minimum rather than a pin.** The CLI here requires a runtime version recent
enough to carry an embedded SQL database in its standard library, and that
single requirement is what removes the native dependency that would
otherwise make this the hardest package in the workspace to install — on
every contributor machine and in every container image. Write it the way the
requirement actually reads: "Node 24.15+, because `node:sqlite`", never
"Node 24.15.0". The first is a statement about a capability and stays true;
the second is a statement about a Tuesday and is wrong by the next release.

**A CLI that shows the server's rows is wrong the moment it queues an
operation**, because the user's own last action is then the one thing
missing from the screen — and the user has no way to tell "not sent yet"
from "did not work". The fix is to overlay the outbox on the replica for
every read, and the cost is an unknown-identifier guard on every read path.
That guard is not optional and not defensive: the outbox can name a row the
replica has never seen, because the operation that creates a row is itself
in the outbox.

## Declining this module

The clean case, and worth reading as the example of what a clean decline
looks like. Nothing else in this recipe reaches into `apps/cli`: no other
module's script writes a file under it, no other module's build reads from
it, no CI job outside this module's own gate mentions it, and no shared
script branches on whether it is present. Declining it is deleting this
module's own steps and nothing else.

That is the property every module is supposed to have. If a future module
cannot say this paragraph about itself, the seam belongs in the recipe's own
design rather than in the project that hits it.

## Verify

1. `<cli> add "fix the -h flag"` stores a title containing `-h` and does not
   print help.
2. With a required configuration value unset, the process exits non-zero
   before doing any work, and the message names the value.
3. An operation queued while the server is unreachable appears in the next
   `list` **before** any successful sync. This is the overlay proved; a list
   that only shows it after a sync is reading the replica.
4. A read that touches an outbox entry naming a row the replica has never
   seen returns without throwing.
5. The documented exit code for a retryable failure differs from the one for
   a bad input, and both differ from `0`. Check the actual codes; a CLI that
   exits `1` for everything has documented a vocabulary it does not speak.
