// Exploratory audit driver, second generation.
//
// What the first one missed, and why this exists:
//   - it walked one persona, one locale, one theme, so eleven-twelfths of the
//     product's visible surface was never rendered;
//   - it had no accessibility check at all, so every a11y finding had to come
//     from reading source;
//   - it saw whichever state the seeded data happened to produce, so empty,
//     loading and error states — the ones designed last and met first — went
//     unaudited.
//
// It still asserts nothing. It reports.
import { chromium } from '@playwright/test';
import { mkdir, writeFile, readFile } from 'node:fs/promises';
// axe-core is a dependency of packages/ui, not hoisted to the workspace root,
// so resolution from this directory fails. Take the store path directly.
// axe-core is a dependency of packages/ui, not hoisted to the workspace root,
// so plain resolution from wherever this runs will fail. Point AXE_PATH at the
// store path, or let this find it under the repo.
const AXE_PATH =
  process.env.AXE_PATH ??
  new URL(
    '../../../node_modules/.pnpm/axe-core@4.11.3/node_modules/axe-core/axe.min.js',
    import.meta.url,
  ).pathname;

const BASE = process.env.AUDIT_BASE ?? 'http://localhost:8090';
const PASS_ENV = process.env.AUDIT_PASSWORD;
const OUT = process.env.AUDIT_OUT ?? new URL('out2', import.meta.url).pathname;
// The key the target app reads its color-mode preference from. Frameworks
// disagree on this, so it is an override rather than a literal, unlike the
// bearer-token key below, which is this driver's own and never varies.
const COLOR_MODE_KEY = process.env.AUDIT_COLOR_MODE_KEY ?? 'color-mode';

const PASS = PASS_ENV ?? 'AuditPass123!';
const PERSONAS = {
  admin: 'audit-admin@example.com',
  learner: 'audit-learner@example.com',
  empty: 'audit-empty@example.com',
};

// Full matrix on the surfaces a real user meets constantly; one pass over the
// rest, so the run stays finishable.
// Full matrix here; every other surface gets one pass. Override with
// AUDIT_CORE / AUDIT_ALL (comma-separated) when the routes change.
const CORE = (process.env.AUDIT_CORE ?? '/,/browse,/settings').split(',');
// `ALL` used to be a bare literal while the comment above promised an
// AUDIT_ALL override. Auditing 1.9.0 hit that: two new surfaces were passed in
// AUDIT_ALL, the run reported 14 routes instead of 16, and the release's only
// new screens went unaudited while the report looked complete.
const ALL = process.env.AUDIT_ALL?.split(',') ?? [
  '/',
  '/browse',
  '/search',
  '/settings',
  // `/libraries` used to sit here. The app has no such route — it is
  // `/admin/libraries`, already listed below — so every run audited the
  // app's default 404 page and filed its empty <title> as a
  // `document-title` violation.
  // Four runs' worth of that finding were about the error page, not a screen.
  '/flashcards/review',
  '/courses/IUJgcSn2VoE9cPFTG63Lw',
  '/courses/IUJgcSn2VoE9cPFTG63Lw/edit',
  '/courses/IUJgcSn2VoE9cPFTG63Lw/lessons/VzjmQ4VtlzJzXp_k-fj4m',
  '/admin',
  '/admin/libraries',
  '/admin/users',
  '/admin/permissions',
  '/admin/backups',
  '/admin/identify-tasks',
  '/admin/scrapers',
];

const VIEWPORTS = [
  { name: '1440', width: 1440, height: 900 },
  { name: '1024', width: 1024, height: 768 },
  { name: '768', width: 768, height: 1024 },
  { name: '375', width: 375, height: 800 },
];

/** Render-correctness probe. Unlike v1 it walks up for a hidden ancestor, so a
 *  nav button hidden by its parent stops being reported as a zero-height bug. */
