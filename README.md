# shipyard

Six Claude Code skills and one command, carrying the process discipline a
real project learned the hard way: keeping a task stack, running parallel
agent lanes without them colliding, telling a genuinely green pull request
from one that only looks green, keeping an issue tracker in sync with what
shipped, putting a release on a host and proving it took effect, and
auditing a product before cutting a release. Install it once; a later fix to
any of these reaches every project that installed it through `/plugin
update`, instead of a copy someone has to remember to paste around.

This is layer 1 of two. Layer 2 is a stack preset — it will ship as a
separate plugin, `shipyard-monorepo`, for a project shaped like a monorepo
regardless of which language its modules are written in — and it does not
exist yet. This plugin runs standalone until it does.

## What this does not do

- **No stack.** No framework choice, no package manager, no lockfile, no
  linter config. Those belong to layer 2, which has not been built.
- **No scaffolding.** A plugin can put `skills/`, `agents/` and `commands/`
  into a Claude Code session; it cannot put `CLAUDE.md`, `specs/tasks/`, or a
  CI workflow into your repository — those are per-repository files, not
  session behaviour. That is [`project-skeleton`](https://github.com/kkucherenkov/project-skeleton),
  a separate GitHub template, and the worked example below starts from it.
- **No opinions about a framework.** Every skill here reads its project
  facts from named headings in your own `CLAUDE.md`, listed below, rather
  than assuming one.
- **No agents.** The agents that existed alongside these skills in the
  repository they were extracted from were each bound to one stack — one
  framework for a backend, a different one for a frontend. An agent without
  its stack produces confident work in the wrong idiom, so none of them
  travel here; they belong to a stack layer, not this one.
- **No guessing.** A skill that needs a `CLAUDE.md` heading and does not
  find it says so and stops, rather than falling back to a default that
  deploys, audits, or bookkeeps nothing and reports success.

## Install and update

```
/plugin marketplace add kkucherenkov/shipyard
/plugin install shipyard
```

If the project is a fresh clone of `project-skeleton`, run `/bootstrap` once,
immediately after — see the worked example below.

To pick up a later fix to any skill:

```
/plugin update shipyard
```

## Skills, and when each one fires

A skill's `description` is what Claude reads to decide whether to load it —
a person deciding whether to *install* this plugin never sees that. Here is
the same information addressed to a person: one line per skill, the moment
it is meant to fire.

| Skill | Fires when |
| --- | --- |
| `task-stack` | Before starting any task bigger than a one-line fix, when a task is blocked, and when one ships. |
| `lane-discipline` | Before dispatching two or more agents to work in parallel, and when a lane's work has already collided with another's. |
| `ci-gates` | When a pull request looks green but will not merge, when a required check is missing rather than failing, and before trusting any script that decides whether CI has finished. |
| `issue-bookkeeping` | When opening a pull request that should close issues, after one merged without closing them, and when reconciling finished work against its tracker. |
| `deploy-verify` | When putting a released version on a host, rolling one back, or answering which version a host is actually running. |
| `release-audit` | Before cutting a release, after a wave of interface fixes to measure whether they moved anything, and when a user-experience review is requested. |

### The `/bootstrap` command

Not a skill — a command. Run it once, right after `/plugin install
shipyard`, against a freshly cloned `project-skeleton` repository, before any
other work. It fills the template's placeholders, settles the four optional
contract sections below (adding the ones you choose with real facts in them,
deleting the rest outright), replaces the license holder, writes the first
ADR, and opens the first task entry.

## The contract with the other layer

Four of the six skills above read a fact out of the project's own
`CLAUDE.md` instead of carrying one of their own or guessing. Every one of
them says so and stops if the heading it needs is missing, rather than
proceeding against a default that does nothing and reports success.

| Heading | Read by | Required? |
| --- | --- | --- |
| `## Quality gates` | `ci-gates` | Yes. |
| `## Deploy targets` | `deploy-verify` | Optional. |
| `## Issue mirroring` | `issue-bookkeeping` | Optional. |
| `## Audit personas` and `## Audit routes` | `release-audit` | Optional, read together — either one missing stops it. |

A fifth, `task-stack`, reads two directories instead of a heading —
`specs/tasks/active/` and `specs/tasks/done/` — and stops the same way if
neither exists. The sixth, `lane-discipline`, reads nothing from the project
at all; it governs how a session dispatches other agents, not a project
fact.

**As shipped today, `project-skeleton`'s `CLAUDE.md` carries only `##
Quality gates`.** The other four headings are not present as empty sections
waiting to be filled in — an empty section reads, to a skill, exactly like a
filled one that has nothing to report, which is the one distinction these
skills are built never to blur. `/bootstrap` is what adds a chosen section
with real facts in it, or deletes an unchosen one outright; nothing ships
those four sections in advance.

`release-audit`'s driver carries a narrower kind of assumption of its own.
Past the routes and personas that `## Audit personas` / `## Audit routes`
supply, it still assumes things about the product it audits — two fixed
locales, an API path prefix, a specific empty-response shape, among others.
Read ["What the driver still
assumes"](skills/release-audit/SKILL.md#what-the-driver-still-assumes)
before pointing it at a project shaped differently in any of those ways.
`skills/release-audit/auth-adapter.mjs` is the one file a different sign-in
flow requires rewriting, and it is already isolated for exactly that reason.

## From an empty directory to a first commit

```sh
gh repo create my-project --template kkucherenkov/project-skeleton --private --clone
cd my-project
```

Then, in a Claude Code session opened in that directory:

```
/plugin marketplace add kkucherenkov/shipyard
/plugin install shipyard
/bootstrap
```

`/bootstrap` asks four questions — the project's name and a one-line
description, which language the conversation happens in, which stack (if
any) it builds on, and which of the four optional contract sections apply —
then, without asking anything further, fills every placeholder the template
shipped with, replaces the license holder (defaulting to `git config
user.name`), writes the first ADR, and opens the first task entry, left
in-progress for whoever lands the work it describes. Commit what it
produced:

```sh
git add -A
git commit -m "chore: bootstrap from project-skeleton"
git push -u origin main
```

## License

MIT — see [`LICENSE`](LICENSE).
