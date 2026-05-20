const NATIVE_HOST_NAME = "com.swiftgetx.native";
const EXTENSION_VERSION = chrome.runtime.getManifest().version;
const NATIVE_HEALTH_CHECK_ALARM = "swiftgetx-native-health-check";
const NATIVE_HEALTH_CHECK_PERIOD_MINUTES = 30;
const NATIVE_SETUP_RETRY_TIMEOUT_MS = 8000;
const NATIVE_SETUP_RETRY_INTERVAL_MS = 1000;
const NATIVE_SETUP_THROTTLE_MS = 60 * 1000;
const NATIVE_SETUP_LAST_OPENED_KEY = "nativeSetupLastOpenedAt";
const NATIVE_SETUP_PAIRED_KEY = "nativeHostPairingConfirmed";
const RECENT_REQUEST_CONTEXT_TTL_MS = 5 * 60 * 1000;
const RECENT_REQUEST_CONTEXT_LIMIT = 200;
const DEFAULT_OPTIONS = {
  takeoverDownloads: true,
  takeoverDownloadsUserSet: false
};
const DOWNLOAD_SOURCE_PATTERN = /(magnet:\?|https?:\/\/|[^\s<>\]]+\.torrent(?:[?#][^\s<>\]]*)?)/i;
const CONTEXT_HEADER_NAMES = new Set([
  "accept",
  "accept-language",
  "authorization",
  "cookie",
  "origin",
  "referer",
  "user-agent",
  "x-api-key",
  "x-auth-token",
  "x-csrf-token",
  "x-requested-with",
  "x-xsrf-token"
]);
const SENSITIVE_HEADER_NAMES = new Set([
  "authorization",
  "cookie",
  "x-api-key",
  "x-auth-token",
  "x-csrf-token",
  "x-xsrf-token"
]);
let currentOptions = { ...DEFAULT_OPTIONS };
let activeNativeRepair;
let recentRequestContexts = new Map();
const i18n = (key, substitutions) => chrome.i18n.getMessage(key, substitutions) || key;

const MENU_ITEMS = [
  {
    id: "send-link",
    titleKey: "contextSendLink",
    contexts: ["link"]
  },
  {
    id: "send-page",
    titleKey: "contextSendPage",
    contexts: ["page"]
  },
  {
    id: "send-selection",
    titleKey: "contextSendSelection",
    contexts: ["selection"]
  },
  {
    id: "send-media",
    titleKey: "contextSendMedia",
    contexts: ["image", "video", "audio"]
  },
  {
    id: "scan-page",
    titleKey: "contextScanPage",
    contexts: ["page"]
  }
];

chrome.runtime.onInstalled.addListener(() => {
  chrome.contextMenus.removeAll(() => {
    for (const item of MENU_ITEMS) {
      chrome.contextMenus.create({
        id: item.id,
        title: i18n(item.titleKey),
        contexts: item.contexts
      });
    }
  });

  chrome.storage.local.get(DEFAULT_OPTIONS, (options) => {
    const nextOptions = { ...DEFAULT_OPTIONS, ...options };
    if (!options.takeoverDownloadsUserSet) {
      nextOptions.takeoverDownloads = true;
    }
    chrome.storage.local.set(nextOptions);
  });

  scheduleNativeHealthChecks();
  runNativeHealthCheck("installed");
});

chrome.runtime.onStartup.addListener(() => {
  scheduleNativeHealthChecks();
  runNativeHealthCheck("startup");
});

chrome.alarms.onAlarm.addListener((alarm) => {
  if (alarm.name === NATIVE_HEALTH_CHECK_ALARM) {
    runNativeHealthCheck("alarm");
  }
});

refreshOptions();
scheduleNativeHealthChecks();
runNativeHealthCheck("service-worker");

chrome.storage.onChanged.addListener((changes, areaName) => {
  if (areaName !== "local") {
    return;
  }

  if (changes.takeoverDownloads) {
    currentOptions.takeoverDownloads = Boolean(changes.takeoverDownloads.newValue);
  }

  if (changes.takeoverDownloadsUserSet) {
    currentOptions.takeoverDownloadsUserSet = Boolean(changes.takeoverDownloadsUserSet.newValue);
  }
});

chrome.contextMenus.onClicked.addListener((info, tab) => {
  handleContextMenuClick(info, tab);
});

chrome.webRequest.onBeforeRequest.addListener(
  captureRequestBasics,
  { urls: ["<all_urls>"] },
  ["requestBody"]
);

chrome.webRequest.onBeforeSendHeaders.addListener(
  captureRequestHeaders,
  { urls: ["<all_urls>"] },
  ["requestHeaders", "extraHeaders"]
);

chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (!message) {
    return false;
  }

  if (message.type === "swiftgetx-download") {
    sendToSwiftGetX(message.payload, {
      allowSetup: true,
      forceSetupOpen: Boolean(message.forceSetupOpen)
    })
      .then(sendResponse)
      .catch((error) => {
        sendResponse({
          ok: false,
          message: error.message || String(error)
        });
      });
    return true;
  }

  if (message.type === "swiftgetx-ping") {
    ensureNativeHostHealthy({
      allowSetup: message.allowSetup !== false,
      forceSetupOpen: Boolean(message.forceSetupOpen),
      reason: message.reason || "manual-check"
    })
      .then(sendResponse)
      .catch((error) => {
        sendResponse({
          ok: false,
          message: error.message || String(error)
        });
      });
    return true;
  }

  return false;
});

