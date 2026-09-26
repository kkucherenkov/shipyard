# shipyard-monorepo

The stack layer of [`shipyard`](../../README.md). `shipyard` carries process —
the task stack, lane discipline, CI gating, issue bookkeeping, deploy
verification, the release audit. This plugin carries the shape of one kind of
repository: a package-manager workspace under a build graph, with a contract
package upstream of the things that consume it.

It is a **recipe**, not a template repository. Nothing here is a frozen copy of
a working project, because the parts of a working project worth copying are the
ones that stop being true — the dependency versions, the generator output, the
lockfile. What travels instead is the instruction to call the generator, the
conventions that outlive its major versions, and every trap that cost somebody a
day, with the evidence still attached.

## What it does not do

- It does not install what you did not ask for. Six modules exist; a project
  takes the ones it needs and the rest leave no trace.
- It does not carry a version number. A floor, where a convention depends on
  one; never a pin.
- It does not carry a lockfile, a dependency override, or a workaround pinned
  for a bug in somebody else's repository.
- It does not cover a browser client, a component package, a design-token
  pipeline or a mobile client. Those modules are unwritten because no project
  has installed them yet, and writing them from memory is how a template dies.

## Install

```sh
/plugin marketplace add kkucherenkov/shipyard   # once per machine
/plugin install shipyard-monorepo
```

Then ask for the module you want. The skill names its preconditions, checks
what is already present, and stops rather than guessing.

## The contract with the other layer

`shipyard` and `project-skeleton` own a project's `CLAUDE.md`; this plugin owns
exactly the region between `<!-- STACK:BEGIN -->` and `<!-- STACK:END -->` and
rewrites nothing outside it. Without those markers a reinstall has two bad
options — overwrite the file and lose hand edits, or leave it and never update.

The agents under `agents/` ship with the modules whose surface they own, and no
others. An agent without its surface produces confident work in the wrong
idiom.

## License

MIT. See [`../../LICENSE`](../../LICENSE).

## Validated

Last run: 2026-09-27. Every in-scope module was installed from these
instructions into an empty directory, and the resulting workspace installed
from a cleared `node_modules` with a frozen lockfile, then built, typechecked,
linted and tested clean. The server was started from its own build and driven
over HTTP: the contract's rejections, the error filter's two halves, the
body-parser ordering and the configuration guard were checked against a
running process rather than reasoned about. A second tree was generated with
the contract and CLI modules declined; it left no reference to either,
disabled nothing, and passed the same gates.

Three things were **not** run, and saying so is part of the record. No hosted
runner has executed the workflow template: it was filled in, parsed and
formatted, and its steps were run by hand locally. `backend`'s staged
concurrency verification — the same transaction interleaving watched ten
times with the lock and ten without — was not built, so the advisory lock and
the row lock are present in generated code and unexercised. And `ci`'s two
shell checks needed a container, because the machine's `/bin/sh` was not the
runner's; they ran there rather than here.

The run rewrote the recipe in fifteen places, and made seven smaller
corrections in the same files. Two were instructions that could not be
followed in the order they were given — each stopped the run at the command
it named. Eight were configuration keys, or whole files, that the recipe
assumed and never told anyone to create. Three were claims about a tool's
behaviour that the current version of that tool contradicts. One was a check
that could not have caught what it was written for. The last was a
contradiction between two modules, and it is the one worth remembering: it
left every gate green and the server refusing to start.

Re-run this when a module changes. A recipe that calls upstream generators
goes stale silently — the generators move and the instructions do not — so the
run is what reports the staleness, and the date above is how long ago
something last did.
