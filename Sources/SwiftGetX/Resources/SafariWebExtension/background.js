importScripts("api-compat.js");

const api = createSwiftGetXExtensionAPI();
const NATIVE_HOST_NAME = "com.swiftgetx.native";
const EXTENSION_VERSION = api.runtime.getManifest().version;
const BROWSER_PROTOCOL_VERSION = 1;
const MIN_NATIVE_HOST_VERSION = "0.2.0";
const NATIVE_HEALTH_CHECK_ALARM = "swiftgetx-native-health-check";
const NATIVE_HEALTH_CHECK_PERIOD_MINUTES = 30;
const NATIVE_SETUP_RETRY_TIMEOUT_MS = 8000;
const NATIVE_SETUP_RETRY_INTERVAL_MS = 1000;
const NATIVE_SETUP_PAIRED_KEY = "nativeHostPairingConfirmed";
const LAST_ERROR_KEY = "lastSwiftGetXError";
const RECENT_REQUEST_CONTEXT_TTL_MS = 5 * 60 * 1000;
const RECENT_REQUEST_CONTEXT_LIMIT = 200;
const TAKEOVER_BYPASS_TTL_MS = 30 * 1000;
const HEAD_PROBE_TIMEOUT_MS = 2500;
const MIN_TAKEOVER_BYTES = 1024 * 1024;
const DOWNLOAD_EXTENSIONS = [
  "7z", "aac", "apk", "bz2", "crx", "dmg", "exe", "flac", "gz", "iso", "m3u8",
  "m4a", "m4v", "mkv", "mov", "mp3", "mp4", "mpd", "msi", "ogg", "pdf", "pkg",
  "rar", "tar", "torrent", "wav", "webm", "xz", "zip"
];
const TAKEOVER_BLOCKED_EXTENSIONS = [
  "css", "gif", "htm", "html", "ico", "jpeg", "jpg", "js", "json", "png", "svg",
  "webp", "xml"
];
const TAKEOVER_BLOCKED_HOST_PARTS = [
  "adservice.",
  "doubleclick.net",
  "googlesyndication.com",
  "googleadservices.com",
  "clients2.google.com",
  "update.googleapis.com",
  "redirector.gvt1.com",
  "edgedl.me.gvt1.com",
  "dl.google.com"
];
const DEFAULT_OPTIONS = {
  takeoverDownloads: true,
  takeoverDownloadsUserSet: false,
  takeoverMinBytes: MIN_TAKEOVER_BYTES,
  takeoverAllowedExtensions: DOWNLOAD_EXTENSIONS,
  takeoverBlockedExtensions: TAKEOVER_BLOCKED_EXTENSIONS,
  takeoverBlockedHosts: TAKEOVER_BLOCKED_HOST_PARTS
};
const DOWNLOAD_SOURCE_PATTERN = /(magnet:\?|https?:\/\/|[^\s<>\]]+\.torrent(?:[?#][^\s<>\]]*)?)/i;
const DOWNLOAD_EXTENSION_PATTERN = new RegExp(`\\.(${DOWNLOAD_EXTENSIONS.join("|")})([?#].*)?$`, "i");
const STATIC_EXTENSION_PATTERN = new RegExp(`\\.(${TAKEOVER_BLOCKED_EXTENSIONS.join("|")})([?#].*)?$`, "i");
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
let takeoverBypassURLs = new Map();
const i18n = (key, substitutions) => api.i18n.getMessage(key, substitutions) || key;

const MENU_ITEMS = [
  {
    id: "send-link",
    titleKey: "contextSendLink",
    contexts: ["link"]
  },
  {
    id: "browser-download-link",
    titleKey: "contextDownloadInBrowser",
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

api.runtime.onInstalled.addListener(() => {
  api.contextMenus.removeAll(() => {
    for (const item of MENU_ITEMS) {
      api.contextMenus.create({
        id: item.id,
        title: i18n(item.titleKey),
        contexts: item.contexts
      });
    }
  });

  api.storage.local.get(DEFAULT_OPTIONS, (options) => {
    const nextOptions = { ...DEFAULT_OPTIONS, ...options };
    if (!options.takeoverDownloadsUserSet) {
      nextOptions.takeoverDownloads = true;
    }
    api.storage.local.set(nextOptions);
  });

  scheduleNativeHealthChecks();
  runNativeHealthCheck("installed");
});

api.runtime.onStartup.addListener(() => {
  scheduleNativeHealthChecks();
  runNativeHealthCheck("startup");
});

api.alarms.onAlarm.addListener((alarm) => {
  if (alarm.name === NATIVE_HEALTH_CHECK_ALARM) {
    runNativeHealthCheck("alarm");
  }
});

refreshOptions();
scheduleNativeHealthChecks();
runNativeHealthCheck("service-worker");

api.storage.onChanged.addListener((changes, areaName) => {
  if (areaName !== "local") {
    return;
  }

  if (Object.keys(changes).some((key) => key.startsWith("takeover"))) {
    refreshOptions();
  }
});

api.contextMenus.onClicked.addListener((info, tab) => {
  handleContextMenuClick(info, tab);
});

api.webRequest.onBeforeRequest.addListener(
  captureRequestBasics,
  { urls: ["<all_urls>"] },
  ["requestBody"]
);

api.webRequest.onBeforeSendHeaders.addListener(
  captureRequestHeaders,
  { urls: ["<all_urls>"] },
  ["requestHeaders", "extraHeaders"]
);

api.runtime.onMessage.addListener((message, sender, sendResponse) => {
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
        markFailure(error.message || String(error));
        sendResponse({
          ok: false,
          message: error.message || String(error)
        });
      });
    return true;
  }

  if (message.type === "swiftgetx-enrich-candidates") {
    enrichCandidates(message.candidates || [])
      .then((candidates) => sendResponse({ ok: true, candidates }))
      .catch((error) => {
        sendResponse({
          ok: false,
          message: error.message || String(error),
          candidates: message.candidates || []
        });
      });
    return true;
  }

  if (message.type === "swiftgetx-last-error") {
    getLocalStorage({ [LAST_ERROR_KEY]: null })
      .then((stored) => sendResponse({
        ok: true,
        error: stored[LAST_ERROR_KEY] || null
      }))
      .catch((error) => sendResponse({
        ok: false,
        message: error.message || String(error)
      }));
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

api.downloads.onDeterminingFilename.addListener((downloadItem, suggest) => {
  handleDownloadDeterminingFilename(downloadItem, suggest).catch((error) => {
    markFailure(error.message || String(error));
  });
  return true;
});

async function handleDownloadDeterminingFilename(downloadItem, suggest) {
  let didSuggest = false;
  const allowSafariFilename = () => {
    if (!didSuggest) {
      didSuggest = true;
      suggest();
    }
  };

  try {
    if (!shouldTakeOverDownload(downloadItem)) {
      allowSafariFilename();
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

    // Send to SwiftGetX FIRST — only cancel Safari download after confirmation.
    const result = await sendToSwiftGetX(payload, { allowSetup: false });

    if (!result.ok) {
      // Native host unreachable or rejected — fall back to Safari download.
      allowSafariFilename();
      return;
    }

    // SwiftGetX accepted the task — cancel and erase the Safari download.
    await callDownloads("cancel", downloadItem.id);
    await callDownloads("erase", { id: downloadItem.id });
  } catch (error) {
    // On any unexpected error, let Safari proceed with the download.
    allowSafariFilename();
    throw error;
  }
}

function shouldTakeOverDownload(downloadItem) {
  return takeoverDecision(downloadItem).takeOver;
}

function takeoverDecision(downloadItem) {
  if (!currentOptions.takeoverDownloads) {
    return { takeOver: false, reason: "disabled" };
  }

  const url = downloadSourceURL(downloadItem).trim();
  if (!url || !isHTTPURL(url)) {
    return { takeOver: false, reason: "unsupported-protocol" };
  }

  if (isTakeoverBypassed(url) || isTakeoverBypassed(downloadItem.url)) {
    return { takeOver: false, reason: "temporary-browser-rule" };
  }

  const parsed = parsedURL(url);
  if (!parsed || hostMatchesBlockedRule(parsed.hostname)) {
    return { takeOver: false, reason: "blocked-site" };
  }

  const extension = extensionFromURL(url) || extensionFromFilename(downloadItem.filename);
  const mime = String(downloadItem.mime || "").toLowerCase();
  if (extension && blockedExtensionSet().has(extension)) {
    return { takeOver: false, reason: "blocked-extension" };
  }

  if (isStaticContentType(mime) || isPageLikeDownload(mime, extension)) {
    return { takeOver: false, reason: "browser-file" };
  }

  const hasAllowedExtension = extension ? allowedExtensionSet().has(extension) : false;
  const hasDownloadMime = isDownloadContentType(mime);
  if (!hasAllowedExtension && !hasDownloadMime) {
    return { takeOver: false, reason: "not-download-like" };
  }

  const totalBytes = downloadSize(downloadItem);
  const minBytes = Math.max(0, Number(currentOptions.takeoverMinBytes || MIN_TAKEOVER_BYTES));
  const isManifestOrTorrent = extension === "torrent" || extension === "m3u8" || extension === "mpd";
  if (totalBytes > 0 && totalBytes < minBytes && !isManifestOrTorrent) {
    return { takeOver: false, reason: "small-file" };
  }

  return { takeOver: true, reason: hasAllowedExtension ? "extension" : "content-type" };
}

function downloadSourceURL(downloadItem) {
  return downloadItem.finalUrl || downloadItem.url || "";
}

function parsedURL(value) {
  try {
    return new URL(value);
  } catch {
    return undefined;
  }
}

function extensionFromURL(value) {
  const url = parsedURL(value);
  if (!url) {
    return undefined;
  }

  const match = /\.([a-z0-9]{1,12})$/i.exec(url.pathname);
  return match?.[1]?.toLowerCase();
}

function extensionFromFilename(value) {
  const name = filenameFromPath(value);
  const match = name ? /\.([a-z0-9]{1,12})$/i.exec(name) : undefined;
  return match?.[1]?.toLowerCase();
}

function normalizedArrayOption(value, fallback) {
  return Array.isArray(value) ? value : fallback;
}

function allowedExtensionSet() {
  return new Set(normalizedArrayOption(
    currentOptions.takeoverAllowedExtensions,
    DOWNLOAD_EXTENSIONS
  ).map((item) => String(item).toLowerCase()));
}

function blockedExtensionSet() {
  return new Set(normalizedArrayOption(
    currentOptions.takeoverBlockedExtensions,
    TAKEOVER_BLOCKED_EXTENSIONS
  ).map((item) => String(item).toLowerCase()));
}

function hostMatchesBlockedRule(hostname) {
  const host = String(hostname || "").toLowerCase();
  return normalizedArrayOption(
    currentOptions.takeoverBlockedHosts,
    TAKEOVER_BLOCKED_HOST_PARTS
  ).some((part) => host.includes(String(part).toLowerCase()));
}

function rememberTakeoverBypass(url) {
  pruneTakeoverBypasses();
  const key = contextKey(url) || url;
  takeoverBypassURLs.set(key, Date.now() + TAKEOVER_BYPASS_TTL_MS);
}

function isTakeoverBypassed(url) {
  pruneTakeoverBypasses();
  const key = contextKey(url) || url;
  return takeoverBypassURLs.has(key);
}

function pruneTakeoverBypasses() {
  const now = Date.now();
  for (const [key, expiresAt] of takeoverBypassURLs.entries()) {
    if (Number(expiresAt) <= now) {
      takeoverBypassURLs.delete(key);
    }
  }
}

function downloadSize(downloadItem) {
  return Number(downloadItem.fileSize || downloadItem.totalBytes || downloadItem.bytesReceived || 0);
}

function isStaticContentType(mime) {
  return /^(image|text\/css|application\/javascript|text\/javascript)\b/i.test(mime || "");
}

function isPageLikeDownload(mime, extension) {
  if (extension === "html" || extension === "htm") {
    return true;
  }
  return /^(text\/html|application\/xhtml\+xml)\b/i.test(mime || "");
}

function isDownloadContentType(mime) {
  const value = String(mime || "").toLowerCase();
  if (!value) {
    return false;
  }

  return value.includes("application/octet-stream")
    || value.includes("application/x-bittorrent")
    || value.includes("application/pdf")
    || value.includes("application/zip")
    || value.includes("application/x-7z")
    || value.includes("application/x-rar")
    || value.includes("application/gzip")
    || value.includes("application/x-tar")
    || value.includes("application/vnd.apple.installer+xml")
    || value.includes("application/vnd.microsoft.portable-executable")
    || value.includes("application/dash+xml")
    || value.includes("application/vnd.apple.mpegurl")
    || value.includes("mpegurl")
    || value.startsWith("audio/")
    || value.startsWith("video/");
}

async function handleContextMenuClick(info, tab) {
  switch (info.menuItemId) {
  case "browser-download-link":
    if (!info.linkUrl) {
      markFailure(i18n("errorNoDownloadAddress"));
      break;
    }
    rememberTakeoverBypass(info.linkUrl);
    if (await callDownloads("download", { url: info.linkUrl })) {
      markSuccess();
    } else {
      markFailure(i18n("sendFailed"));
    }
    break;
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
    const injection = await api.scripting.executeScript({
      target: { tabId: tab.id },
      func: collectDownloadCandidates
    });
    const result = injection?.[0]?.result || {};
    const candidates = (await enrichCandidates(result.candidates || []))
      .filter((candidate) => candidate.downloadable !== false);
    const sourceText = candidates.map((candidate) => candidate.url).join("\n");

    if (!sourceText) {
      markFailure(i18n("errorNoDownloadLinksOnPage"));
      return;
    }

    await sendToSwiftGetX({
      url: sourceText,
      suggestedFilename: result.pageTitle || tab.title,
      sourcePageTitle: result.pageTitle || tab.title,
      sourcePageUrl: result.pageUrl || tab.url,
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
    markFailure(i18n("errorNoDownloadAddress"), {
      action: "validate-source",
      source: payload?.source || "unknown"
    });
    return {
      ok: false,
      message: i18n("errorNoDownloadAddress")
    };
  }

  const message = {
    action: "download",
    url,
    browser: "Safari",
    suggestedFilename: payload.suggestedFilename || filenameFromURL(url),
    sourcePageTitle: payload.sourcePageTitle,
    sourcePageUrl: payload.sourcePageUrl,
    source: payload.source,
    context: buildBrowserContext(payload),
    extensionVersion: EXTENSION_VERSION,
    minimumNativeHostVersion: MIN_NATIVE_HOST_VERSION,
    protocolVersion: BROWSER_PROTOCOL_VERSION
  };

  let result = await sendNativeMessage(message);
  if (result.runtimeError && allowSetup) {
    markFailure(result.message, result.errorDetail);
    const fallbackResult = await openDownloadDeepLink(message);
    if (fallbackResult.ok) {
      markSuccess();
      return fallbackResult;
    }

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
    markFailure(result.message, result.errorDetail);
    return {
      ok: false,
      message: result.message,
      errorDetail: result.errorDetail
    };
  }

  if (result.ok) {
    markSuccess();
  } else {
    markFailure(result.message || i18n("errorTaskRejected"), result.errorDetail);
    if (allowSetup && result.compatible !== false) {
      repairNativeHost(payload.source || "download-rejected");
    }
  }

  return {
    ok: result.ok,
    message: result.message || (result.ok ? i18n("sentToSwiftGetX") : i18n("sendFailed")),
    compatible: result.compatible,
    compatibilityMessage: result.compatibilityMessage,
    errorDetail: result.errorDetail,
    response: result.response
  };
}

async function enrichCandidates(candidates) {
  const uniqueCandidates = [];
  const seen = new Set();

  for (const candidate of candidates.slice(0, 150)) {
    const url = String(candidate?.url || "").trim();
    if (!isSupportedCandidateSource(url)) {
      continue;
    }

    const key = contextKey(url) || url;
    if (seen.has(key)) {
      continue;
    }

    seen.add(key);
    uniqueCandidates.push({
      title: String(candidate.title || "").trim().slice(0, 160),
      url,
      kind: candidate.kind || "link",
      reason: candidate.reason,
      hasDownloadAttribute: Boolean(candidate.hasDownloadAttribute)
    });
  }

  const enriched = await Promise.all(uniqueCandidates.map(enrichCandidate));
  return enriched
    .filter((candidate) => candidate.downloadable !== false)
    .slice(0, 100);
}

async function enrichCandidate(candidate) {
  const url = candidate.url;
  const isMagnet = url.toLowerCase().startsWith("magnet:?");
  const metadata = isHTTPURL(url) ? await probeHTTPMetadata(url) : {};
  const finalURL = metadata.finalURL || url;
  const contentType = metadata.contentType || "";
  const contentDispositionFilename = filenameFromContentDisposition(metadata.contentDisposition);
  const suggestedFilename = contentDispositionFilename
    || filenameFromURL(finalURL)
    || filenameFromURL(url);
  const extension = extensionFromURL(finalURL)
    || extensionFromURL(url)
    || extensionFromFilename(suggestedFilename);
  const blockedExtension = extension ? blockedExtensionSet().has(extension) : false;
  const allowedExtension = extension ? allowedExtensionSet().has(extension) : false;
  const manifestExtension = extension === "m3u8" || extension === "mpd";
  const dispositionDownload = isDownloadDisposition(metadata.contentDisposition);
  const contentDownload = isDownloadContentType(contentType);
  const staticContent = isStaticContentType(contentType) || STATIC_EXTENSION_PATTERN.test(finalURL);
  const pageLikeContent = isPageLikeDownload(contentType, extension);
  let reason = candidate.reason;

  if (isMagnet) {
    reason = "magnet";
  } else if (dispositionDownload) {
    reason = "content-disposition";
  } else if (manifestExtension) {
    reason = "media-manifest";
  } else if (candidate.hasDownloadAttribute) {
    reason = "download-attribute";
  } else if (allowedExtension) {
    reason = "extension";
  } else if (contentDownload) {
    reason = "content-type";
  } else if (candidate.kind === "media") {
    reason = "media-source";
  }

  const downloadable = Boolean(
    isMagnet
      || dispositionDownload
      || manifestExtension
      || candidate.hasDownloadAttribute
      || contentDownload
      || allowedExtension
      || candidate.reason === "download-hint"
      || candidate.kind === "media"
  ) && !(blockedExtension && !dispositionDownload) && !(staticContent && !dispositionDownload);
  const safeDownloadable = downloadable && !(pageLikeContent && !dispositionDownload);

  return {
    ...candidate,
    title: candidate.title || suggestedFilename || i18n("downloadLink"),
    finalUrl: finalURL,
    suggestedFilename,
    contentType,
    contentLength: metadata.contentLength,
    contentDisposition: metadata.contentDisposition,
    reason: reason || "link",
    downloadable: safeDownloadable,
    probeError: metadata.probeError
  };
}

function isSupportedCandidateSource(value) {
  if (!value) {
    return false;
  }

  const lower = value.toLowerCase();
  return lower.startsWith("magnet:?") || isHTTPURL(value);
}

async function probeHTTPMetadata(url) {
  let headMetadata;
  try {
    const response = await fetchWithTimeout(url, {
      method: "HEAD",
      credentials: "include",
      redirect: "follow"
    });
    headMetadata = metadataFromResponse(response);
    if (hasUsefulMetadata(headMetadata) || ![405, 501].includes(response.status)) {
      return headMetadata;
    }
  } catch (error) {
    headMetadata = { probeError: error.message || String(error) };
  }

  try {
    const response = await fetchWithTimeout(url, {
      method: "GET",
      credentials: "include",
      redirect: "follow",
      headers: {
        Range: "bytes=0-0"
      }
    });
    const metadata = metadataFromResponse(response);
    try {
      await response.body?.cancel();
    } catch {
      // Best effort only; the Range request is used as a light metadata probe.
    }
    return metadata;
  } catch (error) {
    return {
      ...(headMetadata || {}),
      probeError: error.message || String(error)
    };
  }
}

function fetchWithTimeout(url, options) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), HEAD_PROBE_TIMEOUT_MS);
  return fetch(url, {
    ...options,
    signal: controller.signal
  }).finally(() => {
    clearTimeout(timeout);
  });
}

function metadataFromResponse(response) {
  return {
    finalURL: response.url,
    contentDisposition: response.headers.get("content-disposition") || "",
    contentType: response.headers.get("content-type") || "",
    contentLength: numericHeader(response.headers.get("content-length"))
  };
}

function hasUsefulMetadata(metadata) {
  return Boolean(
    metadata.contentDisposition
      || metadata.contentType
      || Number(metadata.contentLength || 0) > 0
  );
}

function numericHeader(value) {
  const number = Number(value);
  return Number.isFinite(number) && number >= 0 ? number : undefined;
}

function isDownloadDisposition(value) {
  const lower = String(value || "").toLowerCase();
  return lower.includes("attachment") || lower.includes("filename=");
}

function filenameFromContentDisposition(value) {
  if (!value) {
    return undefined;
  }

  const filenameStar = /filename\*\s*=\s*(?:UTF-8'')?([^;]+)/i.exec(value);
  if (filenameStar?.[1]) {
    return decodeHeaderFilename(filenameStar[1]);
  }

  const filename = /filename\s*=\s*("?)([^";]+)\1/i.exec(value);
  return filename?.[2] ? decodeHeaderFilename(filename[2]) : undefined;
}

function decodeHeaderFilename(value) {
  const trimmed = String(value || "").trim().replace(/^"|"$/g, "");
  try {
    return decodeURIComponent(trimmed);
  } catch {
    return trimmed;
  }
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
    handoffSource: payload.source,
    handoffSourceText: url
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
  api.alarms.create(NATIVE_HEALTH_CHECK_ALARM, {
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
  return {
    ok: false,
    message: i18n("safariPairingUnavailable")
  };
}

async function openDownloadDeepLink(message) {
  if (!message?.url || message.source === "download-takeover") {
    return {
      ok: false,
      message: i18n("sendFailed")
    };
  }

  const downloadURL = new URL("swiftgetx://download");
  downloadURL.searchParams.set("url", message.url);
  appendSearchParam(downloadURL, "browser", message.browser);
  appendSearchParam(downloadURL, "filename", message.suggestedFilename);
  appendSearchParam(downloadURL, "source", message.source);
  appendSearchParam(downloadURL, "sourcePageTitle", message.sourcePageTitle);
  appendSearchParam(downloadURL, "sourcePageUrl", message.sourcePageUrl);

  if (downloadURL.toString().length > 7900) {
    return {
      ok: false,
      message: i18n("nativeHostCannotCommunicate")
    };
  }

  return new Promise((resolve) => {
    api.tabs.create({ url: downloadURL.toString(), active: false }, () => {
      const runtimeError = api.runtime.lastError;
      if (runtimeError) {
        resolve({
          ok: false,
          message: runtimeError.message
        });
        return;
      }

      resolve({
        ok: true,
        message: i18n("sentToSwiftGetX"),
        compatible: true,
        fallback: "deep-link"
      });
    });
  });
}

function appendSearchParam(url, name, value) {
  if (value) {
    url.searchParams.set(name, value);
  }
}

function sendNativeMessage(message) {
  return new Promise((resolve) => {
    api.runtime.sendNativeMessage(NATIVE_HOST_NAME, message, (response) => {
      const runtimeError = api.runtime.lastError;
      if (runtimeError) {
        const errorDetail = nativeMessageErrorDetail(message, {
          runtimeError: runtimeError.message
        });
        resolve({
          ok: false,
          runtimeError: true,
          message: runtimeError.message,
          errorDetail
        });
        return;
      }

      const compatibility = nativeHostCompatibility(response);
      const ok = response?.ok !== false && compatibility.compatible;
      const resultMessage = compatibility.message || response?.message || (ok ? i18n("connected") : i18n("nativeHostReturnedError"));
      resolve({
        ok,
        runtimeError: false,
        message: resultMessage,
        version: response?.version,
        protocolVersion: response?.protocolVersion,
        minimumExtensionVersion: response?.minimumExtensionVersion,
        minimumNativeHostVersion: response?.minimumNativeHostVersion,
        compatible: compatibility.compatible,
        compatibilityMessage: compatibility.message,
        errorDetail: nativeMessageErrorDetail(message, {
          message: resultMessage,
          response,
          compatible: compatibility.compatible,
          compatibilityMessage: compatibility.message
        }),
        response
      });
    });
  });
}

function nativeMessageErrorDetail(message, result = {}) {
  const response = result.response || {};
  return compactObject({
    action: message?.action || "unknown",
    hostName: NATIVE_HOST_NAME,
    runtimeError: result.runtimeError,
    message: result.message,
    version: response.version,
    protocolVersion: response.protocolVersion,
    compatible: result.compatible ?? response.compatible,
    compatibilityMessage: result.compatibilityMessage || response.compatibilityMessage,
    minimumExtensionVersion: response.minimumExtensionVersion,
    minimumNativeHostVersion: response.minimumNativeHostVersion,
    rejectedReason: response.rejectedReason,
    requestID: response.requestID
  });
}

function compactObject(value) {
  const output = {};
  for (const [key, rawValue] of Object.entries(value || {})) {
    if (rawValue === undefined || rawValue === null || rawValue === "") {
      continue;
    }
    output[key] = typeof rawValue === "string" ? rawValue.slice(0, 500) : rawValue;
  }
  return output;
}

function nativeHostCompatibility(response) {
  if (!response) {
    return {
      compatible: false,
      message: i18n("nativeHostNoResponse")
    };
  }

  if (response.compatible === false) {
    return {
      compatible: false,
      message: response.compatibilityMessage || response.message || i18n("nativeHostIncompatible")
    };
  }

  if (!isVersionAtLeast(response.version, MIN_NATIVE_HOST_VERSION)) {
    return {
      compatible: false,
      message: i18n("nativeHostTooOld", [response.version || "unknown", MIN_NATIVE_HOST_VERSION])
    };
  }

  if (Number(response.protocolVersion) !== BROWSER_PROTOCOL_VERSION) {
    return {
      compatible: false,
      message: i18n("nativeHostProtocolIncompatible", [
        String(response.protocolVersion ?? "missing"),
        String(BROWSER_PROTOCOL_VERSION)
      ])
    };
  }

  if (response.minimumExtensionVersion
      && !isVersionAtLeast(EXTENSION_VERSION, response.minimumExtensionVersion)) {
    return {
      compatible: false,
      message: i18n("extensionTooOld", [EXTENSION_VERSION, response.minimumExtensionVersion])
    };
  }

  return {
    compatible: true,
    message: response.compatibilityMessage
  };
}

function isVersionAtLeast(version, minimumVersion) {
  const left = versionComponents(version);
  const right = versionComponents(minimumVersion);
  if (!left || !right) {
    return false;
  }

  const count = Math.max(left.length, right.length);
  for (let index = 0; index < count; index += 1) {
    const leftValue = left[index] || 0;
    const rightValue = right[index] || 0;
    if (leftValue > rightValue) {
      return true;
    }
    if (leftValue < rightValue) {
      return false;
    }
  }
  return true;
}

function versionComponents(version) {
  const text = String(version || "").trim().replace(/^v/i, "");
  if (!text) {
    return undefined;
  }

  const parts = text
    .split(/[^0-9]+/)
    .filter(Boolean)
    .slice(0, 3)
    .map((part) => Number.parseInt(part, 10));
  return parts.length > 0 && parts.every(Number.isFinite) ? parts : undefined;
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
    action: "ping",
    extensionVersion: EXTENSION_VERSION,
    minimumNativeHostVersion: MIN_NATIVE_HOST_VERSION,
    protocolVersion: BROWSER_PROTOCOL_VERSION
  });

  return {
    ok: result.ok,
    message: result.message,
    version: result.version,
    protocolVersion: result.protocolVersion,
    compatible: result.compatible,
    compatibilityMessage: result.compatibilityMessage
  };
}

function getLocalStorage(defaults) {
  return new Promise((resolve) => {
    api.storage.local.get(defaults, resolve);
  });
}

function setLocalStorage(values) {
  return new Promise((resolve) => {
    api.storage.local.set(values, resolve);
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
    api.storage.local.get(DEFAULT_OPTIONS, (options) => {
      resolve({ ...DEFAULT_OPTIONS, ...options });
    });
  });
}

async function refreshOptions() {
  currentOptions = await getOptions();
}

function callDownloads(method, ...args) {
  const downloadMethod = api.downloads?.[method];
  if (typeof downloadMethod !== "function") {
    return Promise.resolve(false);
  }

  return new Promise((resolve) => {
    downloadMethod(...args, () => {
      const runtimeError = api.runtime.lastError;
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
  setLocalStorage({ [LAST_ERROR_KEY]: null });
  setBadge("OK", "#1f8f4d");
}

function markFailure(message, detail = {}) {
  console.warn(`SwiftGetX: ${message}`);
  setLocalStorage({
    [LAST_ERROR_KEY]: {
      message: String(message || i18n("sendFailed")),
      detail: compactObject(detail),
      at: Date.now()
    }
  });
  setBadge("!", "#c43d30");
}

function setBadge(text, color) {
  api.action.setBadgeText({ text });
  api.action.setBadgeBackgroundColor({ color });
  setTimeout(() => api.action.setBadgeText({ text: "" }), 2500);
}

function collectDownloadCandidates() {
  const extensions = [
    "7z", "aac", "apk", "bz2", "crx", "dmg", "exe", "flac", "gz", "iso", "m3u8",
    "m4a", "m4v", "mkv", "mov", "mp3", "mp4", "mpd", "msi", "ogg", "pdf", "pkg",
    "rar", "tar", "torrent", "wav", "webm", "xz", "zip"
  ];
  const extensionPattern = new RegExp(`\\.(${extensions.join("|")})([?#].*)?$`, "i");
  const manifestPattern = /\.(m3u8|mpd)([?#].*)?$/i;
  const downloadHintPattern = /\b(download|direct|file|mirror|release|asset|archive|torrent|installer|package)\b/i;
  const mediaMimePattern = /\b(audio|video|mpegurl|dash\+xml|octet-stream|x-bittorrent)\b/i;
  const candidates = [];
  const seen = new Set();

  const addCandidate = (rawURL, title, details = {}) => {
    if (!rawURL) {
      return;
    }

    let href = rawURL;
    try {
      href = rawURL.startsWith("magnet:") ? rawURL : new URL(rawURL, document.baseURI).href;
    } catch {
      return;
    }

    if (seen.has(href)) {
      return;
    }

    seen.add(href);
    candidates.push({
      title: String(title || details.downloadName || href).trim().slice(0, 120),
      url: href,
      kind: details.kind || "link",
      reason: details.reason,
      hasDownloadAttribute: Boolean(details.hasDownloadAttribute)
    });
  };

  for (const link of document.querySelectorAll("a[href]")) {
    const href = link.href;
    const url = new URL(href, document.baseURI);
    const hasDownloadAttribute = link.hasAttribute("download");
    const title = (link.textContent || link.getAttribute("download") || href).trim();
    const rel = link.getAttribute("rel") || "";
    const type = link.getAttribute("type") || "";
    const looksDownloadable = href.startsWith("magnet:")
      || extensionPattern.test(url.pathname)
      || hasDownloadAttribute
      || mediaMimePattern.test(type)
      || downloadHintPattern.test(`${title} ${rel} ${link.className || ""} ${link.id || ""}`);

    if (!looksDownloadable) {
      continue;
    }

    let reason = "download-hint";
    if (href.startsWith("magnet:")) {
      reason = "magnet";
    } else if (manifestPattern.test(url.pathname)) {
      reason = "media-manifest";
    } else if (hasDownloadAttribute) {
      reason = "download-attribute";
    } else if (extensionPattern.test(url.pathname)) {
      reason = "extension";
    } else if (mediaMimePattern.test(type)) {
      reason = "content-type";
    }

    addCandidate(href, title, {
      kind: "link",
      reason,
      hasDownloadAttribute,
      downloadName: link.getAttribute("download") || ""
    });
  }

  for (const link of document.querySelectorAll("a[href]")) {
    if (candidates.length >= 80) {
      break;
    }

    const href = link.href;
    if (!/^https?:/i.test(href)) {
      continue;
    }

    addCandidate(href, (link.textContent || href).trim(), {
      kind: "link",
      reason: "link"
    });
  }

  for (const media of document.querySelectorAll("video[src], audio[src], source[src]")) {
    const src = media.currentSrc || media.src || media.getAttribute("src");
    const type = media.getAttribute("type") || "";
    let pathname = "";
    try {
      pathname = new URL(src, document.baseURI).pathname;
    } catch {
      pathname = src || "";
    }
    if (!manifestPattern.test(pathname) && !mediaMimePattern.test(type)) {
      continue;
    }

    addCandidate(src, media.getAttribute("title") || document.title || src, {
      kind: "media",
      reason: manifestPattern.test(pathname) ? "media-manifest" : "media-source"
    });
  }

  return {
    pageTitle: document.title,
    pageUrl: location.href,
    candidates: candidates.slice(0, 100)
  };
}