chrome.downloads.onDeterminingFilename.addListener((downloadItem, suggest) => {
  handleDownloadDeterminingFilename(downloadItem, suggest).catch((error) => {
    markFailure(error.message || String(error));
  });
  return true;
});

async function handleDownloadDeterminingFilename(downloadItem, suggest) {
  let didSuggest = false;
  const allowChromeFilename = () => {
    if (!didSuggest) {
      didSuggest = true;
      suggest();
    }
  };

  try {
    if (!shouldTakeOverDownload(downloadItem)) {
      allowChromeFilename();
      return;
    }

    const url = downloadSourceURL(downloadItem);
    const payload = {
      url,
      finalUrl: downloadItem.finalUrl,
      originalUrl: downloadItem.url,
      suggestedFilename: filenameFromPath(downloadItem.filename) || filenameFromURL(url),
      sourcePageUrl: downloadItem.referrer,
      source: "download-takeover"
    };

    // Send to SwiftGetX FIRST — only cancel Chrome download after confirmation.
    const result = await sendToSwiftGetX(payload, { allowSetup: false });

    if (!result.ok) {
      // Native host unreachable or rejected — fall back to Chrome download.
      allowChromeFilename();
      return;
    }

    // SwiftGetX accepted the task — cancel and erase the Chrome download.
    await callDownloads("cancel", downloadItem.id);
    await callDownloads("erase", { id: downloadItem.id });
  } catch (error) {
    // On any unexpected error, let Chrome proceed with the download.
    allowChromeFilename();
    throw error;
  }
}

function shouldTakeOverDownload(downloadItem) {
  return Boolean(currentOptions.takeoverDownloads && isSupportedSource(downloadSourceURL(downloadItem)));
}

function downloadSourceURL(downloadItem) {
  return downloadItem.finalUrl || downloadItem.url || "";
}

async function handleContextMenuClick(info, tab) {
  switch (info.menuItemId) {
  case "send-link":
    await sendToSwiftGetX({
      url: info.linkUrl,
      suggestedFilename: filenameFromURL(info.linkUrl),
      sourcePageTitle: tab?.title,
      sourcePageUrl: tab?.url,
      source: "context-menu-link"
    }, { allowSetup: true, forceSetupOpen: true });
    break;
  case "send-page":
    await sendToSwiftGetX({
      url: info.pageUrl || tab?.url,
      suggestedFilename: tab?.title,
      sourcePageTitle: tab?.title,
      sourcePageUrl: tab?.url,
      source: "context-menu-page"
    }, { allowSetup: true, forceSetupOpen: true });
    break;
  case "send-selection":
    await sendToSwiftGetX({
      url: info.selectionText,
      suggestedFilename: tab?.title,
      sourcePageTitle: tab?.title,
      sourcePageUrl: tab?.url,
      source: "context-menu-selection"
    }, { allowSetup: true, forceSetupOpen: true });
    break;
  case "send-media":
    await sendToSwiftGetX({
      url: info.srcUrl,
      suggestedFilename: filenameFromURL(info.srcUrl),
      sourcePageTitle: tab?.title,
      sourcePageUrl: tab?.url,
      source: "context-menu-media"
    }, { allowSetup: true, forceSetupOpen: true });
    break;
  case "scan-page":
    await scanTabAndSend(tab);
    break;
  default:
    break;
  }
}

