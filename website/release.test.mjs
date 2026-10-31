import test from "node:test";
import assert from "node:assert/strict";
import { releaseFromDocument, loadRelease, updateAvailability } from "./public/release.mjs";

const url = "https://github.com/pobrespandas/draftly/releases/download/v1.2.3/Draftly.zip";
function feed({ version = "1.2.3", minimum = "26.0", download = url, malformed = false } = {}) {
  const enclosure = { getAttribute: () => download, getAttributeNS: () => null };
  const item = {
    querySelector: name => name === "enclosure" ? enclosure : null,
    getElementsByTagNameNS: (_, name) => [{ textContent: name === "shortVersionString" ? version : minimum }],
  };
  return { documentElement: { tagName: "rss" },
    querySelector: name => name === "parsererror" ? (malformed ? {} : null) : item };
}

test("accepts a release only when metadata and GitHub asset agree", () => {
  assert.deepEqual(releaseFromDocument(feed()), {
    version: "1.2.3", minimum: "26.0", download: "https://github.com/pobrespandas/draftly/releases/download/v1.2.3/Draftly-1.2.3.dmg",
    notes: "https://github.com/pobrespandas/draftly/releases/tag/v1.2.3",
  });
  for (const bad of [feed({ version: "01.2.3" }), feed({ minimum: "26<script>" }),
    feed({ download: "https://example.com/Draftly.zip" }), feed({ malformed: true })]) {
    assert.equal(releaseFromDocument(bad), null);
  }
});

test("unavailable, redirected, invalid or oversized feeds stay unavailable", async () => {
  assert.equal(await loadRelease(async () => ({ ok: false }), () => feed()), null);
  assert.equal(await loadRelease(async () => { throw new Error("redirect"); }, () => feed()), null);
  assert.equal(await loadRelease(async () => ({ ok: true, text: async () => "<!DOCTYPE rss>" }), () => feed()), null);
  assert.equal(await loadRelease(async () => ({ ok: true, text: async () => "x".repeat(2 * 1024 * 1024 + 1) }), () => feed()), null);
});

test("availability stays hidden on failure and shows only validated metadata", async () => {
  const ids = ["release-pending", "release-available", "release-download", "release-notes", "release-details", "release-hero-note"];
  const elements = Object.fromEntries(ids.map(id => [id, { hidden: id === "release-available" }]));
  const document = { getElementById: id => elements[id] };
  await updateAvailability(document, async () => ({ ok: false }), () => feed());
  assert.equal(elements["release-available"].hidden, true);
  assert.equal(elements["release-pending"].hidden, false);
  await updateAvailability(document, async (path, options) => {
    assert.equal(path, "/appcast.xml");
    assert.equal(options.redirect, "error");
    return { ok: true, text: async () => "<rss/>" };
  }, () => feed());
  assert.equal(elements["release-available"].hidden, false);
  assert.equal(elements["release-pending"].hidden, true);
  assert.equal(elements["release-download"].href, "https://github.com/pobrespandas/draftly/releases/download/v1.2.3/Draftly-1.2.3.dmg");
  assert.equal(elements["release-details"].textContent, "Requires macOS 26.0 or later.");
  assert.equal(elements["release-notes"].href, "https://github.com/pobrespandas/draftly/releases/tag/v1.2.3");
});
