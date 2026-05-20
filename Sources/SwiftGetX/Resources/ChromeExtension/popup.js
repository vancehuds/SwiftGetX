const DEFAULT_OPTIONS = {
  takeoverDownloads: true,
  takeoverDownloadsUserSet: false
};

let activeTab;
let candidates = [];

const i18n = (key, substitutions) => chrome.i18n.getMessage(key, substitutions) || key;
const activeTabLabel = document.getElementById("active-tab");
const statusLabel = document.getElementById("status");
const takeoverDownloads = document.getElementById("takeover-downloads");
const candidatePanel = document.getElementById("candidate-panel");
const candidateCount = document.getElementById("candidate-count");
const candidateList = document.getElementById("candidate-list");
const selectAllCandidatesButton = document.getElementById("select-all-candidates");
const sendCandidatesButton = document.getElementById("send-candidates");
const connectionIndicator = document.getElementById("connection-indicator");
const connectionLabel = document.getElementById("connection-label");
const connectionDetail = document.getElementById("connection-detail");
const errorPanel = document.getElementById("error-panel");
const errorDetail = document.getElementById("error-detail");

document.getElementById("send-current").addEventListener("click", sendCurrentPage);
document.getElementById("send-selection").addEventListener("click", sendSelection);
document.getElementById("scan-links").addEventListener("click", scanLinks);
selectAllCandidatesButton.addEventListener("click", toggleAllCandidates);
sendCandidatesButton.addEventListener("click", sendSelectedCandidates);
document.getElementById("check-connection").addEventListener("click", () => {
  checkConnection({ allowSetup: true, forceSetupOpen: true });
});
takeoverDownloads.addEventListener("change", () => {
  chrome.storage.local.set({
    takeoverDownloads: takeoverDownloads.checked,
    takeoverDownloadsUserSet: true
  });
});

init();

async function init() {
  localizeStaticText();
  const tabs = await chrome.tabs.query({ active: true, currentWindow: true });
  activeTab = tabs[0];
  activeTabLabel.textContent = activeTab?.title || i18n("currentTab");

  chrome.storage.local.get(DEFAULT_OPTIONS, (options) => {
    takeoverDownloads.checked = Boolean(options.takeoverDownloads);
  });

  await loadLastError();
  checkConnection({ allowSetup: false });
}

async function sendCurrentPage() {
  if (!activeTab?.url) {
    setStatus(i18n("statusNoPage"), "error");
    return;
  }

  await sendDownload({
    url: activeTab.url,
    suggestedFilename: activeTab.title,
    sourcePageTitle: activeTab.title,
    sourcePageUrl: activeTab.url,
    source: "popup-current-page"
  });
}

async function sendSelection() {
  if (!activeTab?.id) {
    setStatus(i18n("statusNoSelection"), "error");
    return;
  }

  let selection = "";
  try {
    const injection = await chrome.scripting.executeScript({
      target: { tabId: activeTab.id },
      func: () => String(window.getSelection() || "").trim()
    });
    selection = injection?.[0]?.result || "";
  } catch {
    setStatus(i18n("statusNoPermission"), "error");
    return;
  }

  if (!selection) {
    setStatus(i18n("statusNoSelection"), "error");
    return;
  }

  await sendDownload({
    url: selection,
    suggestedFilename: activeTab.title,
    sourcePageTitle: activeTab.title,
    sourcePageUrl: activeTab.url,
    source: "popup-selection"
  });
}

async function scanLinks() {
  if (!activeTab?.id) {
    setStatus(i18n("statusCannotScan"), "error");
    return;
  }

  setStatus(i18n("statusScanning"), "");
  candidatePanel.hidden = true;
  try {
    const injection = await chrome.scripting.executeScript({
      target: { tabId: activeTab.id },
      func: collectDownloadCandidates
    });
    const found = injection?.[0]?.result?.candidates || [];
    const response = await chrome.runtime.sendMessage({
      type: "swiftgetx-enrich-candidates",
      candidates: found
    });
    candidates = (response?.candidates || found).map((candidate) => ({
      ...candidate,
      selected: candidate.downloadable !== false
    }));
    if (!response?.ok && response?.message) {
      showError(response.message);
    }
  } catch (error) {
    candidates = [];
    candidatePanel.hidden = true;
    setStatus(i18n("statusNoPermission"), "error");
    showError(error.message || String(error));
    return;
  }

  renderCandidates();

  if (candidates.length === 0) {
    setStatus(i18n("statusNotFound"), "error");
  } else {
    setStatus(i18n("statusCount", String(candidates.length)), "ok");
  }
}

async function sendSelectedCandidates() {
  const selected = selectedCandidates();
  if (selected.length === 0) {
    setStatus(i18n("statusNoSelectedLinks"), "error");
    return;
  }

  await sendDownload({
    url: selected.map((candidate) => candidate.url).join("\n"),
    suggestedFilename: activeTab?.title,
    sourcePageTitle: activeTab?.title,
    sourcePageUrl: activeTab?.url,
    source: "popup-scan"
  });
}

async function sendDownload(payload) {
  setStatus(i18n("statusSending"), "");
  hideError();

  let response;
  try {
    response = await chrome.runtime.sendMessage({
      type: "swiftgetx-download",
      payload,
      forceSetupOpen: true
    });
  } catch (error) {
    setStatus(i18n("statusFailed"), "error");
    showError(error.message || String(error));
    return;
  }

  if (response?.ok) {
    setStatus(i18n("statusSent"), "ok");
    hideError();
  } else {
    setStatus(i18n("statusFailed"), "error");
    showError(response?.message || i18n("sendFailed"));
    await loadLastError();
  }
}

