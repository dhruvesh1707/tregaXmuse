#!/usr/bin/env node
/**
 * One-time setup for the Trega admin panel.
 *
 * Writes `.env` with the Firebase web SDK config, trying these sources in
 * order (first one that works wins):
 *   1. Firebase CLI (`apps:list` / `apps:create` / `apps:sdkconfig`)
 *   2. trega_app/lib/firebase_options.dart (flutterfire-generated `web` entry)
 *   3. trega_app/android/app/google-services.json
 *
 * Usage:  npm run setup   (from trega_admin/)
 */
import { execFileSync } from "node:child_process";
import { writeFileSync, readFileSync, existsSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const PROJECT = process.env.FIREBASE_PROJECT || "tregaxmuse";
const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const REPO_ROOT = join(ROOT, "..");
const ENV_PATH = join(ROOT, ".env");

function fb(args) {
  // On Windows the CLI is firebase.cmd — it only resolves through a shell.
  // If firebase isn't on PATH at all, fall back to npx (one-time download).
  // NOTE: stdin must NOT be "ignore" — on Windows that makes Node-based
  // CLIs abort on exit with "Assertion failed: !(handle->flags &
  // UV_HANDLE_CLOSING)". A piped stdin that is immediately EOF'd is safe.
  const shell = process.platform === "win32";
  const opts = { encoding: "utf8", stdio: ["pipe", "pipe", "pipe"], input: "", shell };
  try {
    return execFileSync("firebase", [...args, "--project", PROJECT], opts);
  } catch (e) {
    const msg = (e.stderr || e.message || "").toString();
    const notFound = e.code === "ENOENT" || /not recognized|command not found/i.test(msg);
    if (!notFound) {
      const err = msg.split("\n").slice(0, 4).join("\n");
      throw new Error(`firebase ${args.join(" ")} failed:\n${err}`);
    }
    console.log("Firebase CLI not on PATH — using npx firebase-tools instead…");
    try {
      return execFileSync("npx", ["--yes", "firebase-tools", ...args, "--project", PROJECT], opts);
    } catch (e2) {
      const err2 = (e2.stderr || e2.message || "").toString().split("\n").slice(0, 4).join("\n");
      throw new Error(`npx firebase-tools ${args.join(" ")} failed:\n${err2}`);
    }
  }
}

/** firebase --json output can carry log lines; extract the JSON payload. */
function parseJson(out) {
  const start = out.indexOf("{");
  const end = out.lastIndexOf("}");
  if (start === -1 || end === -1) throw new Error("No JSON in firebase output.");
  return JSON.parse(out.slice(start, end + 1));
}

function configFromCli() {
  const list = parseJson(fb(["apps:list", "--json"]));
  const apps = list?.result?.apps ?? list?.apps ?? [];
  const web = apps.find((a) => String(a.platform || "").toUpperCase() === "WEB");
  let appId = web?.appId || null;
  if (!appId) {
    console.log("No web app registered — creating 'Trega Admin'…");
    const created = parseJson(fb(["apps:create", "WEB", "Trega Admin", "--json"]));
    appId = created?.result?.appId || created?.appId || null;
  }
  if (!appId) throw new Error("Could not determine the web app id.");
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

function configFromDart() {
  const p = join(REPO_ROOT, "trega_app", "lib", "firebase_options.dart");
  if (!existsSync(p)) return null;
  const src = readFileSync(p, "utf8");
  const m = src.match(/static const FirebaseOptions web\s*=\s*FirebaseOptions\(([\s\S]*?)\);/);
  if (!m) return null;
  const get = (key) => {
    const mm = m[1].match(new RegExp(key + "\\s*:\\s*'([^']+)'"));
    return mm ? mm[1] : "";
  };
  return {
    VITE_FIREBASE_API_KEY: get("apiKey"),
    VITE_FIREBASE_AUTH_DOMAIN: get("authDomain"),
    VITE_FIREBASE_PROJECT_ID: get("projectId") || PROJECT,
    VITE_FIREBASE_STORAGE_BUCKET: get("storageBucket"),
    VITE_FIREBASE_MESSAGING_SENDER_ID: get("messagingSenderId"),
    VITE_FIREBASE_APP_ID: get("appId"),
  };
}

function configFromGoogleServices() {
  const p = join(REPO_ROOT, "trega_app", "android", "app", "google-services.json");
  if (!existsSync(p)) return null;
  const j = JSON.parse(readFileSync(p, "utf8"));
  const info = j.project_info || {};
  const key = j.client?.[0]?.api_key?.[0]?.current_key || "";
  if (!key || !info.project_id) return null;
  return {
    VITE_FIREBASE_API_KEY: key,
    VITE_FIREBASE_AUTH_DOMAIN: `${info.project_id}.firebaseapp.com`,
    VITE_FIREBASE_PROJECT_ID: info.project_id,
    VITE_FIREBASE_STORAGE_BUCKET: info.storage_bucket || `${info.project_id}.appspot.com`,
    VITE_FIREBASE_MESSAGING_SENDER_ID: info.project_number || "",
    // No web app id in this file; Auth/Firestore/Functions don't need it.
    VITE_FIREBASE_APP_ID: "",
  };
}

const sources = [
  ["Firebase CLI", configFromCli],
  ["firebase_options.dart", configFromDart],
  ["google-services.json", configFromGoogleServices],
];

let cfg = null;
let used = "";
for (const [name, fn] of sources) {
  try {
    const c = fn();
    if (c && c.VITE_FIREBASE_API_KEY && c.VITE_FIREBASE_PROJECT_ID) {
      cfg = c;
      used = name;
      break;
    }
  } catch (e) {
    console.log(`(${name} failed: ${(e.message || "").split("\n")[0]})`);
  }
}

if (!cfg) {
  throw new Error(
    "Could not determine the Firebase web config.\n" +
      "Create trega_admin/.env from .env.example with the web config from\n" +
      "Firebase console → Project settings → Your apps."
  );
}

writeFileSync(ENV_PATH, Object.entries(cfg).map(([k, v]) => `${k}=${v}`).join("\n") + "\n");
console.log(`Done — wrote ${ENV_PATH} (source: ${used}). Run: npm run dev`);
