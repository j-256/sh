import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { capture, outputPath } from './browser.mjs';

const root = fileURLToPath(new URL('../../', import.meta.url));
const output = outputPath(root, 'Capture the public Toolio renderer for a published revision matching the local catalog.');
const catalog = await readFile(new URL('../../INDEX.md', import.meta.url), 'utf8');
const revisions = new Set();
for (const ref of ['HEAD', 'origin/main']) {
  try { revisions.add(execFileSync('git', ['rev-parse', ref], { cwd: root, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim()); } catch {}
}
if (process.env.COVER_REVISION) revisions.add(process.env.COVER_REVISION);
let revision;
for (const sha of revisions) {
  assert.match(sha, /^[a-f0-9]{40}$/);
  const response = await fetch(`https://raw.githubusercontent.com/j-256/sh/${sha}/INDEX.md`, { signal: AbortSignal.timeout(30_000) });
  if (response.ok && await response.text() === catalog) { revision = sha; break; }
  if (!response.ok && response.status !== 404) throw new Error(`Catalog fetch failed: HTTP ${response.status}`);
}
assert.ok(revision, 'Publish the catalog revision to a topic branch before capture; no published revision matches local INDEX.md');
const response = await fetch(`https://gh.toolio.sh/j-256/sh/${revision}/INDEX.md.html`, { signal: AbortSignal.timeout(30_000) });
assert.ok(response.ok, `Toolio rendering failed: HTTP ${response.status}`);
const html = await response.text();
const heading = catalog.match(/^# (.+)$/m)?.[1];
assert.ok(heading);
await capture({ output, html, viewport: { width: 1440, height: 960 },
  async ready(page) {
    await page.locator('h1').waitFor();
    assert.equal((await page.locator('h1').textContent()).trim(), heading);
    assert.ok(await page.locator('table tbody tr').count() > 0, 'The catalog must contain tools');
  },
});
