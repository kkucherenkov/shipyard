// The adapter is the only project-specific part of the driver. This asserts
// its shape, so a project that rewrites it for its own API finds out here
// rather than during a run that reports zero findings.
import assert from 'node:assert/strict';
import { signIn, cookieNames, bearerStorageKey, isAuthRoute } from './auth-adapter.mjs';

assert.equal(typeof signIn, 'function', 'signIn must be exported');
assert.equal(signIn.length, 3, 'signIn takes (base, persona, password)');

const names = cookieNames();
assert.equal(typeof names.session, 'string', 'cookieNames().session must be a non-empty string');
assert.ok(names.session.length > 0, 'cookieNames().session must be a non-empty string');
assert.equal(typeof names.locale, 'string', 'cookieNames().locale must be a non-empty string');
assert.ok(names.locale.length > 0, 'cookieNames().locale must be a non-empty string');

// driver.mjs imports this to seed the bearer token into localStorage; a
// rewrite that drops it breaks that import before a single page is audited.
assert.equal(typeof bearerStorageKey, 'function', 'bearerStorageKey must be exported');
const bearerKey = bearerStorageKey();
assert.equal(typeof bearerKey, 'string', 'bearerStorageKey() must return a non-empty string');
assert.ok(bearerKey.length > 0, 'bearerStorageKey() must return a non-empty string');

// driver.mjs's `states` mode imports this to decide which requests to let
// through unmocked; a rewrite that drops it breaks that import before
// `states` mode's first page load.
assert.equal(typeof isAuthRoute, 'function', 'isAuthRoute must be exported');
assert.equal(typeof isAuthRoute('http://x/api/v1/auth/sign-in/email'), 'boolean');

console.log('auth-adapter contract ok');
