---
name: bootstrap
description: Fill a freshly created project-skeleton repository — its placeholders, its contract sections, and its first ADR.
---

# Bootstrap a new project

`project-skeleton` ships a contract with blanks in it. The six skills in this
plugin read named headings out of a project's `CLAUDE.md` and refuse to guess
when a heading they need is missing. This command is the one pass that turns
the template's placeholders and optional headings into that contract — run it
once, right after `/plugin install shipyard`, before any other work.

## 1. Refuse if this repository is already bootstrapped

Find the project's `CLAUDE.md` — the skeleton ships it at `.claude/CLAUDE.md`;
if it has since moved to the repository root, read it there instead. If
neither copy contains a `<PROJECT>` placeholder, stop and say why, then do
nothing else: this repository has already been through `/bootstrap`, and
running the rest of this command would overwrite hand edits made since — a
`## Deploy targets` section someone filled in, a contract heading someone
deleted on purpose, a rewritten `## Never do` list.

## 2. Ask about four things, and no more

1. The project's name, and a one-line description to go with it (one
   exchange, not two — "what's it called, and what is it in one line").
2. The language conversation with the maintainer happens in.
3. Which stack this project builds on, or none.
4. Which of the optional contract sections apply: deploy targets, issue
   mirroring, and audit personas/routes. One yes/no per section, asked
   together, not as three separate questions — and a yes to any of them
   continues into gathering the specifics step 7 needs; it does not close
   the topic on its own.

Each of the four is pursued to whatever depth its own answer needs — a "yes"
in question 4 is that question opening, not that question finished, so the
host, container names and health endpoint `## Deploy targets` needs are
question 4 continued, not a fifth question. The license holder in step 8 is
the same idea applied to question 1: it defaults to `git config user.name`
and is only asked for when that is empty, as project identity continued, not
a new topic. What this command must not do is introduce a topic the four
above don't cover — a testing framework, a naming convention, a release
schedule. Two things it does not ask about at all: today's date and the task
id in step 10, both derived without asking anyone.

## 3. Delete `scripts/smoke-test.sh`, before touching placeholders

Delete it now, before the placeholder grep in the next step, not after it.
The file asserts against the published template's own placeholders and file
layout, so `<PROJECT>`, `<LANG>`, `<SUMMARY>` and `<DATE>` appear inside it as
the test's own assertion data. Left in place, it is a hit the next step's
grep can never clear: every real placeholder in the project can be filled and
the grep still comes back non-empty, from this file alone, so a rule against
reasoning past that grep's output would block on a file that isn't part of
the project it's checking. `project-skeleton`'s own `README.md` orders its
manual bootstrap checklist the same way, for the same reason: this file
exists to test the template, not this project, and it starts failing against
this project the moment the project's placeholders are its own.

## 4. Delete `project-skeleton`'s own README preamble

`README.md` opens with a note block: "This is `project-skeleton`'s own
README. If you created this repository from the template, delete everything
above the horizontal rule below." Do that deletion now — everything from the
top of the file through the `---` line, inclusive — before the next step
fills `<PROJECT>` and `<SUMMARY>` in below it. Nothing else in this command
removes that note, and nothing in the note's own checklist does either: its
three items are the smoke test (step 3, already done), the placeholder grep
(next step), and the license (step 8) — deleting the note that introduces
them is the one item the checklist names before all three, and it is the one
this command must do itself rather than leave to the reader. Skipped, a real
clone ends up with the template's own README glued on top of the project's,
and nothing downstream — not this command, not the commit instructions in
this plugin's own `README.md` — ever removes it.

## 5. Replace every placeholder

Run `grep -rn '<[A-Z_]\+>' . --exclude-dir=.git` and replace every hit it
reports — treat the grep as the source of truth for what needs filling, not
the list below, since a later version of the skeleton can add more:

- `<PROJECT>` — the name from question 1, in `CLAUDE.md` and `README.md`. The
  same spelling is also the `tuxedo` project key, the `dnote` book, and the
  project's folder in whatever notes vault the maintainer uses — one
  identifier several tools query by, so keep it identical everywhere.
- `<LANG>` — the language from question 2, in `CLAUDE.md`.
- `<SUMMARY>` — the one-line description from question 1, in `README.md`.
- `<DATE>` — today's date, in `docs/adr/0001-record-architecture-decisions.md`.
  Fill it without asking; nobody needs to be consulted about what day it is.

