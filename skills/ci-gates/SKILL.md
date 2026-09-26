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

Read `## Quality gates` in the project's `CLAUDE.md` — at the repository
root, or under `.claude/` if that is where this project keeps it. It lists
the contexts branch protection requires, spelled as branch protection spells
them. If that heading is absent from wherever `CLAUDE.md` lives, this project
has not declared its gates — say so and stop. Counting checks instead is the
failure this skill exists to prevent.

## Traps

**`gh` reports an in-progress check as `conclusion: ""`, not `null`.** jq's
`//` operator substitutes only on `false` and `null`, so a test written as
`.conclusion // "PENDING"` gets back the empty string for a check that has not
finished — not the fallback value — and every "is it still running?" test
built on that pattern reports the check as done while it is still running.
Gate on `.status != "COMPLETED"` and leave `conclusion` untested until it is.

**`gh pr merge` refuses with "base branch policy prohibits the merge" on a
pull request where every visible check is green.** A workflow that has not
started yet does not appear in `gh pr checks` at all, so an aggregate test
like `all(.bucket != "pending")` is trivially true — it is checking a list
that is simply short, not a list of checks that have all resolved. This is
not freak timing: a workflow whose `concurrency` block sets
`cancel-in-progress: false` queues consecutive pushes instead of replacing
the run already in flight, so the required context genuinely does not exist
yet. On one pull request the required context stayed absent for ten minutes
while every other check was already green. Do not trust memory for what
"every check" means — ask branch protection instead:
`gh api repos/OWNER/REPO/branches/main/protection --jq
'.required_status_checks.contexts'`, then require each named context to
*exist* in `gh pr checks` and be non-pending, and break on any failure bucket
so a crash reads as a crash, not as silence.

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

**"Use a monitor" with no tool named is not a remedy — a stranger reading it
keeps their loop.** The maintainer stopped two subagents mid-run on
2026-09-14 for exactly this habit: every tick of a sleep-and-poll loop costs
a tool call and lands its output in context whether anything changed or not,
so the session that is supposed to be watching burns the budget it needs to
report the result and is the last one to report back — even when its work
finished first. From a shell, `gh run watch --exit-status` blocks until the
run finishes and fails if the run failed. In this harness, the `Monitor` tool
gives one notification per check as it settles, and `Bash` with
`run_in_background` plus an `until` loop gives one notification when the
whole wait is done. Whichever one is used, cover every terminal state —
failure, cancelled, timed out — not just success, or a crash reads as
still-running.

**`docker build … || echo FAILED` exits `0` no matter which branch ran.** A
shell pipeline's exit status is the status of the last command executed —
`echo`, not `docker build` — so a failed build is swallowed and the script
reports success. The next `compose up` then finds no new image to pick up and
silently starts the previous one, so a broken build never becomes a visibly
broken deploy. Verify the artefact itself — the image's presence and its
build timestamp — never the exit code of the command that built it.
