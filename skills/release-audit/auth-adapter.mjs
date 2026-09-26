// Auth adapter for the release-audit driver.
//
// This file is the only project-specific part of the driver: the personas
// map, the sign-in route, the session and locale cookie names, the
// bearer-token localStorage key, and the cached-token probe endpoint all
// live here. A project with a different auth stack rewrites this one file
// and leaves driver.mjs untouched.
//
// Contract the driver relies on:
//   signIn(base, persona, password) -> { token, cookie }
//     token  — the bearer token the target app's client reads out of
//              localStorage, under the key bearerStorageKey() names.
//     cookie — the session cookie's value (decoded), or null if the target
//              app never sets one. The driver seeds it under
//              cookieNames().session.
//   cookieNames() -> { session, locale }
//     session — the cookie name the driver writes `cookie` under.
//     locale  — the cookie name the driver writes the sweep's locale under.
//   bearerStorageKey() -> the localStorage key the driver writes `token` under.
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

export async function signIn(base, persona, password) {
  const email = PERSONAS[persona];
  if (!email) throw new Error(`signIn: unknown persona "${persona}"`);
  // Cached next to this file rather than under the run's AUDIT_OUT, so an
  // output-directory override doesn't orphan the cache and two sweeps
  // against the same base still share one token.
  const cacheFile = new URL(`.auth-${persona}.json`, import.meta.url).pathname;
  try {
    const c = JSON.parse(await readFile(cacheFile, 'utf8'));
    const probe = await fetch(`${base}/api/v1/courses`, {
      headers: { Authorization: `Bearer ${c.token}` },
    });
    // 429 means "too many requests", not "bad token" — the general throttler
    // (60/min) fires during a sweep and would otherwise send us to sign-in,
    // which has its own, stricter limiter.
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
  const { token } = await res.json();
  const { session } = cookieNames();
  const raw = res.headers.getSetCookie?.().find((c) => c.startsWith(`${session}=`));
  const cookie = raw ? decodeURIComponent(raw.split(';')[0].split('=').slice(1).join('=')) : null;
  const out = { token, cookie };
  await writeFile(cacheFile, JSON.stringify(out), { mode: 0o600 });
  return out;
}