async function scanTabAndSend(tab) {
  if (!tab?.id) {
    markFailure(i18n("errorNoScannableTab"));
    return;
  }

  try {
    const injection = await chrome.scripting.executeScript({
      target: { tabId: tab.id },
      func: collectDownloadCandidates
    });
    const candidates = injection?.[0]?.result?.candidates || [];
    const sourceText = candidates.map((candidate) => candidate.url).join("\n");

    if (!sourceText) {
      markFailure(i18n("errorNoDownloadLinksOnPage"));
      return;
    }

    await sendToSwiftGetX({
      url: sourceText,
      suggestedFilename: tab.title,
      sourcePageTitle: tab.title,
      sourcePageUrl: tab.url,
      source: "context-menu-scan"
    }, { allowSetup: true });
  } catch (error) {
    markFailure(error.message || String(error));
  }
}

async function sendToSwiftGetX(payload, options = {}) {
  const allowSetup = options.allowSetup !== false;
  const url = (payload?.url || "").trim();
  if (!isSupportedSource(url)) {
    markFailure(i18n("errorNoDownloadAddress"));
    return {
      ok: false,
      message: i18n("errorNoDownloadAddress")
    };
  }

  const message = {
    action: "download",
    url,
    browser: "Chrome",
    suggestedFilename: payload.suggestedFilename || filenameFromURL(url),
    sourcePageTitle: payload.sourcePageTitle,
    sourcePageUrl: payload.sourcePageUrl,
    source: payload.source,
    context: buildBrowserContext(payload)
  };

  let result = await sendNativeMessage(message);
  if (result.runtimeError && allowSetup) {
    markFailure(result.message);
    const repairResult = await repairNativeHost(payload.source || "download", {
      forceOpen: Boolean(options.forceSetupOpen)
    });
    if (repairResult.ok) {
      result = await sendNativeMessage(message);
    } else {
      result = {
        ...result,
        message: repairResult.message || result.message
      };
    }
  }

  if (result.runtimeError) {
    markFailure(result.message);
    return {
      ok: false,
      message: result.message
    };
  }

  if (result.ok) {
    markSuccess();
  } else {
    markFailure(result.message || i18n("errorTaskRejected"));
    if (allowSetup) {
      repairNativeHost(payload.source || "download-rejected");
    }
  }

  return {
    ok: result.ok,
    message: result.message || (result.ok ? i18n("sentToSwiftGetX") : i18n("sendFailed"))
  };
}

function captureRequestBasics(details) {
  if (!isHTTPURL(details.url)) {
    return;
  }

  const context = lookupRecentRequestContext(details.url) || {};
  context.method = details.method || context.method || "GET";
  context.originalURL = context.originalURL || details.url;

  const bodyMetadata = bodyMetadataFromRequest(details);
  if (bodyMetadata) {
    context.bodyMetadata = bodyMetadata;
  }

  rememberRequestContext(details.url, context);
}

function captureRequestHeaders(details) {
  if (!isHTTPURL(details.url)) {
    return;
  }

  const context = lookupRecentRequestContext(details.url) || {};
  context.method = details.method || context.method || "GET";
  context.originalURL = context.originalURL || details.url;

  const headers = [];
  for (const header of details.requestHeaders || []) {
    const name = header.name || "";
    const lower = name.toLowerCase();
    if (!CONTEXT_HEADER_NAMES.has(lower)) {
      continue;
    }

    const value = header.value || "";
    if (!value) {
      continue;
    }

    headers.push({
      name,
      value,
      sensitive: SENSITIVE_HEADER_NAMES.has(lower)
    });

    if (lower === "referer") {
      context.referrer = value;
    } else if (lower === "user-agent") {
      context.userAgent = value;
    }
  }

  context.headers = mergeHeaders(context.headers || [], headers);
  rememberRequestContext(details.url, context);
}

