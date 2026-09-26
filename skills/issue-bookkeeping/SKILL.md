---
name: issue-bookkeeping
description: Use when opening a pull request that should close issues, after a pull request merged without closing them, and when reconciling a finished piece of work against its tracker. Covers the closing syntax GitHub actually recognises and the counter that merges cleanly while losing data.
---

# Issue bookkeeping

A tracker drifts from the work the moment a pull request closes an issue by
the wrong syntax, merges without closing anything, or a record gets marked
done while the issues under it stay open. None of that shows up as a merge
conflict — the drift is silent — so checking the tracker against reality is a
habit to run deliberately, not a state a green pipeline confirms on its own.

## Where the tracker lives

Read `## Issue mirroring` in the project's `CLAUDE.md` — at the repository
root, or under `.claude/` if that is where this project keeps it. It names
where the source of truth lives, the id format, and the milestone if there is
one. If that heading is absent, this project does not mirror its work into
issues — say so and stop, rather than inventing a scheme it will have to live
with.

## Opening a pull request

Put a `Closes #N` line for **each** issue the pull request closes. `Closes`,
`Fixes` and `Resolves` all work, and all three fire when the pull request
merges to the default branch.

A pull request that **schedules** work rather than doing it — opening a
milestone, filing issues for later — carries no `Closes` lines at all: closing
them the moment the pull request is opened would empty the milestone before
any of the work behind it exists.

## A pull request merged without them

The completion is real. Close the issues and record which pull request did
it, rather than leaving them open for someone to notice by hand later:

```sh
gh issue close <N> --reason completed --comment "Closed by PR #<pr>."
```

## Traps

**GitHub's closing keywords parse only a bare `#N`, never a project's own id
format.** `Closes <some-card-id>` — anything that is not a literal `#`
followed by digits — reads as ordinary prose to GitHub's merge handler, not a
closing reference. The pull request merges clean, every check is green, and
the issue it was supposed to close stays open with no error or warning
anywhere in the process. The failure only surfaces later, as a milestone that
will not close, at which point every issue the pull request was meant to
close gets closed by hand, one at a time, well after the work already shipped.

**A progress counter is not a mergeable quantity.** Two lanes that each bump a
tracker line from `12 / 36` to `14 / 36` produce no conflict — both sides
wrote the identical text — and the merge silently loses two completed items
with nothing in the diff to flag it. Git has no textual collision to catch
here, because there never was one to begin with. After every merge that
touches a counter like this, recount instead of trusting the arithmetic
either side did by hand: run a `grep -c` over the checked rows and set the
counter to whatever that prints.
