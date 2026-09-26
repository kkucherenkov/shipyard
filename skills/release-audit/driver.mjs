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
import { mkdir, writeFile } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { signIn, cookieNames, bearerStorageKey, isAuthRoute } from './auth-adapter.mjs';
// axe-core is often installed somewhere this file's own module resolution
// cannot see — nested under a workspace package rather than hoisted to
// where the driver runs from. AXE_PATH is the escape hatch for that case;
// the default is plain module resolution, not a path baked in for one
// project's dependency layout.
const require = createRequire(import.meta.url);
const AXE_PATH = process.env.AXE_PATH ?? require.resolve('axe-core/axe.min.js');

const BASE = process.env.AUDIT_BASE ?? 'http://localhost:8090';
// The cookies below are scoped by hostname, not by BASE as a whole — derive
// it, or pointing AUDIT_BASE anywhere but localhost drops both cookies
// silently and the run lands in the sign-in-redirect failure mode below.
const BASE_HOST = new URL(BASE).hostname;
const PASS_ENV = process.env.AUDIT_PASSWORD;
const OUT = process.env.AUDIT_OUT ?? new URL('out2', import.meta.url).pathname;
// The key the target app reads its color-mode preference from. Frameworks
// disagree on this, so it is an override rather than a literal.
const COLOR_MODE_KEY = process.env.AUDIT_COLOR_MODE_KEY ?? 'color-mode';

const PASS = PASS_ENV ?? 'AuditPass123!';
const { session: SESSION_COOKIE, locale: LOCALE_COOKIE } = cookieNames();

// CORE, ALL and PERSONA_NAMES all come from the project's own declared
// surface — `## Audit routes` / `## Audit personas` in its CLAUDE.md, see
// SKILL.md — never from a list baked into this file. A silent fallback here
// is the exact failure this method exists to catch: a route list once
// dropped two new screens while the run still reported a route count as if
// nothing were missing, and a stale route's 404 page got filed as a real
// screen's defect for several runs running. Refuse to guess; fail fast.
function requiredList(envVar, heading) {
  const raw = process.env[envVar];
  if (!raw) {
    throw new Error(
      `${envVar} is required (comma-separated), set from \`${heading}\` in ` +
        "the project's CLAUDE.md — see SKILL.md. Refusing to fall back to a " +
        'built-in list.',
    );
  }
  return raw.split(',').filter(Boolean);
}

// The surfaces a real user meets constantly (full matrix) and everything
// else (one pass), so the run stays finishable.
const CORE = requiredList('AUDIT_CORE', '## Audit routes');
const ALL = requiredList('AUDIT_ALL', '## Audit routes');
// The persona names the sweep iterates. auth-adapter.mjs's `PERSONAS` map
// maps these to sign-in credentials; keep the two in step when either
// changes.
const PERSONA_NAMES = requiredList('AUDIT_PERSONAS', '## Audit personas');

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
  return signIn(BASE, persona, PASS);
}

async function makeContext(browser, { token, cookie }, locale, theme, viewport) {
  const ctx = await browser.newContext({ viewport, locale: locale === 'ru' ? 'ru-RU' : 'en-US' });
  await ctx.addCookies([
    ...(cookie
      ? [
          {
            name: SESSION_COOKIE,
            value: cookie,
            domain: BASE_HOST,
            path: '/',
            httpOnly: true,
            sameSite: 'Lax',
          },
        ]
      : []),
    { name: LOCALE_COOKIE, value: locale, domain: BASE_HOST, path: '/' },
  ]);
  await ctx.addInitScript(
    ([t, th, bearerKey, colorModeKey]) => {
      try {
        localStorage.setItem(bearerKey, t);
        localStorage.setItem(colorModeKey, th);
      } catch {
        /* private mode */
      }
    },
    [token, theme, bearerStorageKey(), COLOR_MODE_KEY],
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
    // 2) The matrix the first run never touched: every declared persona, both
    //    locales, both themes, on the surfaces everyone meets.
    for (const persona of PERSONA_NAMES) {
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
    // Every case forces a response shape, not a particular route, so the
    // declared CORE list — the same one `sweep` reads from `## Audit routes`
    // — is enough; no case needs a route of its own. A literal route here
    // (worse, one with a literal id) is Important 1's bug again: a stale or
    // product-specific path turns the forced state into a test of the
    // target's 404 page instead of the state under test.
    const CASES = [
      {
        name: 'server-error',
        paths: CORE,
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
        paths: CORE,
        route: (r) =>
          r.fulfill({
            status: 200,
            contentType: 'application/json',
            body: JSON.stringify({ items: [], total: 0 }),
          }),
      },
      {
        name: 'slow',
        paths: CORE,
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
        // the audit out (isAuthRoute is the adapter's own definition of "auth",
        // so a project whose sign-in flow lives somewhere else fixes this by
        // editing auth-adapter.mjs, not here); faking /admin/has-users or
        // /admin/instance makes the global middleware think the instance is
        // uninitialised and funnels every route into the first-run wizard,
        // which is a different screen than the one being audited.
        if (
          isAuthRoute(u) ||
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