function bodyMetadataFromRequest(details) {
  const requestBody = details.requestBody;
  if (!requestBody) {
    return undefined;
  }

  if (requestBody.formData) {
    const fieldCount = Object.keys(requestBody.formData).length;
    return {
      description: `form fields: ${fieldCount}`
    };
  }

  if (requestBody.raw?.length) {
    const byteCount = requestBody.raw.reduce((total, item) => total + (item.bytes?.byteLength || 0), 0);
    return {
      byteCount,
      description: "raw request body"
    };
  }

  return undefined;
}

function buildBrowserContext(payload) {
  const url = (payload?.url || "").trim();
  const isSingleHTTPSource = isHTTPURL(url) && !url.includes("\n");
  const recentContext = isSingleHTTPSource
    ? (lookupRecentRequestContext(payload.finalUrl) || lookupRecentRequestContext(payload.originalUrl) || lookupRecentRequestContext(url) || {})
    : {};
  const suggestedFilename = payload.suggestedFilename || filenameFromURL(url);

  return {
    ...recentContext,
    referrer: recentContext.referrer || payload.sourcePageUrl,
    userAgent: recentContext.userAgent,
    method: recentContext.method || "GET",
    headers: isSingleHTTPSource ? (recentContext.headers || []) : [],
    bodyMetadata: isSingleHTTPSource ? recentContext.bodyMetadata : undefined,
    finalURL: payload.finalUrl || recentContext.finalURL || (isSingleHTTPSource ? url : undefined),
    originalURL: payload.originalUrl || recentContext.originalURL || (isSingleHTTPSource ? url : undefined),
    suggestedFilename,
    sourcePageTitle: payload.sourcePageTitle,
    sourcePageURL: payload.sourcePageUrl,
    handoffSource: payload.source
  };
}

function mergeHeaders(existingHeaders, nextHeaders) {
  const merged = new Map();
  for (const header of [...existingHeaders, ...nextHeaders]) {
    merged.set(header.name.toLowerCase(), header);
  }
  return Array.from(merged.values());
}

function rememberRequestContext(url, context) {
  const key = contextKey(url);
  if (!key) {
    return;
  }

  pruneRecentRequestContexts();
  recentRequestContexts.set(key, {
    ...context,
    capturedAt: Date.now()
  });
}

function lookupRecentRequestContext(url) {
  const key = contextKey(url);
  if (!key) {
    return undefined;
  }

  const context = recentRequestContexts.get(key);
  if (!context) {
    return undefined;
  }

  if (Date.now() - Number(context.capturedAt || 0) > RECENT_REQUEST_CONTEXT_TTL_MS) {
    recentRequestContexts.delete(key);
    return undefined;
  }

  const { capturedAt, ...payload } = context;
  return payload;
}

function pruneRecentRequestContexts() {
  const now = Date.now();
  for (const [key, context] of recentRequestContexts.entries()) {
    if (now - Number(context.capturedAt || 0) > RECENT_REQUEST_CONTEXT_TTL_MS) {
      recentRequestContexts.delete(key);
    }
  }

  while (recentRequestContexts.size > RECENT_REQUEST_CONTEXT_LIMIT) {
    const firstKey = recentRequestContexts.keys().next().value;
    if (!firstKey) {
      break;
    }
    recentRequestContexts.delete(firstKey);
  }
}

function contextKey(value) {
  if (!value) {
    return undefined;
  }

  try {
    const url = new URL(value);
    url.hash = "";
    return url.toString();
  } catch {
    return undefined;
  }
}

function isHTTPURL(value) {
  try {
    const url = new URL(value);
    return url.protocol === "http:" || url.protocol === "https:";
  } catch {
    return false;
  }
}

