# `specs` — the contract and its generated client

One document that every client and the server agree on, and the package that
turns it into code.

## Preconditions

- `core` installed: the workspace globs, the build graph, and the base
  TypeScript config.
- No existing `packages/specs`. If one exists, read its `openapi.yaml` and
  extend it rather than replacing it.

## Steps

1. **Create `packages/specs`** with an OpenAPI 3.1 document at
   `openapi/openapi.yaml`. Declare `servers` with the versioned prefix the
   server will actually mount (`/api/v1`), a `securitySchemes` entry, and a
   shared error schema. Use RFC 9457 `application/problem+json` unless the
   project has a reason not to:

   ```yaml
   components:
     schemas:
       Problem:
         type: object
         required: [type, title, status]
         properties:
           type: { type: string }
           title: { type: string }
           status: { type: integer }
           detail: { type: string }
   ```

2. **Add the linter, the generator, and a bundler as dev dependencies** — a
   spec linter, an OpenAPI-to-TypeScript generator, and a bundler able to
   emit type declarations alongside its output — by name, and let the
   package manager resolve their versions. Do not write a version into the
   manifest by hand. All three are load-bearing: the bundle step in Step 4,
   the tsconfig override in Step 3, and Verify item 2's `--dts` output all
   depend on the bundler existing as a real dependency, not just as a name
   in a script string.

3. **Extend `core`'s base config in the package's own `tsconfig.json`, with
   one override.** The generator emits extension-less relative imports
   between its own files (`from "./types.gen"`), which do not resolve under
   the base config's `NodeNext`:

   ```json
   {
     "extends": "../../tsconfig.base.json",
     "compilerOptions": {
       "noEmit": true,
       // Override, this package only: the generator emits extension-less
       // relative imports between its own files, which NodeNext resolution
       // rejects. Safe only because the bundle step below resolves them at
       // build time — remove the bundler and this override starts lying.
       "module": "ESNext",
       "moduleResolution": "Bundler"
     }
   }
   ```

   This package does not need `core`'s second, build-only tsconfig: nothing
   here runs `tsc` to emit, so there is nothing to split the emitting config
   away from.

4. **Give the package its own scripts, then expose exactly two of them at the
   workspace root — and only scripts that exist.**

   ```json
   {
     "scripts": {
       "validate": "<the linter> openapi/openapi.yaml",
       "codegen": "<the generator>",
       "build": "pnpm codegen && <the bundler> src/generated/index.ts --format esm --dts --clean",
       "typecheck": "tsc --noEmit",
       "lint": "eslint ."
     }
   }
   ```

   At the workspace root:

   ```json
   {
     "scripts": {
       "spec:validate": "pnpm --filter <scope>/specs validate",
       "spec:codegen": "pnpm --filter <scope>/specs codegen"
     }
   }
   ```

   Two root scripts, not three: the bundle step is folded into the package's
   own `build`, which every consumer already gets for free from `turbo`'s
   `dependsOn: ["^build"]`. Give bundling its own root script only if the
   project genuinely gives it its own command — and if so, define it here
   rather than only in prose. The last trap below is this exact mistake,
   made once already.

5. **Make the package export built output.** `main`, `types` and `exports`
   all point at `dist/`; `files` lists `dist`:

   ```json
   {
     "main": "./dist/index.js",
     "types": "./dist/index.d.ts",
     "exports": {
       ".": { "types": "./dist/index.d.ts", "default": "./dist/index.js" }
     },
     "files": ["dist"]
   }
   ```

   `dist/` goes in the package's own `.gitignore`, while the **generated
   sources under `src/generated/` stay committed**. The generated source is
   the reviewable artefact; the bundle is not.

6. **Declare the generated client's runtime dependency explicitly.** The
   generator emits imports of its own HTTP runtime and does not add that
   runtime to `package.json` — add it to `dependencies` by hand, unpinned.

7. **Commit generated output in its own commit.** A reviewer then reads the
   contract change without the derived diff, and a regeneration that changes
   nothing shows up as an empty commit rather than as noise inside a feature.

8. **Write four rules into the document itself**, as a comment beside the
   schema each one governs — each with the failure it prevents, not just the
   rule:
   - `additionalProperties: false` on every request body. JSON Schema
     defaults to open, so a schema with a full `required` list still accepts
     any extra field — mass assignment wearing the look of a closed schema.
   - Split a variant type by its discriminator with `oneOf`. A flat schema's
     shared `required` fields promise less than the type union built from
     it, and the runtime validator enforces the schema, not the union
     (Traps below).
   - A `default` error response on every operation. Without one, a response
     status with no schema makes the response validator throw *inside* the
     response, after the error filter has already run.
   - A `summary` on every operation. It becomes the docstring on every
     generated client method (Traps below).

9. **Write the ordering rule into the project's `CLAUDE.md` stack block.**
   One sentence: the contract changes before the code that reads it. The
   first trap below is why that direction is the cheap one to get wrong.

## What the consumer decides

The package scope, which paths exist, the error schema, the linter, the
generator, whether a second client in another language is generated
alongside, and whether the bundle step gets its own root-level script or
stays folded into `build`.

## Traps

**Change the contract before the code that reads it, never the other way
round.** The runtime validator this recipe's `backend` module mounts enforces
the document on every request it handles, not on every commit. A route
implemented first and declared in the contract afterwards compiles,
typechecks, and passes review — the drift is invisible until a real request
hits it and comes back a 400 nobody wrote a test for. Moving the document
first turns that same mistake into a merge conflict or a codegen diff, both
of which are caught before a request ships rather than after.