const PROBE = () => {
  const hiddenByAncestor = (el) => {
    for (let n = el; n; n = n.parentElement) {
      const s = getComputedStyle(n);
      if (s.display === 'none' || s.visibility === 'hidden') return true;
    }
    return false;
  };
  const out = { bodyOverflow: null, brokenImages: [], zeroHeight: [], clipped: [] };
  const de = document.documentElement;
  if (de.scrollWidth > de.clientWidth + 1) {
    out.bodyOverflow = { scrollWidth: de.scrollWidth, clientWidth: de.clientWidth };
  }
  for (const img of document.images) {
    if (img.complete && img.naturalWidth === 0)
      out.brokenImages.push(img.currentSrc || img.src || '(no src)');
  }
  for (const el of document.querySelectorAll(
    'main, [role="main"], article, section, h1, h2, button, a',
  )) {
    const text = (el.textContent ?? '').trim();
    if (!text || hiddenByAncestor(el)) continue;
    const r = el.getBoundingClientRect();
    if (r.height === 0) out.zeroHeight.push(`${el.tagName.toLowerCase()}: ${text.slice(0, 40)}`);
    const s = getComputedStyle(el);
    if (
      el.scrollWidth > el.clientWidth + 1 &&
      s.textOverflow === 'clip' &&
      s.overflow === 'hidden'
    ) {
      out.clipped.push(`${el.tagName.toLowerCase()}: ${text.slice(0, 40)}`);
    }
  }
  return out;
};

async function tokenFor(persona) {
  const email = PERSONAS[persona];
  const cacheFile = `${OUT}/../.auth-${persona}.json`;
  try {
    const c = JSON.parse(await readFile(cacheFile, 'utf8'));
    const probe = await fetch(`${BASE}/api/v1/courses`, {
      headers: { Authorization: `Bearer ${c.token}` },
    });
    // 429 means "too many requests", not "bad token" — the general throttler
    // (60/min) fires during a sweep and would otherwise send us to sign-in,
    // which has its own, stricter limiter.
    if (probe.ok || probe.status === 429) return c;
  } catch {
    /* no cache */
  }
  const res = await fetch(`${BASE}/api/v1/auth/sign-in/email`, {
    method: 'POST',
    // Better Auth rejects a request whose Origin is absent-but-browser-shaped
    // (undici sends Sec-Fetch-* without Origin) with MISSING_OR_NULL_ORIGIN.
    headers: { 'Content-Type': 'application/json', Origin: BASE },
    body: JSON.stringify({ email, password: PASS }),
  });
  if (!res.ok)
    throw new Error(`sign-in(${persona}) HTTP ${res.status}: ${(await res.text()).slice(0, 160)}`);
  const { token } = await res.json();
  const raw = res.headers.getSetCookie?.().find((c) => c.startsWith('better-auth.session_token='));
  const cookie = raw ? decodeURIComponent(raw.split(';')[0].split('=').slice(1).join('=')) : null;
  const out = { token, cookie };
  await writeFile(cacheFile, JSON.stringify(out), { mode: 0o600 });
  return out;
}

async function makeContext(browser, { token, cookie }, locale, theme, viewport) {
  const ctx = await browser.newContext({ viewport, locale: locale === 'ru' ? 'ru-RU' : 'en-US' });
  await ctx.addCookies([
    ...(cookie
      ? [
          {
            name: 'better-auth.session_token',
            value: cookie,
            domain: 'localhost',
            path: '/',
            httpOnly: true,
            sameSite: 'Lax',
          },
        ]
      : []),
    { name: 'i18n_locale', value: locale, domain: 'localhost', path: '/' },
  ]);
  await ctx.addInitScript(
    ([t, th, key]) => {
      try {
        localStorage.setItem('cs.web.bearer', t);
        localStorage.setItem(key, th);
      } catch {
        /* private mode */
      }
    },
    [token, theme, COLOR_MODE_KEY],
  );
  return ctx;
}

