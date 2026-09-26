---
name: ci-gates
description: Use when a pull request looks green but will not merge, when a required check is missing rather than failing, and before trusting any script that decides whether CI has finished. Covers how GitHub reports pending and blocked runs, and the ways a check that never ran reads as a check that passed.
---

# CI gates

A status check has more states than pass and fail: it can be running, queued,
blocked on a human, or simply absent from the list because it has not been
scheduled yet. A script — or a person skimming a PR page — that only tells
red from green collapses all of those into "not red", and "not red" is not
the same claim as "passed". Every trap below is a script or a habit that made
that collapse and got a wrong answer that looked like a right one.

## Which checks matter

Read `## Quality gates` in `.claude/CLAUDE.md`. It lists the contexts branch
protection requires, spelled as branch protection spells them. If that heading
is absent, this project has not declared its gates — say so and stop. Counting
checks instead is the failure this skill exists to prevent.

## Traps

**`gh` reports an in-progress check as `conclusion: ""`, not `null`.** jq's
`//` operator substitutes only on `false` and `null`, so a test written as
`.conclusion // "PENDING"` gets back the empty string for a check that has not
finished — not the fallback value — and every "is it still running?" test
built on that pattern reports the check as done while it is still running.
Gate on `.status != "COMPLETED"` and leave `conclusion` untested until it is.

**A required check that has not started yet does not appear in the check list
at all — it is absent, not pending.** A script that counts how many checks it
can see and calls the pull request green once that count looks complete never
notices the one context branch protection requires that GitHub has not even
queued, because there is nothing in the list to count. Gate on the exact
context names branch protection requires, read from `## Quality gates`, and
treat a required name missing from the list as unresolved — never as passed.

**A push made as a bot account with the default workflow token does not
retrigger checks.** GitHub deliberately declines to fire `on: push` workflows
for a commit pushed by `github-actions[bot]` using `GITHUB_TOKEN` — otherwise
a workflow that pushes its own commit would retrigger itself forever. A pull
request updated this way keeps showing the previous run's result, so a check
that is still red after the fix reads as a slow queue instead of what it
actually is: a check that never ran against the new commit at all.

**A branch carrying that bot commit puts every later workflow run into
`action_required`.** Those runs never start on their own, and they do not
appear in the pull request's check list either — not pending, not queued,
simply missing — so the state reads as "the checks have not started yet"
rather than "the checks are blocked on a human". Five runs sat waiting
fifteen minutes before this was spotted and approved by hand. Find them with
`gh run list --branch <branch> --json databaseId,conclusion`, looking for
`conclusion: action_required`, then approve each with
`gh api -X POST repos/:owner/:repo/actions/runs/<id>/approve`.

**`for id in $ids` under a shell that does not word-split unquoted variables
iterates once, over the whole string, not once per id.** It approved one of
five pending runs while the loop's own output scrolled by looking like it had
walked all five — the command still exits `0`, so nothing about the loop's
own result signals the miss. Use
`printf '%s\n' "$ids" | while read -r id; do ...; done` instead, which reads
one id per line regardless of which shell is running it.

**Waiting on CI with a sleep-and-poll loop spends the very context it needs
to report the result.** Each iteration's output piles up in the session that
is supposed to be watching, so by the time the checks actually finish, that
session has burned its budget narrating its own polling and is the last one
to report back — even when its work finished first. Use a blocking wait or a
monitoring tool built for watching a run, never a loop written by hand.

**`docker build … || echo FAILED` exits `0` no matter which branch ran.** A
shell pipeline's exit status is the status of the last command executed —
`echo`, not `docker build` — so a failed build is swallowed and the script
reports success. The next `compose up` then finds no new image to pick up and
silently starts the previous one, so a broken build never becomes a visibly
broken deploy. Verify the artefact itself — the image's presence and its
build timestamp — never the exit code of the command that built it.
