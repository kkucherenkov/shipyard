// Auth adapter for the release-audit driver.
//
// This file is the only project-specific part of the driver: the personas
// map, the sign-in route, the session and locale cookie names, the
// bearer-token localStorage key, the auth-route pattern the `states` mode
// must not mock, and the cached-token probe endpoint all live here. A
// project with a different auth stack rewrites this one file and leaves
// driver.mjs untouched.
//
// Contract the driver relies on:
//   signIn(base, persona, password) -> { token, cookie }
//     token  — the bearer token the target app's client reads out of
//              localStorage, under the key bearerStorageKey() names. Never
//              undefined: signIn throws rather than hand back a session
//              that didn't actually authenticate.
//     cookie — the session cookie's value (decoded), or null if the target
//              app never sets one. The driver seeds it under
//              cookieNames().session.
//   cookieNames() -> { session, locale }
//     session — the cookie name the driver writes `cookie` under.
//     locale  — the cookie name the driver writes the sweep's locale under.
//   bearerStorageKey() -> the localStorage key the driver writes `token` under.
//   isAuthRoute(url) -> true if `url` is part of the sign-in flow. The
//     driver's `states` mode must let these through unmocked — faking auth
//     logs the audit out, which is the zero-findings failure this whole
//     method exists to catch.
import { readFile, writeFile } from 'node:fs/promises';

// audit-*@example.com are the seeded personas this project's setup creates;
// PERSONA_NAMES (declared in the project's CLAUDE.md, read by driver.mjs)
// must list the same keys as this map — nothing here checks that they agree.
const PERSONAS = {
  admin: 'audit-admin@example.com',
  learner: 'audit-learner@example.com',
  empty: 'audit-empty@example.com',
};

export function cookieNames() {
  return { session: 'better-auth.session_token', locale: 'i18n_locale' };
}

// The key the target app's client reads its bearer token from. `cs.` is
// this source product's own storage prefix — a different app almost
// certainly uses an unrelated key, not just a different prefix.
export function bearerStorageKey() {
  return 'cs.web.bearer';
}

export function isAuthRoute(url) {
  return url.includes('/api/v1/auth/');
}

// A run's minted tokens are cached to disk so a sweep across many pages
// doesn't burn the sign-in rate limit on plumbing (see the 429 handling
// below). Keyed on persona *and* the target host: two different projects
// audited from one checkout of this plugin (or the same project on two
// ports) must not share a cache file, or a rate-limited probe below can
// hand one project's session to the other. `import.meta.dirname`, not
// `new URL(...).pathname`, because the latter percent-encodes — an install
// path containing a space would otherwise write to a `%20` path that
// doesn't exist and fail the run after a successful sign-in.
function cacheFileFor(base, persona) {
  const host = new URL(base).host.replace(/:/g, '_');
  return `${import.meta.dirname}/.auth-${persona}-${host}.json`;
}

export async function signIn(base, persona, password) {
  const email = PERSONAS[persona];
  if (!email) throw new Error(`signIn: unknown persona "${persona}"`);
  const cacheFile = cacheFileFor(base, persona);
  try {
    const c = JSON.parse(await readFile(cacheFile, 'utf8'));
    const probe = await fetch(`${base}/api/v1/courses`, {
      headers: { Authorization: `Bearer ${c.token}` },
    });
    // 429 means "too many requests", not "bad token" — the general throttler
    // (60/min) fires during a sweep and would otherwise send us to sign-in,
    // which has its own, stricter limiter. Safe to trust here because the
    // cache file is already scoped to this base: it cannot hand back another
    // project's token.
    if (probe.ok || probe.status === 429) return c;
  } catch {
    /* no cache */
  }
  const res = await fetch(`${base}/api/v1/auth/sign-in/email`, {
    method: 'POST',
    // Better Auth rejects a request whose Origin is absent-but-browser-shaped
    // (undici sends Sec-Fetch-* without Origin) with MISSING_OR_NULL_ORIGIN.
    // curl sends neither and is let through as a non-browser client.
    headers: { 'Content-Type': 'application/json', Origin: base },
    body: JSON.stringify({ email, password }),
  });
  if (!res.ok)
    throw new Error(`sign-in(${persona}) HTTP ${res.status}: ${(await res.text()).slice(0, 160)}`);
  const body = await res.json();
  const { token } = body;
  // A 200 with no usable token is worse than an HTTP error: nothing stops it
  // being cached and seeded into the browser, and the sweep then "audits" an
  // unauthenticated session and reports near-zero findings. Refuse to guess
  // that a missing field is fine.
  if (!token) {
    throw new Error(
      `sign-in(${persona}) HTTP ${res.status} but no token in the response body: ` +
        `${JSON.stringify(body).slice(0, 160)}`,
    );
  }
  const { session } = cookieNames();
  const raw = res.headers.getSetCookie?.().find((c) => c.startsWith(`${session}=`));
  const cookie = raw ? decodeURIComponent(raw.split(';')[0].split('=').slice(1).join('=')) : null;
  const out = { token, cookie };
  await writeFile(cacheFile, JSON.stringify(out), { mode: 0o600 });
  return out;
}
