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
report and a screenshot per combination. It carries no built-in route or
persona list: `AUDIT_CORE`, `AUDIT_ALL` and `AUDIT_PERSONAS` are required,
each read from `## Audit routes` / `## Audit personas`, and the driver fails
fast if any is unset rather than falling back to a guessed one.

```sh
AUDIT_CORE="<the surfaces a real user meets constantly, from ## Audit routes>" \
AUDIT_ALL="<every route worth one pass, from ## Audit routes>" \
AUDIT_PERSONAS="<the persona names, from ## Audit personas>" \
node driver.mjs sweep    # matrix sweep + accessibility scan
```

`states` reads the same three variables and forces the error / empty / slow
states in `main()`.

## The sign-in path is isolated in one file

Authentication is the one part of the driver genuinely shaped by the product
it audits, so it lives entirely in [auth-adapter.mjs](auth-adapter.mjs): the
personas map, the sign-in route, the session cookie name, the locale cookie
name, the bearer-token localStorage key, the auth-route pattern the `states`
mode must not mock, and the cached-token probe endpoint. A project with a
different auth flow rewrites that one file — `signIn(base, persona,
password)` returning `{ token, cookie }`, `cookieNames()` returning
`{ session, locale }`, `bearerStorageKey()` returning a string, and
`isAuthRoute(url)` returning a boolean — and touches nothing in
`driver.mjs`.

A run caches each persona's minted token to disk next to `auth-adapter.mjs`,
one file per persona-and-target-host pair (`.auth-<persona>-<host>.json`),
so a sweep across many pages doesn't spend the sign-in rate limit on
plumbing. That file holds a live bearer token and session cookie — treat it
as a credential, not as build output; it is git-ignored, not cleaned up.

## What the driver still assumes

Past the routes and personas above, and past the sign-in path now isolated
in the adapter, the driver still carries assumptions from the product it was
first written against:

- Two fixed locales, `ru` and `en`.
- An `/api/v1/` API prefix.
- Two endpoints, `/admin/has-users` and `/admin/instance`, named explicitly
  so the `states` mode's mock does not fake them.
- An `{ items, total }` response envelope for the empty-payload state.
- A fixed 600ms settle wait after navigation, before probing the page.
- `AUDIT_COLOR_MODE_KEY` defaults to `color-mode`, and the theme-detection
  probe reads `data-theme` or a `dark` class — both assume one theming
  convention.

A project shaped differently in any of these needs to edit the driver
itself; declaring `## Audit routes` / `## Audit personas` does not reach
them.

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