**The default rule set errors on a missing operation summary, and the
reflex — add a config that relaxes the rule — is backwards.** A summary is
contract content, not a linter's opinion: it becomes the docstring on every
generated client method, in every language the contract is generated into.
Write the summaries. The general shape, worth stating once and applying
everywhere: fix the document, not the linter.

**The exception to that rule, and it needs naming or somebody silences the
whole rule set over one warning.** Not every default rule fits every
operation. The concrete case here: the rule requiring a 4xx response fires on
a liveness probe, which has no client error to declare — it answers, or the
process is not there to answer. Inventing a 4xx would put an impossible
response in the contract that every generated client writes a branch for.
Leave that one warning visible and unsilenced, and say in the document why. A
silenced warning and an absent one look identical six months later.

**A type union and a wire schema are different documents, and the validator
believes the schema.** A discriminated union in TypeScript says each variant
requires its own fields. One flat schema with four common `required` entries
says something much weaker, and it is the schema the runtime validator
enforces — so the types promise a guarantee nothing checks. Split by
discriminator with `oneOf`, or the union is decoration.

**A package whose contents are generated must build and export `dist/`; it
must never export raw TypeScript.** Generated code follows its generator's
idiom, and the generator here emits extension-less relative imports (`from
"./types.gen"`). A package exporting raw TypeScript does not resolve those
itself — the *consumer* does, under its own module resolution — and a server
and a CLI both compiling under `NodeNext`, where extension-less relative
imports do not resolve, fail at once and neither can fix it. The bundler
resolves them at build time and the bundle is all any consumer imports. The
evidence above is this generator's own — a generator that emitted
resolvable specifiers would not hit this particular failure — but the
export-built-output rule holds regardless, so that swapping generators is
never quietly taken as license to skip it.

**Setting `moduleResolution: "Bundler"` inside the generating package looks
like the fix and is not.** It turns that package's own typecheck green and
moves nothing for its consumers, who still resolve those imports themselves.
A recipe that stops at "give the package a tsconfig" produces exactly that: a
green gate over a broken import graph. The override is correct *only*
alongside a real bundle step, and the tsconfig has to say so in a comment or
the next person removes the bundler and keeps the override.

**Nothing catches a missing runtime dependency until a clean install.** The
generated client imports an HTTP runtime the generator does not add to
`package.json`. Typecheck passes, the import resolves through the workspace's
hoisted modules, every developer machine is fine, and it fails on the first
install that starts from nothing — which is CI, or a new contributor,
whichever comes first.

**Never write a pipeline step the project has no script for.** This
recipe's own source project once documented a three-command pipeline copied
from a different repository, where all three scripts existed; in the source
project itself, the middle one never existed. It was found when somebody ran
the documented line and got a missing-script
error, which is the cheap version of this failure. The expensive version is
a recipe that tells a new project to run three commands of which one has
never existed anywhere, and the reader who hits it cannot tell a typo from a
missing install step. Name only what you created, and check the manifest
before writing a command into prose.

## Declining this module

A project with no wire contract declines it. Two other modules name it in
`Requires`, and declining it decides them:

- **`cli` is declined with it, in full.** Its whole cheapness comes from
  consuming the generated client; a CLI written against a hand-maintained
  client is a different module and this recipe does not have it. No step of
  `cli` survives the decline.
- **`backend` keeps every step except two, and those two must be written as
  separate, independently-removable steps for exactly this reason**:
  mounting the runtime request/response validator against this module's
  document, and typing its request and response bodies from the generated
  client's types instead of hand-written ones. Everything else `backend`
  does — its configuration class, its error filter, its write ordering, its
  schema guidance — is independent of this module and stays. Both steps go
  together, not one or the other — name both, by name, in the project's
  `CLAUDE.md`, because a reader who finds no validator mounted will
  otherwise assume it was forgotten rather than declined on purpose.

Nothing in this module emits a file into another module's directory, and it
generates no client the project did not ask for. That is what makes both
declines above a deletion of this module's own files rather than an edit to
somebody else's.

## Verify

Each of these has an answer that cannot be produced by accident:

1. `pnpm spec:validate` exits `0`, with any surviving warnings explained in
   the document. This proves the document itself is well-formed; it proves
   nothing about the generated client, which is what the next three items
   check.
2. `pnpm -w exec turbo run build` produces `packages/specs/dist/index.js` and
   `packages/specs/dist/index.d.ts`. Check for both files by name; a bundler
   that emitted JavaScript and no declarations passes a build and breaks
   every consumer's typecheck.
3. From a **clean install** — `rm -rf node_modules && pnpm install
   --frozen-lockfile` — `pnpm -w exec turbo run build typecheck` exits `0`.
   This is the only check that catches the undeclared runtime dependency, and
   running it on a warm tree proves nothing.
4. `git ls-files packages/specs/src/generated` prints at least one path.
   Check this before trusting the next line — an empty result means the
   generated sources were never committed, or are gitignored by accident
   (easy to do: `core`'s own ESLint and Prettier steps tell the reader to
   ignore "any generated directory," and this is one), and in that state the
   next check goes green for exactly the wrong reason. Only once this passes
   does `git status --short packages/specs` after `pnpm spec:codegen`
   showing no change, or only files under `src/generated/`, mean what it
   claims to mean. Anything else means codegen is writing outside its own
   output directory.
