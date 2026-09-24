#!/usr/bin/env node
/**
 * One-time setup for the Trega admin panel.
 *
 * Uses your logged-in Firebase CLI to find (or create) the project's Web
 * app and writes `.env` with its SDK config — no console copy-paste needed.
 *
 * Usage:  npm run setup
 */
import { execFileSync } from "node:child_process";
import { writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const PROJECT = process.env.FIREBASE_PROJECT || "tregaxmuse";
const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const ENV_PATH = join(ROOT, ".env");

function fb(args) {
  try {
    return execFileSync("firebase", [...args, "--project", PROJECT], {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "pipe"],
    });
  } catch (e) {
    const err = (e.stderr || e.message || "").toString().split("\n").slice(0, 4).join("\n");
    throw new Error(`firebase ${args.join(" ")} failed:\n${err}`);
  }
}

/** firebase --json output can carry log lines; extract the JSON payload. */
function parseJson(out) {
  const start = out.indexOf("{");
  const end = out.lastIndexOf("}");
  if (start === -1 || end === -1) throw new Error("No JSON in firebase output.");
  return JSON.parse(out.slice(start, end + 1));
}

function findWebAppId() {
  const list = parseJson(fb(["apps:list", "--json"]));
  const apps = list?.result?.apps ?? list?.apps ?? [];
  const web = apps.find((a) => String(a.platform || "").toUpperCase() === "WEB");
  return web?.appId || null;
}

function createWebApp() {
  console.log("No web app registered — creating 'Trega Admin'…");
  const created = parseJson(fb(["apps:create", "WEB", "Trega Admin", "--json"]));
  return created?.result?.appId || created?.appId || null;
}

function sdkConfig(appId) {
  const out = fb(["apps:sdkconfig", "WEB", appId]);
  const get = (key) => {
    const m = out.match(new RegExp(key + '\\s*:\\s*"([^"]+)"'));
    return m ? m[1] : "";
  };
  return {
    VITE_FIREBASE_API_KEY: get("apiKey"),
    VITE_FIREBASE_AUTH_DOMAIN: get("authDomain"),
    VITE_FIREBASE_PROJECT_ID: get("projectId") || PROJECT,
    VITE_FIREBASE_STORAGE_BUCKET: get("storageBucket"),
    VITE_FIREBASE_MESSAGING_SENDER_ID: get("messagingSenderId"),
    VITE_FIREBASE_APP_ID: get("appId") || appId,
  };
}

let appId = findWebAppId();
if (!appId) appId = createWebApp();
if (!appId) throw new Error("Could not find or create the Firebase web app.");

const cfg = sdkConfig(appId);
const missing = Object.entries(cfg)
  .filter(([, v]) => !v)
  .map(([k]) => k);
if (missing.length) {
  throw new Error("Incomplete SDK config, missing: " + missing.join(", "));
}

writeFileSync(ENV_PATH, Object.entries(cfg).map(([k, v]) => `${k}=${v}`).join("\n") + "\n");
console.log(`Done — wrote ${ENV_PATH} (web app ${appId}). Run: npm run dev`);
