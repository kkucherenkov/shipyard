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

## Find the stack from the running container

Don't type the compose directory from memory. Ask the container that is
already running for the compose file(s) that started it, via the label
Compose stamps on every service it manages:

```sh
docker inspect <container> --format \
  '{{index .Config.Labels "com.docker.compose.project.config_files"}}'
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
docker compose pull <service...>
docker compose up -d <service...>
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

Keep a copy of the compose file named after the version you are leaving —
`compose.yaml.<old-version>` next to `compose.yaml` — before touching
anything. A rollback then needs neither git history nor memory of the
previous tag: restore the copy and restart the same services.

A release that carries a database migration is not rollable this way.
Restoring an older application image against an already-migrated schema is
its own failure mode, not a fix for one. Check what migrations sit between
the old and new tags before promising a rollback, and dump the database
first.

## Where this project deploys

Read `## Deploy targets` in the project's `CLAUDE.md` — at the repository
root, or under `.claude/` if that is where this project keeps it. It names
the host, the container names, the image registry, the health endpoint, and
the stack's own compose project name. If that heading is absent, this
project has no deploy target configured — say so and stop. Do not infer one
from a compose file lying around: the procedure above is precisely about not
trusting a path you did not read from the system that is actually running.

## Traps

**A rendered compose bundle bakes the image tag in as a literal string, not
a variable.** A release pipeline that generates `compose.yaml` writes
`image: registry/service:1.6.0` directly into the file at build time, so
Compose never reads a version variable back out of `.env` at deploy time —
that variable only mattered during the render, months or minutes earlier,
never after. Edit a `RELEASE_TAG`-style variable in `.env` and rerun `pull`
and `up -d`: both exit `0`, `pull` reports the image already present, `up -d`
reports the container already up to date, and a deploy script that only
checks exit codes logs a clean success — having pulled and restarted the
exact build that was already running. The only place the missed edit is
visible is the compose file itself, so read the changed lines back with
`grep` before pulling, not after: `sed -i 's#service:<old>#service:<new>#'
compose.yaml && grep -n 'service:' compose.yaml`.

**A compose file that pins its own `name:` field can send a command to a
stack you didn't mean to touch.** Compose resolves the project name from
that field before it looks at the current directory, so running
`docker compose up` from a scratch checkout, a re-extracted bundle, or simply
the wrong terminal tab does not fail — it either creates a second, empty
stack beside the real one, or drives the real one, depending on which
directory's label Compose matches first. Either way `up -d` exits `0` and
prints containers started, and a deploy watched only for that exit code
calls it done while the stack actually serving traffic stays untouched.
Confirm the project a command will hit before running it, not after:
`docker compose config --format json | jq -r .name`, compared against
`docker ps --filter label=com.docker.compose.project`.