function selectedCandidates() {
  return candidates.filter((candidate) => candidate.selected);
}

function toggleAllCandidates() {
  const shouldSelect = selectedCandidates().length !== candidates.length;
  candidates = candidates.map((candidate) => ({
    ...candidate,
    selected: shouldSelect
  }));
  renderCandidates();
}

function renderCandidates() {
  candidatePanel.hidden = candidates.length === 0;
  candidateList.replaceChildren();

  for (const [index, candidate] of candidates.entries()) {
    const item = document.createElement("li");
    const label = document.createElement("label");
    const checkbox = document.createElement("input");
    const content = document.createElement("span");
    const title = document.createElement("span");
    const meta = document.createElement("span");
    const url = document.createElement("span");

    label.className = "candidate-row";
    checkbox.type = "checkbox";
    checkbox.checked = Boolean(candidate.selected);
    checkbox.addEventListener("change", () => {
      candidates[index] = {
        ...candidate,
        selected: checkbox.checked
      };
      updateCandidateSummary();
    });

    content.className = "candidate-content";
    title.className = "candidate-title";
    title.textContent = candidate.title || candidate.suggestedFilename || filenameFromURL(candidate.url) || i18n("downloadLink");
    meta.className = "candidate-meta";
    meta.textContent = candidateMetadata(candidate);
    url.className = "candidate-url";
    url.textContent = candidate.url;

    content.append(title, meta, url);
    label.append(checkbox, content);
    item.append(label);
    candidateList.append(item);
  }

  updateCandidateSummary();
}

function updateCandidateSummary() {
  const selected = selectedCandidates().length;
  candidateCount.textContent = i18n("selectedCount", [String(selected), String(candidates.length)]);
  selectAllCandidatesButton.textContent = selected === candidates.length && candidates.length > 0
    ? i18n("selectNone")
    : i18n("selectAll");
  sendCandidatesButton.disabled = selected === 0;
}

function candidateMetadata(candidate) {
  const parts = [];
  if (candidate.reason) {
    parts.push(candidateReasonLabel(candidate.reason));
  }
  if (candidate.contentLength) {
    parts.push(formatBytes(candidate.contentLength));
  }
  if (candidate.contentType) {
    parts.push(candidate.contentType.split(";")[0]);
  }
  if (candidate.probeError) {
    parts.push(i18n("metadataLimited"));
  }
  return parts.join(" - ") || i18n("metadataPending");
}

function candidateReasonLabel(reason) {
  const key = `candidateReason_${String(reason).replace(/[^a-z0-9]+/gi, "_")}`;
  const localized = i18n(key);
  return localized === key ? reason : localized;
}

function formatBytes(value) {
  const bytes = Number(value);
  if (!Number.isFinite(bytes) || bytes <= 0) {
    return "";
  }

  const units = ["B", "KB", "MB", "GB", "TB"];
  let size = bytes;
  let unitIndex = 0;
  while (size >= 1024 && unitIndex < units.length - 1) {
    size /= 1024;
    unitIndex += 1;
  }
  return `${size >= 10 || unitIndex === 0 ? size.toFixed(0) : size.toFixed(1)} ${units[unitIndex]}`;
}

function setStatus(text, state) {
  statusLabel.textContent = text;
  statusLabel.className = `status ${state || ""}`.trim();
}

async function checkConnection(options = {}) {
  setConnectionState("checking", i18n("connectionChecking"), "");

  try {
    const response = await chrome.runtime.sendMessage({
      type: "swiftgetx-ping",
      allowSetup: options.allowSetup !== false,
      forceSetupOpen: Boolean(options.forceSetupOpen),
      reason: "manual-check"
    });

    if (response?.ok) {
      const version = response.version ? `v${response.version}` : "";
      setConnectionState("ok", i18n("connectionConnected"), version ? `Native Host ${version}` : i18n("nativeHostHealthy"));
    } else if (response?.setupOpened || response?.setupThrottled) {
      setConnectionState(
        "checking",
        i18n("connectionWaitingPairing"),
        response.message || i18n("pairingOpenedDetail")
      );
    } else {
      setConnectionState("error", i18n("connectionFailed"), response?.message || i18n("nativeHostNoResponse"));
    }
  } catch (error) {
    setConnectionState("error", i18n("connectionFailed"), error.message || i18n("nativeHostCannotCommunicate"));
  }
}

async function loadLastError() {
  try {
    const response = await chrome.runtime.sendMessage({
      type: "swiftgetx-last-error"
    });
    if (response?.ok && response.error?.message) {
      showError(response.error.message);
    }
  } catch {
    // The visible connection status covers native-host communication failures.
  }
}

function showError(message) {
  errorDetail.textContent = message;
  errorPanel.hidden = false;
}

function hideError() {
  errorDetail.textContent = "";
  errorPanel.hidden = true;
}

function localizeStaticText() {
  document.documentElement.lang = chrome.i18n.getUILanguage().replace("_", "-");
  for (const element of document.querySelectorAll("[data-i18n]")) {
    element.textContent = i18n(element.dataset.i18n);
  }
  document.title = i18n("appName");
  candidateCount.textContent = i18n("selectedCount", ["0", "0"]);
}

function setConnectionState(state, label, detail) {
  connectionIndicator.className = `connection-indicator ${state}`;
  connectionLabel.textContent = label;
  connectionDetail.textContent = detail;
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
    if (candidates.length >= 100) {
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
    candidates: candidates.slice(0, 100)
  };
}
