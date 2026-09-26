# Standing up the audit instance

Restore production-shaped data into a local stack running the images that are
about to ship. Budget about twenty minutes, most of it spent waiting on an
image build.

None of the values below — the dump source, the compose file, the seeding
credentials — are fixed here. Every project shapes them differently. Pull the
dump path and the compose file from the project's own deploy documentation
(the same source a deploy skill reads to find its stack), and pull the
persona list from `## Audit personas` in the project's `CLAUDE.md`.

## 1 — Dump production, read-only

Get a read-only export of the production database onto this machine, using
whatever the project's deploy documentation names as the safe way to reach
it — an SSH host, a managed database's export tool, a scheduled backup
artefact. Nothing in this step writes back to production.

## 2 — Bring across a handful of real files

Most scenarios never touch the largest assets. Bring enough of the real ones
to exercise the routes that do — pick objects with the properties that broke
things before (a non-Latin title, an unusually long field, a file the seeded
data never produces) rather than the whole dataset.

## 3 — Build the images from the release commit

```sh
docker build -f <backend-dockerfile> -t <backend-image>:audit .
docker build -f <frontend-dockerfile> -t <frontend-image>:audit .
```

Build what ships, not what a dev server runs. A development server differs
from the release image in exactly the places these audits catch defects: the
content security policy, minification, and the rendered document.

## 4 — Run the release bundle, not the repository's own compose file

Run whatever the project publishes as its deployable artefact — a release
bundle, a tagged compose file, an infrastructure-as-code stack — not a
development compose file assembled for local iteration. The two diverge in
exactly the ways this audit exists to catch.

## 5 — Restore before the application starts

Start only the database service, restore the dump into it, then start the
rest of the stack. An application that starts against an empty database
migrates it, and the restore then fights that migration instead of landing
cleanly.

Check that any stored file-system paths in the restored data match this
stack's own mounts, or every reference to a stored file resolves to nothing.

## 6 — Seed the personas this project declared

Create one account per persona named under `## Audit personas` in the
project's `CLAUDE.md`, through whatever sign-up path the project itself
exposes, all sharing one password set as `AUDIT_PASSWORD` for the driver —
`driver.mjs` refuses to guess one, so this is the only place that password is
written down. Grant each account the access its persona implies — a role
does not always imply content access, so an admin persona may still need an
explicit grant — and leave at least one persona with nothing granted: the
account with no access is where the interesting failures live.

Space the sign-ups out if the project rate-limits them; a failed attempt
usually still counts against the limit.

## Teardown

Tear the stack down the way the project's own deploy documentation tears
down a stack stood up for testing. Keep the run's report and screenshots —
the next run compares against them.