async function auditPage(page, { persona, locale, theme, viewport, path }, sink) {
  const target = `${BASE}${path}`;
  try {
    await page.goto(target, { waitUntil: 'networkidle', timeout: 30_000 });
  } catch (error) {
    sink.findings.push({
      persona,
      locale,
      theme,
      viewport,
      path,
      error: String(error).slice(0, 160),
    });
    return;
  }
  await page.waitForTimeout(600);

  const probe = await page.evaluate(PROBE);
  const themeSeen = await page.evaluate(
    () =>
      document.documentElement.dataset.theme ??
      (document.documentElement.classList.contains('dark') ? 'dark' : 'light'),
  );

  // axe-core: injected fresh per page; the deterministic half this run was
  // missing entirely.
  await page.addScriptTag({ path: AXE_PATH });
  const axe = await page.evaluate(async () => {
    const r = await globalThis.axe.run(document, {
      resultTypes: ['violations'],
      runOnly: {
        type: 'tag',
        values: ['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa', 'best-practice'],
      },
    });
    return r.violations.map((v) => ({
      id: v.id,
      impact: v.impact,
      nodes: v.nodes.length,
      help: v.help,
    }));
  });

  const slug = `${persona}_${locale}_${theme}_${viewport.name}${path.replaceAll(/[^a-z0-9]+/gi, '_') || '_root'}`;
  const shot = `${OUT}/${slug}.png`;
  await page.screenshot({ path: shot });
  sink.findings.push({
    persona,
    locale,
    theme,
    viewport: viewport.name,
    path,
    themeSeen,
    screenshot: shot,
    ...probe,
    axe,
  });
}

