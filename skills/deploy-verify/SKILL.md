---
name: deploy-verify
description: Use when putting a released version on a host, rolling one back, or answering which version a host is actually running. Covers finding the stack from the running container rather than from memory, and the several ways a deploy reports success having changed nothing.
---

# Deploying and verifying a release

Putting a build on a host takes seconds. Proving it took effect is the part
that goes wrong: which version is actually serving traffic, whether a pending
migration ran, whether a rollback is even safe. Every step below exists
because one of those questions got answered by trusting something adjacent —
a container's health check, a path remembered from last time, a variable that
looks like it controls the version but no longer does.

## Where this project deploys

Read `## Deploy targets` in the project's `CLAUDE.md` — at the repository
root, or under `.claude/` if that is where this project keeps it. It names
the host, the container names, the image registry, the health endpoint, and
the stack's own compose project name. If that heading is absent, this
project has no deploy target configured — say so and stop. Do not infer one
from a compose file lying around: the procedure below is precisely about not
trusting a path you did not read from the system that is actually running.

## Find the stack from the running container

Don't type the compose directory from memory. Ask the container that is
already running for the compose file(s) that started it, via the label
Compose stamps on every service it manages, and keep the answer — every
command below reads it back instead of assuming a filename:

```sh
stack=$(docker inspect <container> --format \
  '{{index .Config.Labels "com.docker.compose.project.config_files"}}')
```

The label is `config_files`, plural: a stack can be assembled from more than
one file, comma-separated. Splitting it into a space-separated `$paths` and
reusing that unquoted — `for f in $paths`, `docker compose $files pull` — is
the same trap `ci-gates` records for `$ids`: an unquoted multi-value variable
word-splits on every shell that isn't zsh, and doesn't split at all on zsh,
so the maintainer's own shell silently collapses two files into one `-f`
argument, or one loop iteration instead of two. Read `$stack` one path per
line instead, `printf '%s\n' "$stack" | tr ',' '\n'`, everywhere below, and
build the `-f` flags Compose needs the same way:

```sh
files=$(printf '%s\n' "$stack" | tr ',' '\n' | while read -r f; do printf -- '-f %s ' "$f"; done)
```

`$files` is now itself a multi-flag string, so handing it to `docker compose`
unquoted hits the identical trap one level up. Every command below that
needs it runs it through `eval` instead — re-parsing a string as fresh shell
syntax tokenizes it on whitespace the ordinary way, in every shell, zsh
included, unlike expanding an already-stored variable.

The same source, read the same way, answers the question a deploy is
actually about — what is running right now, not what a document says should
be running — pointed at `docker ps` instead:

```sh
docker ps --format '{{.Names}} {{.Image}} {{.Status}}'
```

## Pull and restart only what changed

Restart only the services the release touches. A database and a reverse
proxy are unchanged by an application release, and restarting them buys
nothing while costing uptime.

```sh
eval "docker compose $files pull <service...>"
eval "docker compose $files up -d <service...>"
```

## Verify with the version, never the container status

`Up (healthy)` is the container's own health check. It proves the process
answers a request, not which build answered it. Ask the application itself,
through whatever endpoint the project exposes its version on, and compare the
answer against the tag just deployed.

Then read the deploy log for the migration line. "No pending migrations" on a
release you expected to carry one is not confirmation the release landed —
it is a sign the image now running is older than the one you think you just
deployed.

## Rollback

Keep a copy of every file `$stack` named, suffixed with the version you are
leaving, before touching anything. Reading it into a `while read -r` loop
rather than an unquoted `for f in $paths` is the same fix as above, for the
same reason:

```sh
printf '%s\n' "$stack" | tr ',' '\n' | while read -r f; do cp "$f" "$f.<old-version>"; done
```

A rollback then needs neither git history nor memory of the previous tag:
restore the copies and restart the same services.

```sh
printf '%s\n' "$stack" | tr ',' '\n' | while read -r f; do cp "$f.<old-version>" "$f"; done
eval "docker compose $files up -d <service...>"
```

A release that carries a database migration is not rollable this way.
Restoring an older application image against an already-migrated schema is
its own failure mode, not a fix for one. Check what migrations sit between
the old and new tags before promising a rollback, and dump the database
first.

## Traps

**A rendered compose bundle bakes the image tag in as a literal string, not
a variable.** A release pipeline that generates the compose file writes
`image: registry/service:1.6.0` directly into it at build time, so Compose
never reads a version variable back out of `.env` at deploy time — that
variable only mattered during the render, months or minutes earlier, never
after. Edit a `RELEASE_TAG`-style variable in `.env` and rerun `pull` and
`up -d`: both exit `0`, `pull` reports the image already present, `up -d`
reports the container already up to date, and a deploy script that only
checks exit codes logs a clean success — having pulled and restarted the
exact build that was already running. The first time this went unnoticed it
cost an afternoon of chasing a version mismatch back to this one line. The
only place the missed edit is visible is the compose file itself, so back it
up and read the changed line back with `grep` before pulling, not after —
`xargs`, not an unquoted `$paths`, hands each file to `sed` and `grep` as its
own argument regardless of which shell is running this:
`printf '%s\n' "$stack" | tr ',' '\n' | while read -r f; do cp "$f"
"$f.<old-version>"; done && printf '%s\n' "$stack" | tr ',' '\n' | xargs
sed -i.bak 's#service:<old>#service:<new>#' && printf '%s\n' "$stack" | tr
',' '\n' | xargs grep -n 'service:'`.

**A compose file that pins its own `name:` field ignores the directory a
command runs from.** Compose resolves the project name from that field
before it looks at the current directory, so running `docker compose up`
from a scratch checkout, a re-extracted bundle, or simply the wrong terminal
tab does not fail: it creates a second, empty stack beside the real one,
under the same name, and reports success — containers started, exit `0` —
while the stack actually serving traffic stays untouched. A deploy watched
only for that exit code calls the release done. Confirm the project a
command will hit before running it, not after: `docker compose config
--format json | jq -r .name`, compared against `docker ps --filter
label=com.docker.compose.project`.
