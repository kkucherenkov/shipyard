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
