const DEFAULT_OPTIONS = {
  takeoverDownloads: true,
  takeoverDownloadsUserSet: false
};

let activeTab;
let candidates = [];

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
  const tabs = await chrome.tabs.query({ active: true, currentWindow: true });
  activeTab = tabs[0];
  activeTabLabel.textContent = activeTab?.title || "当前标签页";

  chrome.storage.local.get(DEFAULT_OPTIONS, (options) => {
    takeoverDownloads.checked = Boolean(options.takeoverDownloads);
  });

  checkConnection({ allowSetup: false });
}

async function sendCurrentPage() {
  if (!activeTab?.url) {
    setStatus("无页面", "error");
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
    setStatus("无选区", "error");
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
    setStatus("无权限", "error");
    return;
  }

  if (!selection) {
    setStatus("无选区", "error");
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
    setStatus("无法扫描", "error");
    return;
  }

  setStatus("扫描中", "");
  try {
    const injection = await chrome.scripting.executeScript({
      target: { tabId: activeTab.id },
      func: collectDownloadCandidates
    });
    candidates = injection?.[0]?.result?.candidates || [];
  } catch {
    candidates = [];
    candidatePanel.hidden = true;
    setStatus("无权限", "error");
    return;
  }
  renderCandidates();

  if (candidates.length === 0) {
    setStatus("未发现", "error");
  } else {
    setStatus(`${candidates.length} 个`, "ok");
  }
}

async function sendAllCandidates() {
  if (candidates.length === 0) {
    setStatus("无链接", "error");
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
  setStatus("发送中", "");
  const response = await chrome.runtime.sendMessage({
    type: "swiftgetx-download",
    payload,
    forceSetupOpen: true
  });

  if (response?.ok) {
    setStatus("已发送", "ok");
  } else {
    setStatus("失败", "error");
  }
}

function renderCandidates() {
  candidatePanel.hidden = candidates.length === 0;
  candidateCount.textContent = `${candidates.length} 个链接`;
  candidateList.replaceChildren();

  for (const candidate of candidates.slice(0, 12)) {
    const item = document.createElement("li");
    const title = document.createElement("div");
    const url = document.createElement("div");

    title.className = "candidate-title";
    title.textContent = candidate.title || filenameFromURL(candidate.url) || "下载链接";
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
  setConnectionState("checking", "检查中…", "");

  try {
    const response = await chrome.runtime.sendMessage({
      type: "swiftgetx-ping",
      allowSetup: options.allowSetup !== false,
      forceSetupOpen: Boolean(options.forceSetupOpen),
      reason: "manual-check"
    });

    if (response?.ok) {
      const version = response.version ? `v${response.version}` : "";
      setConnectionState("ok", "已连接", version ? `Native Host ${version}` : "Native Host 运行正常");
    } else if (response?.setupOpened || response?.setupThrottled) {
      setConnectionState(
        "checking",
        "等待配对",
        response.message || "已打开 SwiftGetX，请在软件中允许插件配对后再次检查。"
      );
    } else {
      setConnectionState("error", "连接失败", response?.message || "Native Host 未响应");
    }
  } catch (error) {
    setConnectionState("error", "连接失败", error.message || "无法与 Native Host 通信");
  }
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
