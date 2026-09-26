// The adapter is the only project-specific part of the driver. This asserts
// its shape, so a project that rewrites it for its own API finds out here
// rather than during a run that reports zero findings.
import assert from 'node:assert/strict';
import { signIn, cookieNames } from './auth-adapter.mjs';

assert.equal(typeof signIn, 'function', 'signIn must be exported');
assert.equal(signIn.length, 3, 'signIn takes (base, persona, password)');

const names = cookieNames();
assert.ok(names.session, 'cookieNames().session must be a non-empty string');
assert.ok(names.locale, 'cookieNames().locale must be a non-empty string');

console.log('auth-adapter contract ok');
