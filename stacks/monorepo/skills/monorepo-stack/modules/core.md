# `core` — workspace, build graph, TypeScript

The floor every other module stands on. Within this recipe, it is the one
module that cannot be declined.

## Preconditions

- A git repository with no `package.json` at its root, or one that is not
  already a workspace. If a workspace file already exists, read it and stop:
  this module would rewrite the build graph of a repository that has one.
- A package manager with workspace support and a task runner that understands a
  dependency graph. This recipe is written for pnpm and turbo; the conventions
  below hold for any pair with the same two capabilities, and the file names do
  not.

## Steps

1. **Initialise the workspace root.** A private root package that ships nothing,
   holding the scripts that fan out across the graph:

   ```json
   {
     "name": "<project>",
     "private": true,
     "version": "0.1.0",
     "packageManager": "pnpm@<the version you installed>",
     "engines": { "node": ">=<your floor>" },
     "scripts": {
       "build": "turbo run build",
       "test": "turbo run test",
       "typecheck": "turbo run typecheck",
       "lint": "turbo run lint && prettier --check .",
       "format": "prettier --write ."
     }
   }
   ```

   Install the dev dependencies by name and let the package manager resolve
   them — `pnpm add -Dw typescript @types/node eslint @eslint/js
   typescript-eslint prettier turbo`. Do not write versions into this file by
   hand. **Run that command after Step 2, not here**: `-Dw` means "the root of
   a workspace", and pnpm refuses it — `--workspace-root may only be used
   inside a workspace`, exit 1 — until the workspace file Step 2 writes
   exists. `@types/node` is on the list because every package in this recipe
   compiles against the runtime's own library and nothing else pulls it in;
   without it a package importing anything under `node:` fails its build with
   `TS2688: Cannot find type definition file for 'node'`.

   Then read what the resolver picked, before going further: install
   TypeScript at the major the type-aware lint plugin's peer range accepts,
   and let the resolver pick every patch. The trap below is why.

2. **Declare two workspace globs, not one**, in `pnpm-workspace.yaml`:

   ```yaml
   packages:
     - "apps/*"
     - "packages/*"
   ```

   Two, so a package is filed by *what it is* — a deployable thing or a library
   — rather than by who imports it. One glob makes that distinction a naming
   convention, and a naming convention is not enforced by anything.

3. **Declare the build graph**, in `turbo.json`. Four tasks, each waiting for
   their dependencies' builds:

   ```json
   {
     "$schema": "https://turbo.build/schema.json",
     "tasks": {
       "build": { "dependsOn": ["^build"], "outputs": ["dist/**"] },
       "typecheck": { "dependsOn": ["^build"] },
       "test": {
         "dependsOn": ["^build"],
         "env": ["<every variable this project's tests read>"]
       },
       "lint": {
         "dependsOn": ["^build"],
         "inputs": ["$TURBO_DEFAULT$", "$TURBO_ROOT$/eslint.config.mjs"]
       }
     }
   }
   ```

   A `typecheck` that does not wait for upstream builds passes against
   yesterday's types.

   **Declare a task's environment variables on the task, never in `globalEnv`.**
   The task runner runs each task in a filtered environment, so a variable set
   on a CI job or exported in a shell reaches the task only if the task names
   it. `env` is also part of the cache key, which is right for the task that
   reads a database and wrong for `build` and `typecheck` — those would miss
   cache on every change to a connection string they never read.

4. **Write the base TypeScript config**, `tsconfig.base.json`, at the root,
   extended by every package:

   ```json
   {
     "compilerOptions": {
       "target": "<a recent ES target>",
       "module": "NodeNext",
       "moduleResolution": "NodeNext",
       "strict": true,
       "noUncheckedIndexedAccess": true,
       "exactOptionalPropertyTypes": true,
       "skipLibCheck": true,
       "declaration": true,
       "sourceMap": true
     }
   }
   ```

5. **Give every package two tsconfigs, not one, and declare `include` in
   both.** `tsconfig.json` includes everything — sources, specs, and the
   package's own root-level config files, which is `"include": ["src", "*.ts"]`
   — with `noEmit: true`. Declare it rather than leaving it off: a
   `tsconfig.json` with no `include` defaults to every file under the package,
   and the default `exclude` drops `outDir` only when `outDir` is set in *that*
   file, which here it is not. So `typecheck` reads the package's own build
   output — seven `.d.ts` files out of `dist/`, measured on a tree built from
   these instructions — and quietly starts depending on whether `build` ran. `tsconfig.build.json` extends it, sets `noEmit: false`
   with `rootDir: "src"` and an `outDir`, and **re-declares `include` as
   `["src"]`** rather than inheriting the base file's. `extends` inherits
   `include` along with everything else, so a root-level file such as
   `vitest.config.ts` — swept in by the base config's `include`, but outside
   `rootDir` — fails the build with `TS6059` if the build config still
   inherits that wider `include`. On top of the narrower `include`, it
   excludes `**/*.spec.ts`. `typecheck` and ESLint read the first; `build`
   reads the second.

6. **Configure ESLint once, at the workspace root**, in `eslint.config.mjs`, as
   a flat config using the recommended type-checked rule set with the project
   service enabled, ignoring `**/dist/` and any generated directory. Add a
   final block applying the disable-type-checked preset to `**/*.{js,mjs}`, so
   config files that sit outside every tsconfig get syntax rules rather than
   an error.

   Set `@typescript-eslint/no-unused-vars` to `{ ignoreRestSiblings: true }`
   in the same file, with the reason beside it. A rest-spread omission —
   `const { seq: _seq, ...rest } = row` — is how a field is dropped from an
   object, and `backend`'s rule about guarding protocol-owned columns by an
   explicit list produces exactly that shape. Without the option the default
   rule set reports the named-and-discarded binding as unused, and the next
   reader's fix is to stop writing the omission.

7. **Configure Prettier, and keep it away from Markdown.** `.prettierrc.json`
   carrying the one setting this recipe fixes rather than leaves open, and
   the override that setting forces:

   ```json
   {
     "singleQuote": true,
     "overrides": [
       { "files": "*.{yml,yaml}", "options": { "singleQuote": false } }
     ]
   }
   ```

   The override is not taste. `singleQuote` applies to YAML too, and the
   workspace file Step 2 writes, the compose file `docker` writes and the
   workflow `ci` copies are all YAML with double-quoted scalars — so without
   it a tree built exactly from these instructions fails this module's own
   Verify item 3 on its first run, on `pnpm-workspace.yaml`, before a line of
   project code exists.

   Alongside it, a `.prettierignore` covering the lockfile, every generated
   directory, and `*.md`.

8. **Write the root `.gitignore`.** Nothing else in this recipe creates one
   and everything in it assumes one: `node_modules/`, every package's `dist/`,
   the task runner's own cache directory, `*.tsbuildinfo`, and `.env`. Without
   it `git status` is unreadable from the first install onward, and every
   later check that greps the tree — `specs`' committed-generated-source
   check, an audit that a declined module left nothing behind — reads a few
   hundred megabytes of dependencies before reaching a file anybody wrote.

9. **Create `.git-blame-ignore-revs`** at the root with a comment naming
   `git config blame.ignoreRevsFile .git-blame-ignore-revs`, and add the SHA of
   the first formatting-only commit to it once that commit exists.

## What the consumer decides

The package scope, the Node floor, the package-manager version, the ES target,
any rule set beyond the recommended type-checked one, and whether Markdown is
formatted at all (see the trap below before deciding yes).

## Traps

**`noUncheckedIndexedAccess` is not a taste setting, and the recipe has to say
why or the first person who hits a compile error turns it off.** The case it
exists for looks exactly like a false positive: code indexing a record by a key
the type does not guarantee is present — a per-field timestamp map keyed by
field name, for instance — compiles silently without the flag and hands the
next line an `undefined` typed as a value. That is precisely the case the
surrounding logic exists to handle, and the compiler was the only thing that
could have pointed at it. Carry the flag and carry this sentence with it.

**Two tsconfigs per package is not tidiness, and the failure is silent in the
direction that matters.** Two packages here each had one `tsconfig.json` that
excluded `*.spec.ts` so the build would not emit them — which meant `typecheck`
never looked at a spec file either. Six type errors were sitting in spec files
with nothing failing anywhere. They surfaced only when type-aware lint was
added, months later. The fix is structural rather than a rule anyone has to
remember: the config that excludes is the build's, and typecheck and lint read
the one that sees everything.

**`dependsOn: ["^build"]` on the `lint` task looks like over-ordering until the
first clean run.** Type-aware rules resolve types through the project graph, so
linting a package that imports a workspace library needs that library's built
output to exist. Without the dependency, lint passes on any machine with a warm
build and fails on CI — which is the worst available ordering of those two
outcomes, because the failure arrives after review rather than before it.

**Installing by name is this recipe's design, and its price is that a new
TypeScript major arrives before the tools that read the compiler API.** Both
failures land in the same install and neither is loud. The type-aware lint
plugin declares an honest peer range, so the package manager prints one
unmet-peer line per transitive package and the install still exits `0` — a
warning nobody reads at the bottom of forty lines of progress. An OpenAPI
generator declared a range that *accepted* the new major, so there was no
warning at all: it crashed at the first call with `Cannot read properties of
undefined (reading 'AnyKeyword')`, a stack trace inside the tool with nothing
pointing at the compiler version underneath it. Both cleared the moment
TypeScript was installed at the lint plugin's declared ceiling. Read the peer
ranges after the first install and pick the major from the strictest one, or
the first person to run a generator debugs somebody else's dependency tree.

**Prettier turned loose on the whole tree rewrites prose whose line breaks were
chosen.** It reflowed seventeen architecture decision records here — documents
that are records rather than code, where a line break is sometimes the author's
and a reformat destroys the diff of every later edit to them. Add `*.md` to
`.prettierignore` deliberately rather than leaving the next project to discover
it by reading a seventeen-file formatting diff. When a formatting pass does
happen, land it in a commit of its own and put that commit's SHA in
`.git-blame-ignore-revs`, so blame keeps pointing at whoever wrote the line
rather than at the formatter.

## Declining this module

There is no smaller version of `core` to fall back to inside this recipe — the
real alternative is not declining it, it is not building a monorepo. A
repository with a single deployable package needs none of `apps/*`,
`packages/*`, or a task runner that orders work across a dependency graph, and
should stop right here rather than install a workspace it will never grow into.

What actually breaks if a project tries to add a second package without this
module: nothing routes it. `apps/*` and `packages/*` are directories nobody
globs, so the package manager treats each folder as its own project with its
own `node_modules`. There is no `turbo.json`, so `build`, `typecheck`, `test`
and `lint` are commands someone runs by hand, in whatever order they remember,
with no cache and no dependency ordering — the exact failure the traps above
describe, minus the module that would have caught it. There is no shared
`tsconfig.base.json`, so `noUncheckedIndexedAccess` and the rest of `strict` are
a convention someone has to retype correctly in every package rather than a
default every package inherits. Every later module in this table names `core`
in its own `Requires` for this reason: each one adds a package to a workspace,
a task to a graph, or a type to a config this module is what defines.

## Verify

Each of these has an answer that cannot be produced by accident:

1. `grep -c '"dependsOn": \["\^build"\]' turbo.json` prints `4` — every task's
   dependency declared, checked against the file this step writes rather than
   by running the graph. `pnpm -w exec turbo run typecheck lint --dry=json`
   against the empty workspace reports `"tasks": []` regardless of whether
   `dependsOn` is set correctly, because dry-run resolves task instances per
   package and there are no packages yet — the same "nothing ran" result
   either way is the accident this check exists to rule out, not the thing to
   assert on.
2. `grep -c noUncheckedIndexedAccess tsconfig.base.json` prints `1`.
3. `pnpm exec prettier --check .` exits `0`, and adding a deliberately
   misformatted `.ts` file makes it exit non-zero. Run both halves — a formatter
   whose ignore file is too wide passes the first and fails to catch anything.
4. In any package, `pnpm exec tsc -p tsconfig.json --listFiles | grep -c '\.spec\.ts'`
   is greater than `0` once specs exist, and the same command against
   `tsconfig.build.json` prints `0`. This is the two-tsconfig split proved
   rather than assumed.
5. In any package, **after** a build has run,
   `pnpm exec tsc -p tsconfig.json --listFiles | grep -c '/dist/'` prints `0`.
   Run it after a build, never before: on an unbuilt package it prints `0`
   whether or not `include` is declared, which is the accident this check
   exists to rule out. On a package whose `tsconfig.json` has no `include`,
   the same command printed `7` here.
