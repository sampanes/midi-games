import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const appSource = await readFile(new URL("../src/midi-listener/app.js", import.meta.url), "utf8");
const pageSource = await readFile(new URL("../src/midi-listener/index.html", import.meta.url), "utf8");

test("every listener DOM reference exists exactly once", () => {
  const referencedIds = [...appSource.matchAll(/byId\("([^"]+)"\)/g)].map((match) => match[1]);
  assert.ok(referencedIds.length > 0);
  assert.equal(new Set(referencedIds).size, referencedIds.length, "app.js should not declare duplicate element references");

  const pageIds = [...pageSource.matchAll(/\bid="([^"]+)"/g)].map((match) => match[1]);
  const counts = new Map(pageIds.map((id) => [id, pageIds.filter((candidate) => candidate === id).length]));
  for (const id of referencedIds) assert.equal(counts.get(id), 1, `expected one #${id} in index.html`);
});

test("listener loads the application as an external module", () => {
  assert.match(pageSource, /<script\s+type="module"\s+src="\.\/app\.js"><\/script>/);
  assert.doesNotMatch(pageSource, /<script(?![^>]*\bsrc=)[^>]*>/i, "inline scripts would violate the listener CSP");
});
