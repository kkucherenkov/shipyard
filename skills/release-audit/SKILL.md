---
name: release-audit
description: Use before cutting a release, after a wave of interface fixes to measure whether they moved anything, and when a user-experience review is requested. Covers standing the product up on production-shaped data, the two-assessment critique, and why a run that reports nothing is the failure mode.
---

# Release audit

Two passes over a running instance restored from production-shaped data: an
exploratory browser sweep that reports what is broken, then a design critique
that scores the product. Compare the score against the previous run.

## The environment is the whole game

Restore a production-shaped dump into a local stack. Not the seed: seeded
data produces short titles and small objects, and every bug this method has
caught lived in the gap between that and reality — a non-Latin title that
deleted a record, a 4203-character description with nowhere to go, 1945
items filed under an unknown language.

The live production system is the other wrong answer: half the interesting
scenarios are destructive and cannot run against real data.

## Audit the release images, not a development server

A dev server differs from what users get in exactly the places that matter:
the content security policy, minification, and the rendered document. See
[setup.md](setup.md) for the restore-and-build procedure.

## Two assessments, kept strictly apart

An exploratory sweep that reports what is broken, and a design critique that
scores. Nielsen's ten heuristics, 0-4 each. **Most real interfaces land
20-32 of 40.**

## What this project audits

Read `## Audit personas` and `## Audit routes` in the project's `CLAUDE.md`
— at the repository root, or under `.claude/` if that is where this project
keeps it. If either heading is absent, this project has not described its
own surface — say so and stop. Auditing a guessed route list produces a
report whose gaps are invisible.

## Running it

[driver.mjs](driver.mjs) is the harness. It asserts nothing — it writes a
report and a screenshot per combination.

```sh
node driver.mjs sweep    # matrix sweep + accessibility scan
node driver.mjs states   # forced error / empty / slow states
```

## Traps

**A run that reports zero findings is the failure mode, not the result.**
The first sweep of this method reported "56 pages, 0 violations" while every
page was the sign-in redirect. Make the harness refuse to continue when
authentication did not take, and look at a screenshot before believing a
clean result.

**Sign-in is rate-limited twice over.** A harness that signs in per run
burns the allowance on plumbing: mint once, cache to disk, reuse. The token
probe must treat a rate-limit response as **valid**, not as an expired
token, or the run drives itself into the stricter limiter.

**Filling a sign-in form does not work against a client that hydrates after
the network settles.** It replaces the inputs and discards the fill
silently. Authenticate over the API and seed the credentials.

**A visibility probe that checks the element misses ancestors.** Walk up
the tree. A clip probe flags the visually-hidden heading pattern, too:
`position:absolute; width:1px; clip-path:inset(50%)` is indistinguishable
from a clipped element by geometry alone. Check the class before filing.

**Faking every API response also fakes the endpoints that decide whether
the instance is initialised.** That funnels every route into a first-run
wizard — a different screen than the one under audit. Exclude auth and
instance-config routes from the mock.

## Reading the result

**Normalise before comparing runs.** Raw counts mislead: a wider matrix
produces more of everything, and rate-limit noise dominates both
numerators.

**One rule violation is usually one element.** A run reported 98 violations
of one rule; they were a single unlabelled button multiplied by 128 matrix
combinations. Group by rule, find the element, then size the work.

**Expect the fixes to break things.** The first fix wave moved a score from
18 to 22 and introduced three new inconsistencies, one of which made a
previously inert setting actively contradictory. Audit the fixes, not just
the original findings.

## What this misses

Say what the audit systematically misses — interaction, long operations,
the media player's native chrome, keyboard-only navigation, zoom, reduced
motion, forced colours — rather than implying coverage you do not have.