function scheduleNativeHealthChecks() {
  chrome.alarms.create(NATIVE_HEALTH_CHECK_ALARM, {
    periodInMinutes: NATIVE_HEALTH_CHECK_PERIOD_MINUTES
  });
}

function runNativeHealthCheck(reason) {
  getLocalStorage({ [NATIVE_SETUP_PAIRED_KEY]: false })
    .then((stored) => ensureNativeHostHealthy({
      allowSetup: Boolean(stored[NATIVE_SETUP_PAIRED_KEY]),
      reason
    }))
    .catch((error) => {
      console.warn(`SwiftGetX health check: ${error.message || String(error)}`);
    });
}

async function ensureNativeHostHealthy(options = {}) {
  const allowSetup = options.allowSetup !== false;
  const ping = await pingSwiftGetX();
  if (ping.ok) {
    await setNativePairingConfirmed();
    return ping;
  }

  if (!allowSetup) {
    return ping;
  }

  const repairResult = await repairNativeHost(options.reason || "health-check", {
    forceOpen: Boolean(options.forceSetupOpen)
  });
  return repairResult.ok || repairResult.setupOpened || repairResult.setupThrottled ? repairResult : ping;
}

async function repairNativeHost(reason, options = {}) {
  if (!activeNativeRepair) {
    activeNativeRepair = (async () => {
      const setupResult = await openBrowserSetup(reason, {
        forceOpen: Boolean(options.forceOpen)
      });
      if (!setupResult.ok) {
        return setupResult;
      }

      const result = await waitForNativeHost(NATIVE_SETUP_RETRY_TIMEOUT_MS);
      if (result.ok) {
        await setNativePairingConfirmed();
        return result;
      }

      return {
        ...result,
        setupOpened: Boolean(setupResult.opened),
        setupThrottled: Boolean(setupResult.throttled),
        message: setupResult.throttled
          ? i18n("setupPairingRequested")
          : i18n("setupPairingOpened"),
        detailMessage: result.message
      };
    })().finally(() => {
      activeNativeRepair = undefined;
    });
  }

  return activeNativeRepair;
}

async function openBrowserSetup(reason = "repair", options = {}) {
  const now = Date.now();
  const stored = await getLocalStorage({
    [NATIVE_SETUP_LAST_OPENED_KEY]: 0
  });
  const lastOpenedAt = Number(stored[NATIVE_SETUP_LAST_OPENED_KEY] || 0);
  if (!options.forceOpen && now - lastOpenedAt < NATIVE_SETUP_THROTTLE_MS) {
    return {
      ok: true,
      throttled: true
    };
  }

  await setLocalStorage({
    [NATIVE_SETUP_LAST_OPENED_KEY]: now
  });

  const setupURL = new URL("swiftgetx://browser-setup");
  setupURL.searchParams.set("browser", "Chrome");
  setupURL.searchParams.set("extensionID", chrome.runtime.id);
  setupURL.searchParams.set("version", EXTENSION_VERSION);
  setupURL.searchParams.set("reason", reason);

  return new Promise((resolve) => {
    chrome.tabs.create({ url: setupURL.toString(), active: Boolean(options.forceOpen) }, () => {
      const runtimeError = chrome.runtime.lastError;
      if (runtimeError) {
        console.warn(`SwiftGetX setup: ${runtimeError.message}`);
        resolve({
          ok: false,
          message: runtimeError.message
        });
        return;
      }

      resolve({
        ok: true,
        opened: true
      });
    });
  });
}

function sendNativeMessage(message) {
  return new Promise((resolve) => {
    chrome.runtime.sendNativeMessage(NATIVE_HOST_NAME, message, (response) => {
      const runtimeError = chrome.runtime.lastError;
      if (runtimeError) {
        resolve({
          ok: false,
          runtimeError: true,
          message: runtimeError.message
        });
        return;
      }

      const ok = response?.ok !== false;
      resolve({
        ok,
        runtimeError: false,
        message: response?.message || (ok ? i18n("connected") : i18n("nativeHostReturnedError")),
        version: response?.version,
        response
      });
    });
  });
}

