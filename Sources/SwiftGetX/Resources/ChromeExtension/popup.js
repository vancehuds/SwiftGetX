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
const sendCandidatesButton = document.getElementById("send-candidates");
const connectionIndicator = document.getElementById("connection-indicator");
const connectionLabel = document.getElementById("connection-label");
const connectionDetail = document.getElementById("connection-detail");

document.getElementById("send-current").addEventListener("click", sendCurrentPage);
document.getElementById("send-selection").addEventListener("click", sendSelection);
document.getElementById("scan-links").addEventListener("click", scanLinks);
sendCandidatesButton.addEventListener("click", sendAllCandidates);
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
  try {
    const injection = await chrome.scripting.executeScript({
      target: { tabId: activeTab.id },
      func: collectDownloadCandidates
    });
    candidates = injection?.[0]?.result?.candidates || [];
  } catch {
    candidates = [];
    candidatePanel.hidden = true;
    setStatus(i18n("statusNoPermission"), "error");
    return;
  }
  renderCandidates();

  if (candidates.length === 0) {
    setStatus(i18n("statusNotFound"), "error");
  } else {
    setStatus(i18n("statusCount", String(candidates.length)), "ok");
  }
}

async function sendAllCandidates() {
  if (candidates.length === 0) {
    setStatus(i18n("statusNoLinks"), "error");
    return;
  }

  await sendDownload({
    url: candidates.map((candidate) => candidate.url).join("\n"),
    suggestedFilename: activeTab?.title,
    sourcePageTitle: activeTab?.title,
    sourcePageUrl: activeTab?.url,
    source: "popup-scan"
  });
}

async function sendDownload(payload) {
  setStatus(i18n("statusSending"), "");
  const response = await chrome.runtime.sendMessage({
    type: "swiftgetx-download",
    payload,
    forceSetupOpen: true
  });

  if (response?.ok) {
    setStatus(i18n("statusSent"), "ok");
  } else {
    setStatus(i18n("statusFailed"), "error");
  }
}

function renderCandidates() {
  candidatePanel.hidden = candidates.length === 0;
  candidateCount.textContent = i18n("linkCount", String(candidates.length));
  candidateList.replaceChildren();

  for (const candidate of candidates.slice(0, 12)) {
    const item = document.createElement("li");
    const title = document.createElement("div");
    const url = document.createElement("div");

    title.className = "candidate-title";
    title.textContent = candidate.title || filenameFromURL(candidate.url) || i18n("downloadLink");
    url.className = "candidate-url";
    url.textContent = candidate.url;

    item.append(title, url);
    candidateList.append(item);
  }
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

function localizeStaticText() {
  document.documentElement.lang = chrome.i18n.getUILanguage().replace("_", "-");
  for (const element of document.querySelectorAll("[data-i18n]")) {
    element.textContent = i18n(element.dataset.i18n);
  }
  document.title = i18n("appName");
  candidateCount.textContent = i18n("linkCount", "0");
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
    "7z", "apk", "bz2", "crx", "dmg", "exe", "flac", "gz", "iso", "m4a",
    "mkv", "mov", "mp3", "mp4", "msi", "pdf", "pkg", "rar", "tar",
    "torrent", "wav", "webm", "xz", "zip"
  ];
  const extensionPattern = new RegExp(`\\.(${extensions.join("|")})([?#].*)?$`, "i");
  const candidates = [];
  const seen = new Set();

  for (const link of document.querySelectorAll("a[href]")) {
    const href = link.href;
    const url = new URL(href, document.baseURI);
    const title = (link.textContent || link.getAttribute("download") || href).trim();
    const hasDownloadAttribute = link.hasAttribute("download");
    const looksDownloadable = href.startsWith("magnet:")
      || extensionPattern.test(url.pathname)
      || hasDownloadAttribute;

    if (!looksDownloadable || seen.has(href)) {
      continue;
    }

    seen.add(href);
    candidates.push({
      title: title.slice(0, 120),
      url: href
    });
  }

  return {
    candidates: candidates.slice(0, 100)
  };
}
