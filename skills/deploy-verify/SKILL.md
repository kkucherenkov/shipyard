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
one file, comma-separated, and the value is rarely `compose.yaml` in whatever
directory happens to be the reader's current one. Split it into the raw paths
and into the `-f` flags Compose needs, once, and reuse both below:

```sh
paths=$(printf '%s' "$stack" | tr ',' ' ')
files=$(printf -- '-f %s ' $paths)
```

The same shape of command, pointed at `docker ps` instead, answers the
question a deploy is actually about — what is running right now, not what a
document says should be running:

```sh
docker ps --format '{{.Names}} {{.Image}} {{.Status}}'
```

## Pull and restart only what changed

Restart only the services the release touches. A database and a reverse
proxy are unchanged by an application release, and restarting them buys
nothing while costing uptime.

```sh
docker compose $files pull <service...>
docker compose $files up -d <service...>
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

Keep a copy of every file `$paths` named, suffixed with the version you are
leaving, before touching anything:

```sh
for f in $paths; do cp "$f" "$f.<old-version>"; done
```

A rollback then needs neither git history nor memory of the previous tag:
restore the copies and restart the same services.

```sh
for f in $paths; do cp "$f.<old-version>" "$f"; done
docker compose $files up -d <service...>
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
up and read the changed line back with `grep` before pulling, not after:
`for f in $paths; do cp "$f" "$f.<old-version>"; done && sed -i.bak
's#service:<old>#service:<new>#' $paths && grep -n 'service:' $paths`.

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
