# `docker` — local service dependencies

Everything the project needs running to develop against, and nothing it does
not. It stands apart from the rest of this recipe: its `Requires` is nothing,
not even `core`. A repository can want a database in a container before it
has a package manager workspace at all, and nothing below reads a file `core`
writes.

## Preconditions

- Requires: nothing.
- No `docker/compose.yml` already present. If there is one, read it: this
  module adds services to it rather than replacing it.
- A container runtime with Compose support on the machine.

## Steps

1. **Create `docker/compose.yml` with an explicit project name.** Compose
   derives one from the directory otherwise, so two checkouts of the same
   repository silently share one stack and rewrite each other's services:

   ```yaml
   name: <project>-dev
   ```

2. **Publish every service on a non-default host port**, remapped from the
   image's own. Give each a healthcheck and a named volume where it holds
   state:

   ```yaml
   services:
     <service>:
       image: <image>:<the tag you chose>
       environment: {} # the service's own config, e.g. a database's credentials
       ports:
         - "<non-default host port>:<the image's own port>"
       volumes:
         - <service>data:/<the image's data path>
       healthcheck:
         test: ["CMD-SHELL", "<the image's own readiness command>"]
         interval: 5s
         timeout: 3s
         retries: 10

   volumes:
     <service>data:
   ```

   Name the tag when you fill this in; this file names none, the same way
   `core` never writes a `pnpm` version by hand. A tag pinned into a recipe is
   a statement about the day the recipe was written, and the image's own
   release cadence outlives that day faster than the recipe gets reread.

3. **Write the connection string into the project's `CLAUDE.md` stack block**,
   using the remapped host port, alongside a one-line note that the port is
   remapped and why. A remap nobody documented is a remap somebody undoes.

## What the consumer decides

Which services, which images and tags, which host ports, whether state
survives `down` — and the answer to whether this module is wanted at all,
which is a real question for a project whose only dependency is a file on
disk.

## Traps

**Publish on a non-default host port, and carry the reason with the rule or
the rule loses.** A developer machine very likely already has a database of
the same kind listening on the default port. The failure that produces is
not a refused connection, which anyone would debug in a minute — it is a
*successful* connection to the wrong database, which presents as a data bug
for as long as it takes somebody to work out which instance they have been
talking to. A recipe that says "use a non-default port" without that sentence
gets overridden by the next person who finds the remap inconvenient.

**An image's entrypoint can start refusing a volume that worked last month,
without the data path itself changing at all.** Two tags of one database's
current major, on the same day, against the identical compose file: with the
volume mounted where every guide and every older compose file puts it, the
floating major-only tag exited `1` at first boot on an empty volume —
`there appears to be PostgreSQL data in: /var/lib/postgresql/data (unused
mount/volume)` — while a pinned major.minor tag of the same major started and
reported healthy. Inspecting both images shows why the obvious diagnosis is
wrong: they declare the **same** data directory. Nothing moved. One
entrypoint revision began rejecting a mount at the legacy path and the other
had not yet, so a tag that floats across those revisions changes the file's
behaviour while the file, the image's own configuration and every sentence
anyone would write about it stay the same. Read the image's own
documentation for where it wants the mount, and re-read it when you move the
tag. Verify item 2 below is what catches this, and only if you run it
with `-a`.

**A CI service container is reached on the image's own port, not the host
remap, and the comment saying so has to live in the workflow.** The remap
exists only to dodge a collision on a developer machine; a job's service
container has a network to itself and nothing to collide with. Every time
this is rediscovered it is rediscovered as a connection refused in CI against
a config that works locally, so the workflow template carries the
explanation next to the port rather than leaving it to be re-derived.

## Declining this module

A project whose services are all in-process declines it, and two things must
then not appear anywhere else: `backend`'s `## Verify` must not instruct
bringing a compose stack up — it verifies against whatever the project
actually runs against instead. `ci`'s workflow template must have its
`services:` block deleted — deleted, not commented out and not guarded by an
`if:`. A required job that never starts is absent from the check list rather
than pending, which reads as passing, and a guarded job that silently skips
reads the same way. Nothing else reaches into `docker/`: no other module's
script writes a file under it, so the decline is clean once those two are
handled.

## Verify

1. `docker compose -f docker/compose.yml config` exits `0` — it resolves and
   validates the file without starting anything.
2. `docker compose -f docker/compose.yml up -d` followed by
   `docker compose -f docker/compose.yml ps -a` shows every service
   `healthy`, not merely `running`. A container that is up and not yet
   accepting connections is the state that makes the next step flaky, and
   the check above would not have caught it — `config` only proves the file
   parses. Pass `-a`, and count the healthy rows against the number of
   services rather than looking for an unhealthy one: a container that
   started and exited is **absent** from the default listing, so the table
   is empty, nothing reads as unhealthy, and a check phrased as "no service
   is unhealthy" passes over a stack that is not running at all. That is
   how the tag trap above presents.
3. The published host port differs from the image's default. Check it, do
   not assume it: `docker compose -f docker/compose.yml port <service>
   <internal port>` prints the host mapping, and reading it back is what
   catches a copied block whose remap was never changed — a file that
   *says* it remaps and a file that *does* are not the same claim.
