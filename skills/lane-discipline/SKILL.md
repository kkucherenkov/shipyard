---
name: lane-discipline
description: Use before dispatching two or more agents to work in parallel, and when a lane's work has collided with another's. Covers what a lane's brief must contain, how to divide work by files rather than by findings, and the two failure modes that cost the most to unpick.
---

# Lane discipline

Two or more agents working on the same change at the same time are two or
more lanes. A lane is not a role or a slice of the task description — it is
a worktree, a branch, and a pull request that no other lane touches while it
is open.

## One lane, one everything

One lane is one worktree, one branch, one pull request. Lanes never share a
branch: two agents committing to the same branch race each other's commits,
and there is no merge step to catch the collision, because there was never a
merge to begin with — just two writers on one ref.

## Divide by files, not by findings

Split work by which files each lane touches, not by which findings or
subtasks the lanes are chasing. A brief that hands two findings in the same
file to two different lanes has created a collision it never named: both
lanes edit that file, and whichever pull request lands second inherits a
conflict the brief gave no instruction for resolving.

## What a lane's brief must say before it starts

A lane that has to ask a question mid-flight is a lane that has already
stopped. Settle all of this before dispatching, not after the first question
comes back:

- **The paths it owns, and the paths other lanes own.** Name them — "stay in
  your area" is not a boundary. A wave on 2026-09-18 lost time to two lanes
  both editing a component that sat between the two files each brief did
  name; neither brief was wrong about its own file, and neither mentioned the
  one in between.
- **That a file two lanes both need belongs to exactly one of them.** The
  others wait for that lane's pull request to land before they touch it,
  rather than editing their own copy of the same file in parallel.
- **What the lane must NOT do.** Reach for a label instead of fixing a gate,
  change server-side semantics from a client-side lane, or write to a shared
  notes store or tracker — that stays with whoever is coordinating the wave,
  centrally, or five lanes edit the same note at once and the last write
  silently wins.
- **How it is expected to wait on CI.** A real monitoring mechanism — a
  blocking wait, a webhook, a tool built for watching a run — never a
  sleep-and-poll loop. A poll loop spends the lane's own context reading its
  own polling output, and because it is busy polling, it is the last lane to
  report back even when its work finished first.

## Traps

**A subagent dispatched without its own worktree runs git in your working
copy, on your branch.** Told to "work on a new branch," it may commit to
yours instead, because nothing about a plain dispatch actually separates the
two checkouts — on 2026-09-18 that put ten unrelated changes on a local
`main` before anyone noticed. Dispatch every lane into an explicit worktree
(`git worktree add <path> <branch>`, or whatever your orchestrator calls the
equivalent) rather than trusting an instruction to "use a new branch," and
after any agent reports back, run `git log --oneline -1` on your own branch
to confirm nothing landed there that should not have.

**A lane that brings up a container stack without giving it its own project
name or namespace adopts whatever stack is already running and rewrites that
stack's services out from under it.** A lane did exactly this on 2026-09-18:
the shared dev stack happened to be down at the moment the lane ran, so the
only visible damage was the running stack silently taking on the lane's
name — the same sequence with the stack already up would have redeployed
someone else's containers with the lane's config instead. Give every lane
its own project name before it brings anything up (for Docker Compose,
`docker compose -p <lane-slug> up` or `COMPOSE_PROJECT_NAME=<lane-slug>`; the
equivalent isolation flag for another orchestrator), and check that nothing
is already running under the name a lane is about to claim.
