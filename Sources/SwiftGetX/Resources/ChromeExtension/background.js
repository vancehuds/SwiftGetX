const NATIVE_HOST_NAME = "com.swiftgetx.native";
const DEFAULT_OPTIONS = {
  takeoverDownloads: true,
  takeoverDownloadsUserSet: false
};
const DOWNLOAD_SOURCE_PATTERN = /(magnet:\?|https?:\/\/|[^\s<>\]]+\.torrent(?:[?#][^\s<>\]]*)?)/i;
let currentOptions = { ...DEFAULT_OPTIONS };

const MENU_ITEMS = [
  {
    id: "send-link",
    title: "使用 SwiftGetX 下载链接",
    contexts: ["link"]
  },
  {
    id: "send-page",
    title: "使用 SwiftGetX 下载当前页面",
    contexts: ["page"]
  },
  {
    id: "send-selection",
    title: "使用 SwiftGetX 下载选中文本",
    contexts: ["selection"]
  },
  {
    id: "send-media",
    title: "使用 SwiftGetX 下载媒体",
    contexts: ["image", "video", "audio"]
  },
  {
    id: "scan-page",
    title: "扫描页面下载链接到 SwiftGetX",
    contexts: ["page"]
  }
];

chrome.runtime.onInstalled.addListener(() => {
  chrome.contextMenus.removeAll(() => {
    for (const item of MENU_ITEMS) {
      chrome.contextMenus.create(item);
    }
  });

  chrome.storage.local.get(DEFAULT_OPTIONS, (options) => {
    const nextOptions = { ...DEFAULT_OPTIONS, ...options };
    if (!options.takeoverDownloadsUserSet) {
      nextOptions.takeoverDownloads = true;
    }
    chrome.storage.local.set(nextOptions);
  });
});

refreshOptions();

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

chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (!message) {
    return false;
  }

  if (message.type === "swiftgetx-download") {
    sendToSwiftGetX(message.payload)
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
    pingSwiftGetX()
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
      suggestedFilename: filenameFromPath(downloadItem.filename) || filenameFromURL(url),
      sourcePageUrl: downloadItem.referrer,
      source: "download-takeover"
    };

    // Send to SwiftGetX FIRST — only cancel Chrome download after confirmation.
    const result = await sendToSwiftGetX(payload);

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
    });
    break;
  case "send-page":
    await sendToSwiftGetX({
      url: info.pageUrl || tab?.url,
      suggestedFilename: tab?.title,
      sourcePageTitle: tab?.title,
      sourcePageUrl: tab?.url,
      source: "context-menu-page"
    });
    break;
  case "send-selection":
    await sendToSwiftGetX({
      url: info.selectionText,
      suggestedFilename: tab?.title,
      sourcePageTitle: tab?.title,
      sourcePageUrl: tab?.url,
      source: "context-menu-selection"
    });
    break;
  case "send-media":
    await sendToSwiftGetX({
      url: info.srcUrl,
      suggestedFilename: filenameFromURL(info.srcUrl),
      sourcePageTitle: tab?.title,
      sourcePageUrl: tab?.url,
      source: "context-menu-media"
    });
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
    markFailure("没有可扫描的标签页");
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
      markFailure("当前页面没有发现下载链接");
      return;
    }

    await sendToSwiftGetX({
      url: sourceText,
      suggestedFilename: tab.title,
      sourcePageTitle: tab.title,
      sourcePageUrl: tab.url,
      source: "context-menu-scan"
    });
  } catch (error) {
    markFailure(error.message || String(error));
  }
}

async function sendToSwiftGetX(payload) {
  const url = (payload?.url || "").trim();
  if (!isSupportedSource(url)) {
    markFailure("没有可发送的下载地址");
    return {
      ok: false,
      message: "没有可发送的下载地址"
    };
  }

  return new Promise((resolve) => {
    chrome.runtime.sendNativeMessage(NATIVE_HOST_NAME, {
      action: "download",
      url,
      browser: "Chrome",
      suggestedFilename: payload.suggestedFilename || filenameFromURL(url),
      sourcePageTitle: payload.sourcePageTitle,
      sourcePageUrl: payload.sourcePageUrl,
      source: payload.source
    }, (response) => {
      const runtimeError = chrome.runtime.lastError;
      if (runtimeError) {
        markFailure(runtimeError.message);
        resolve({
          ok: false,
          message: runtimeError.message
        });
        return;
      }

      const ok = response?.ok !== false;
      if (ok) {
        markSuccess();
      } else {
        markFailure(response?.message || "SwiftGetX 未接受该任务");
      }
      resolve({
        ok,
        message: response?.message || (ok ? "已发送到 SwiftGetX" : "发送失败")
      });
    });
  });
}

function pingSwiftGetX() {
  return new Promise((resolve) => {
    chrome.runtime.sendNativeMessage(NATIVE_HOST_NAME, {
      action: "ping"
    }, (response) => {
      const runtimeError = chrome.runtime.lastError;
      if (runtimeError) {
        resolve({
          ok: false,
          message: runtimeError.message
        });
        return;
      }

      resolve({
        ok: response?.ok !== false,
        message: response?.message || "connected",
        version: response?.version
      });
    });
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
