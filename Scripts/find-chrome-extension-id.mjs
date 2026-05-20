#!/usr/bin/env node
import { existsSync, readdirSync, readFileSync, statSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, isAbsolute, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const EXTENSION_NAME = process.env.SWIFTGETX_CHROME_EXTENSION_NAME || "SwiftGetX";
const EXTENSION_DESCRIPTION = "Send links, pages, media, and detected downloads to SwiftGetX.";
const EXTENSION_POPUP = "popup.html";
const SCRIPT_DIR = dirname(fileURLToPath(import.meta.url));
const USER_DATA_DIR = process.env.SWIFTGETX_CHROME_USER_DATA_DIR
  || join(homedir(), "Library", "Application Support", "Google", "Chrome");
const DEVELOPMENT_EXTENSION_DIR = resolve(
  process.env.SWIFTGETX_CHROME_EXTENSION_DIR
    || join(SCRIPT_DIR, "..", "Sources", "SwiftGetX", "Resources", "ChromeExtension")
);
const PREFERENCE_FILENAMES = ["Secure Preferences", "Preferences"];

const ids = [...discoverExtensionIDs(USER_DATA_DIR)].sort();

for (const id of ids) {
  console.log(id);
}

function discoverExtensionIDs(userDataDir) {
  const discovered = new Set();

  for (const preferenceFile of preferenceFiles(userDataDir)) {
    for (const id of discoverExtensionIDsInPreferenceFile(preferenceFile)) {
      discovered.add(id);
    }
  }

  return discovered;
}

function preferenceFiles(userDataDir) {
  const files = PREFERENCE_FILENAMES.map((filename) => join(userDataDir, filename));

  if (!existsSync(userDataDir)) {
    return files.filter(existsSync);
  }

  for (const entry of readdirSync(userDataDir)) {
    const candidate = join(userDataDir, entry);
    if (!isDirectory(candidate)) {
      continue;
    }

    for (const filename of PREFERENCE_FILENAMES) {
      files.push(join(candidate, filename));
    }
  }

  return files.filter(existsSync);
}

function discoverExtensionIDsInPreferenceFile(preferenceFile) {
  const root = readJSON(preferenceFile);
  const settings = root?.extensions?.settings;

  if (!settings || typeof settings !== "object") {
    return [];
  }

  return Object.entries(settings)
    .filter(([id, extensionSettings]) => {
      return isValidExtensionID(id)
        && isSwiftGetXExtension(extensionSettings);
    })
    .map(([id]) => id);
}

function isSwiftGetXExtension(extensionSettings) {
  const manifest = extensionSettings?.manifest;
  if (!manifest || typeof manifest !== "object") {
    return false;
  }

  if (!permissions(manifest).includes("nativeMessaging")) {
    return false;
  }

  if (String(manifest.name || "").toLowerCase() === EXTENSION_NAME.toLowerCase()) {
    return true;
  }

  return isDevelopmentExtensionPath(extensionSettings?.path)
    && hasSwiftGetXExtensionShape(manifest);
}

function hasSwiftGetXExtensionShape(manifest) {
  return manifest.description === EXTENSION_DESCRIPTION
    && manifest.action?.default_popup === EXTENSION_POPUP;
}

function isDevelopmentExtensionPath(path) {
  if (!path || !isAbsolute(path)) {
    return false;
  }

  const resolvedPath = resolve(path);
  return resolvedPath === DEVELOPMENT_EXTENSION_DIR
    || existsSync(join(resolvedPath, "manifest.json"));
}

function permissions(manifest) {
  return [
    ...(Array.isArray(manifest.permissions) ? manifest.permissions : []),
    ...(Array.isArray(manifest.optional_permissions) ? manifest.optional_permissions : [])
  ];
}

function readJSON(filePath) {
  try {
    return JSON.parse(readFileSync(filePath, "utf8"));
  } catch {
    return null;
  }
}

function isDirectory(path) {
  try {
    return statSync(path).isDirectory();
  } catch {
    return false;
  }
}

function isValidExtensionID(id) {
  return /^[a-p]{32}$/.test(id);
}
