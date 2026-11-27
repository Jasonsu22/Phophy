// Renders one frame of every page of the presentation, for the storyboard.
//
//   node stills.mjs OUT_DIR [page-id ...]
//
// Each frame is taken near the end of its page, when everything has appeared
// (or at the page's "still" time in talk.json). Named pages only, if given.
import { bundle } from "@remotion/bundler";
import { openBrowser, renderStill, selectComposition } from "@remotion/renderer";
import fs from "node:fs";
import path from "node:path";

// "--at=SECONDS" takes the frame at that moment of the named page(s) instead, to check an animation's timing.
const at = process.argv.find((arg) => arg.startsWith("--at="))?.slice(5);
const [outDir, ...only] = process.argv.slice(2).filter((arg) => !arg.startsWith("--"));
if (!outDir) throw new Error("usage: node stills.mjs OUT_DIR [page-id ...]");
fs.mkdirSync(outDir, { recursive: true });
const talk = JSON.parse(fs.readFileSync("src/talk.json", "utf8"));
const timing = JSON.parse(fs.readFileSync("src/talk-timing.json", "utf8"));

const serveUrl = await bundle({ entryPoint: path.resolve("src/index.ts") });
const browser = await openBrowser("chrome");
for (const [i, page] of talk.pages.entries()) {
  if (only.length > 0 && !only.includes(page.id)) continue;
  const inputProps = { page: i };
  const composition = await selectComposition({ serveUrl, id: "TalkPage", inputProps, puppeteerInstance: browser });
  const moment = at ? Number(at) : (page.still ?? timing.pages[i].seconds - 0.25);
  const frame = Math.max(0, Math.min(composition.durationInFrames - 1, Math.round(moment * composition.fps)));
  const output = path.join(outDir, `${String(i + 1).padStart(2, "0")}${at ? `-at-${at}` : ""}.jpeg`);
  await renderStill({ composition, serveUrl, output, frame, inputProps, imageFormat: "jpeg", jpegQuality: 90, scale: 2 / 3, puppeteerInstance: browser, overwrite: true });
  console.log(`${String(i + 1).padStart(2)} ${page.id} frame ${frame}`);
}
await browser.close({ silent: true });