async function waitForNativeHost(timeoutMs) {
  const deadline = Date.now() + timeoutMs;
  let lastResult = {
    ok: false,
    message: i18n("nativeHostNoResponse")
  };

  while (Date.now() <= deadline) {
    const result = await pingSwiftGetX();
    if (result.ok) {
      return result;
    }

    lastResult = result;
    await delay(NATIVE_SETUP_RETRY_INTERVAL_MS);
  }

  return lastResult;
}

async function pingSwiftGetX() {
  const result = await sendNativeMessage({
    action: "ping"
  });

  return {
    ok: result.ok,
    message: result.message,
    version: result.version
  };
}

function getLocalStorage(defaults) {
  return new Promise((resolve) => {
    chrome.storage.local.get(defaults, resolve);
  });
}

function setLocalStorage(values) {
  return new Promise((resolve) => {
    chrome.storage.local.set(values, resolve);
  });
}

function setNativePairingConfirmed() {
  return setLocalStorage({
    [NATIVE_SETUP_PAIRED_KEY]: true
  });
}

function delay(ms) {
  return new Promise((resolve) => {
    setTimeout(resolve, ms);
  });
}

function getOptions() {
  return new Promise((resolve) => {
    chrome.storage.local.get(DEFAULT_OPTIONS, (options) => {
      resolve({ ...DEFAULT_OPTIONS, ...options });
    });
  });
}

async function refreshOptions() {
  currentOptions = await getOptions();
}

function callDownloads(method, ...args) {
  return new Promise((resolve) => {
    chrome.downloads[method](...args, () => {
      const runtimeError = chrome.runtime.lastError;
      if (runtimeError) {
        console.warn(`SwiftGetX downloads.${method}: ${runtimeError.message}`);
      }
      resolve(!runtimeError);
    });
  });
}

function isSupportedSource(value) {
  return DOWNLOAD_SOURCE_PATTERN.test(value || "");
}

function filenameFromURL(value) {
  try {
    const url = new URL(value);
    const lastSegment = url.pathname.split("/").filter(Boolean).pop();
    return lastSegment ? decodeURIComponent(lastSegment) : undefined;
  } catch {
    return undefined;
  }
}

function filenameFromPath(value) {
  if (!value) {
    return undefined;
  }

  const lastSegment = value.split(/[\\/]/).filter(Boolean).pop();
  return lastSegment || undefined;
}

function markSuccess() {
  setBadge("OK", "#1f8f4d");
}

function markFailure(message) {
  console.warn(`SwiftGetX: ${message}`);
  setBadge("!", "#c43d30");
}

function setBadge(text, color) {
  chrome.action.setBadgeText({ text });
  chrome.action.setBadgeBackgroundColor({ color });
  setTimeout(() => chrome.action.setBadgeText({ text: "" }), 2500);
}

function collectDownloadCandidates() {
  const extensions = [
    "7z", "apk", "bz2", "crx", "dmg", "exe", "flac", "gz", "iso", "m4a",
    "mkv", "mov", "mp3", "mp4", "msi", "pdf", "pkg", "rar", "tar",
    "torrent", "wav", "webm", "xz", "zip"
  ];
  const extensionPattern = new RegExp(`\\.(${extensions.join("|")})([?#].*)?$`, "i");
  const candidates = [];
  const seen = new Set();

  for (const link of document.querySelectorAll("a[href]")) {
    const href = link.href;
    const hasDownloadAttribute = link.hasAttribute("download");
    const looksDownloadable = href.startsWith("magnet:")
      || extensionPattern.test(new URL(href, document.baseURI).pathname)
      || hasDownloadAttribute;

    if (!looksDownloadable || seen.has(href)) {
      continue;
    }

    seen.add(href);
    candidates.push({
      title: (link.textContent || link.getAttribute("download") || href).trim().slice(0, 120),
      url: href
    });
  }

  return {
    pageTitle: document.title,
    pageUrl: location.href,
    candidates: candidates.slice(0, 100)
  };
}