async function main() {
  const mode = process.argv[2] ?? 'sweep';
  await mkdir(OUT, { recursive: true });
  const browser = await chromium.launch(
    process.env.CHROME_BIN ? { executablePath: process.env.CHROME_BIN } : {},
  );
  const sink = { findings: [], consoleErrors: [], failedRequests: [], stateProbes: [] };

  const wire = (page, tag) => {
    page.on('console', (m) => {
      if (m.type() === 'error')
        sink.consoleErrors.push({ tag, url: page.url(), text: m.text().slice(0, 280) });
    });
    page.on('requestfailed', (r) =>
      sink.failedRequests.push({
        tag,
        url: page.url(),
        resource: r.url().slice(0, 180),
        reason: r.failure()?.errorText,
      }),
    );
    page.on('response', (r) => {
      if (r.status() >= 400)
        sink.failedRequests.push({
          tag,
          url: page.url(),
          resource: r.url().slice(0, 180),
          reason: `HTTP ${r.status()}`,
        });
    });
  };

  if (mode === 'sweep') {
    // 1) Comparable-to-baseline pass: admin, ru, dark, every surface, 4 widths.
    const adminAuth = await tokenFor('admin');
    for (const vp of VIEWPORTS) {
      const ctx = await makeContext(browser, adminAuth, 'ru', 'dark', vp);
      const page = await ctx.newPage();
      wire(page, 'baseline-shape');
      for (const path of ALL) {
        await auditPage(
          page,
          { persona: 'admin', locale: 'ru', theme: 'dark', viewport: vp, path },
          sink,
        );
      }
      await ctx.close();
    }
    // 2) The matrix the first run never touched: three personas, both locales,
    //    both themes, on the surfaces everyone meets.
    for (const persona of ['admin', 'learner', 'empty']) {
      const auth = await tokenFor(persona);
      for (const locale of ['ru', 'en']) {
        for (const theme of ['dark', 'light']) {
          for (const vp of [VIEWPORTS[0], VIEWPORTS[3]]) {
            const ctx = await makeContext(browser, auth, locale, theme, vp);
            const page = await ctx.newPage();
            wire(page, `${persona}/${locale}/${theme}`);
            for (const path of CORE) {
              await auditPage(page, { persona, locale, theme, viewport: vp, path }, sink);
            }
            await ctx.close();
          }
        }
      }
    }
  }

  if (mode === 'states') {
    // Force the states the data never produces. Without this, an error screen
    // is audited only if something happens to be broken that day.
    const auth = await tokenFor('admin');
    const CASES = [
      {
        name: 'server-error',
        paths: ['/', '/browse', '/courses/IUJgcSn2VoE9cPFTG63Lw'],
        route: (r) =>
          r.fulfill({
            status: 500,
            contentType: 'application/problem+json',
            body: JSON.stringify({
              type: 'about:blank',
              title: 'Internal Server Error',
              status: 500,
            }),
          }),
      },
      {
        name: 'empty-payload',
        paths: ['/', '/browse', '/search?q=zzz'],
        route: (r) =>
          r.fulfill({
            status: 200,
            contentType: 'application/json',
            body: JSON.stringify({ items: [], total: 0 }),
          }),
      },
      {
        name: 'slow',
        paths: ['/', '/browse'],
        route: async (r) => {
          await new Promise((res) => setTimeout(res, 6000));
          await r.continue();
        },
      },
    ];
    for (const c of CASES) {
      const ctx = await makeContext(browser, auth, 'ru', 'dark', VIEWPORTS[0]);
      const page = await ctx.newPage();
      wire(page, `state:${c.name}`);
      await page.route('**/api/v1/**', (route) => {
        const u = route.request().url();
        // Break only the data the screen under test is about. Faking auth logs
        // the audit out; faking /admin/has-users or /admin/instance makes the
        // global middleware think the instance is uninitialised and funnels
        // every route into the first-run wizard, which is a different screen
        // than the one being audited.
        if (
          u.includes('/auth/') ||
          u.includes('/admin/has-users') ||
          u.includes('/admin/instance')
        ) {
          return route.continue();
        }
        return c.route(route);
      });
      for (const path of c.paths) {
        const target = `${BASE}${path}`;
        try {
          await page.goto(target, { waitUntil: 'domcontentloaded', timeout: 40_000 });
          await page.waitForTimeout(c.name === 'slow' ? 2000 : 1500);
        } catch (error) {
          sink.stateProbes.push({ state: c.name, path, error: String(error).slice(0, 160) });
          continue;
        }
        const probe = await page.evaluate(PROBE);
        const text = await page.evaluate(() =>
          (document.querySelector('main')?.innerText ?? document.body.innerText ?? '')
            .replaceAll(/\s+/g, ' ')
            .trim()
            .slice(0, 400),
        );
        const shot = `${OUT}/state_${c.name}${path.replaceAll(/[^a-z0-9]+/gi, '_')}.png`;
        await page.screenshot({ path: shot });
        sink.stateProbes.push({
          state: c.name,
          path,
          screenshot: shot,
          visibleText: text,
          ...probe,
        });
      }
      await ctx.close();
    }
  }

  await writeFile(`${OUT}/report.json`, JSON.stringify(sink, null, 2));
  await browser.close();

  const axeTotal = sink.findings.reduce((n, f) => n + (f.axe?.length ?? 0), 0);
  const render = sink.findings.filter(
    (f) =>
      f.bodyOverflow ||
      f.brokenImages?.length ||
      f.zeroHeight?.length ||
      f.clipped?.length ||
      f.error,
  ).length;
  console.log(`mode: ${mode}`);
  console.log(`pages audited: ${sink.findings.length}`);
  console.log(`render violations: ${render}`);
  console.log(`axe violation instances: ${axeTotal}`);
  console.log(`console errors: ${sink.consoleErrors.length}`);
  console.log(`failed requests: ${sink.failedRequests.length}`);
  console.log(`state probes: ${sink.stateProbes.length}`);
}
main().catch((error) => {
  console.error(error);
  process.exit(1);
});
