const SPARKLE = "http://www.andymatuschak.org/xml-namespaces/sparkle";
const RELEASES = "https://github.com/pobrespandas/draftly/releases";
const VERSION = /^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$/;
const MINIMUM = /^[0-9]+(?:\.[0-9]+){0,2}$/;

export function releaseFromDocument(document) {
  if (document.documentElement?.tagName !== "rss" || document.querySelector("parsererror")) return null;
  const item = document.querySelector("channel > item");
  const enclosure = item?.querySelector("enclosure");
  if (!enclosure) return null;
  const version = item.getElementsByTagNameNS(SPARKLE, "shortVersionString")[0]?.textContent?.trim()
    || enclosure.getAttributeNS(SPARKLE, "shortVersionString");
  const minimum = item.getElementsByTagNameNS(SPARKLE, "minimumSystemVersion")[0]?.textContent?.trim();
  if (!VERSION.test(version || "") || !MINIMUM.test(minimum || "")) return null;
  const tag = `v${version}`;
  const download = `${RELEASES}/download/${tag}/Draftly.zip`;
  if (enclosure.getAttribute("url") !== download) return null;
  return { version, minimum, download: `${RELEASES}/download/${tag}/Draftly-${version}.dmg`, notes: `${RELEASES}/tag/${tag}` };
}

export async function loadRelease(fetcher, parse) {
  try {
    const response = await fetcher("/appcast.xml", { cache: "no-cache", redirect: "error" });
    if (!response.ok) return null;
    const xml = await response.text();
    if (xml.length > 2 * 1024 * 1024 || /<!DOCTYPE|<!ENTITY/i.test(xml)) return null;
    return releaseFromDocument(parse(xml));
  } catch {
    return null;
  }
}

export async function updateAvailability(document, fetcher, parse) {
  const release = await loadRelease(fetcher, parse);
  if (!release) return;
  const pending = document.getElementById("release-pending");
  const available = document.getElementById("release-available");
  const download = document.getElementById("release-download");
  const notes = document.getElementById("release-notes");
  const details = document.getElementById("release-details");
  const hero = document.getElementById("release-hero-note");
  if (!pending || !available || !download || !notes || !details || !hero) return;
  download.href = release.download;
  download.textContent = `Download Draftly ${release.version}`;
  notes.href = release.notes;
  details.textContent = `Requires macOS ${release.minimum} or later.`;
  hero.textContent = `macOS ${release.minimum} or later · Version ${release.version}`;
  pending.hidden = true;
  available.hidden = false;
}

if (typeof document !== "undefined") {
  updateAvailability(document, fetch, xml => new DOMParser().parseFromString(xml, "application/xml"));
}
