---
name: task-stack
description: Use before starting any task larger than a one-line fix, when a task is blocked, and when one ships. Covers the one-file-per-task layout, the id format and why it is a branch slug rather than a counter, and what moving an entry to done must record.
---

# Task stack

The task stack is the only durable record of what is in flight, what is
blocked, and what has already shipped. It is two directories, one file per
entry: `active/` for work in flight, one file per task named after its id, and
`done/` for the archive — the same file, moved there with `git mv` once a task
ships or is cancelled. There is no index file and nothing to regenerate:
listing `active/` is the stack, and reading its files is the state.

## Where the stack lives

`specs/tasks/active/` and `specs/tasks/done/`, relative to the repository root.
If neither exists, this project does not use a task stack — say so and stop
rather than creating one unasked. The directories arrive with
`project-skeleton`; adding them to an existing project is a decision for the
maintainer, not a side effect of reading a task.

## Why one file per entry

The obvious layout is two files, `active.md` and `done.md`, each an
append-at-the-top list. Every lane then writes at the top of the same file, so
every lane after the first hits a conflict there — in a file whose entries
never actually overlap.

A custom merge driver (`merge=taskstack`) resolves that locally and works. It
cannot help where the cost actually lands: **GitHub does not run custom merge
drivers.** It computes mergeability with a plain three-way merge, so the PR
page says CONFLICTING regardless, the lane has to rebase, the force-push
restarts the whole CI run, and a green PR goes back through the full check
suite to absorb a bookkeeping line.

Separate files cannot conflict — locally or on GitHub. Finishing a task is a
rename, which git tracks by itself, so the "the other lane already moved this
entry to done" case that the driver needed special code for cannot arise.

## Rules

1. **Before touching code**, create `active/<id>.md` from
   `specs/tasks/templates/feature.md`; if that template is absent, write the
   entry directly rather than treating the absence as a broken setup.

2. **While working**, tick sub-steps in place. If the task is blocked, set
   `Status: blocked` and fill `Blockers:`.

3. **When shipped**, `git mv specs/tasks/active/<id>.md specs/tasks/done/`,
   set `Status: done`, and add `- Completed: YYYY-MM-DD` and
   `- Result: <PR link>`. The entry must reference the spec it implemented so
   the audit trail survives.

4. **Never delete** a file from `done/`. A cancelled task moves there with
   `- Result: cancelled — <reason>`.

5. **Stack depth** — `active/` should rarely hold more than three files. If it
   does, something is being left half-done. Close or cancel before opening the
   next.

## Task ID format

`T-YYYY-MM-DD-<branch-slug>` — the date the entry was created, then the task's
own branch with its Conventional-Commits type prefix dropped and `/` replaced
by `-`:

| Branch                    | Id                                  |
| ------------------------- | ----------------------------------- |
| `fix/dark-theme-contrast` | `T-2026-01-15-dark-theme-contrast`  |
| `feat/export-to-markdown` | `T-2026-01-15-export-to-markdown`   |
| `chore/bump-node-22`      | `T-2026-01-15-bump-node-22`         |

**Do not allocate a number.** A counter of the form `T-YYYY-MM-DD-NNN` has no
allocator: a lane picks the next free number by reading what exists, so two
lanes working at the same time read the same state and pick the same number.
A branch slug needs no allocator because the uniqueness already exists further
up — two lanes cannot share a branch.

The filename is the id, so a collision is not a merge conflict; it is two lanes
trying to create the same path, which git refuses outright.