The grep should come back empty once every one of these is placed — it will,
now that step 3 has already removed the one file that would otherwise keep
matching on its own account. If it does not come back empty, stop and look
again rather than reporting success: a placeholder that survives is a section
someone will silently ship unfilled.

## 6. Settle the stack

If question 3 named a stack plugin, install it and let its own setup fill the
block between `<!-- STACK:BEGIN -->` and `<!-- STACK:END -->` in `CLAUDE.md` —
that block belongs to the stack layer, not to this command, and this command
must not write inside it. If the answer was none, leave the two marker lines
exactly as they are. An empty block between them is not a broken template; it
is a project that has not picked a stack yet, which is a legitimate, complete
state — unlike the optional sections in the next step, nothing reads this
block on its own, so there is nothing for an empty block to be mistaken for.

## 7. Settle the four optional contract sections — delete, never empty

The headings are `## Deploy targets` (read by `deploy-verify`), `## Issue
mirroring` (read by `issue-bookkeeping`), and `## Audit personas` with
`## Audit routes` (both read by `release-audit`, which stops if either one is
missing — treat this pair as **one** yes/no, not two, since a project that
answers yes to one and no to the other ends up with `release-audit` stopping
anyway, only later and less clearly than if it had never seen the pair).

**If the answer is yes:** collect the facts the section exists to hold — this
is question 4 continued, not a new question, per step 2 — then write the
heading with those facts in it.

- `## Deploy targets` needs the host, the container names, the image
  registry, the health endpoint, and the stack's own compose project name.
- `## Issue mirroring` needs the tracker's location, its id format, and its
  milestone if it has one.
- `## Audit personas` / `## Audit routes` need the accounts the audit signs in
  as, and the routes it walks.

If `CLAUDE.md` does not already carry that heading, add it after
`<!-- STACK:END -->`, in this order: Deploy targets, Issue mirroring, Audit
personas, Audit routes. If it already carries the heading with placeholder
text, replace the placeholder with the real facts.

**If the answer is no: delete the heading and everything under it, down to
the next `##` heading or the end of the file.** Do not leave the heading
behind with an empty line under it. Do not leave it with "N/A", "not
applicable", "TBD", or any other placeholder under it. Do not leave it and
plan to fill it in later. A `## Deploy targets` heading followed by nothing
looks, to a human skimming the file, like an oversight to fix — but the
skill reading it cannot tell "this project chose not to deploy anywhere" from
"the maintainer has not gotten to this yet", so it would run its deploy
procedure against nothing and report success, having deployed nothing to
nowhere. Deleting the heading outright is the only state that reads as "not
applicable" to both a human and the skill: an absent heading is exactly what
each skill's "if that heading is absent, say so and stop" is written to
detect. Leaving it present in any empty form defeats that check before it
ever runs.

Do not guess yes to make the file look more complete than the project
actually is, and do not guess no to finish the interview faster. A section
answered yes that nothing has actually configured is worse than an absent
one, because it invites a skill to trust data that is not really there.

## 8. Replace the license

Replace the copyright line in `LICENSE` with this project's owner — default to
`git config user.name`, and ask only if that comes back empty, per step 2.
The rest of the file, including its MIT terms, does not change.

## 9. Write the first ADR

Add `docs/adr/0002-<slug>.md` in the same shape as
`docs/adr/0001-record-architecture-decisions.md` — Status, Date, Context,
Decision, Consequences. Its subject is the stack answer from question 3,
which is already the first architecturally significant decision this project
has made: if a stack was named, the decision is that stack over deferring the
choice; if the answer was none, the decision is starting with no stack at
all, deferred on purpose rather than picked to have an answer. Do not invent
a different decision to fill this file — the project has not made one yet,
and writing a made-up rationale for something nobody decided is worse than a
short, honest ADR about the one real decision on the table.

## 10. Open the first task entry

Create `specs/tasks/active/T-<today>-bootstrap-project.md` from
`specs/tasks/templates/feature.md`. Goal: turning this clone of
`project-skeleton` into this project's own contract. Sub-steps: mirror steps
3-9 above. Leave `Status: in-progress` — do not move it to `done/` here, since
that step also records a pull request link, and this command does not open
one; leave the move to whoever lands this work.
