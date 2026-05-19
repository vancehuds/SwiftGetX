const NATIVE_HOST_NAME = "com.swiftgetx.native";
const DEFAULT_OPTIONS = {
  takeoverDownloads: false
};
const DOWNLOAD_SOURCE_PATTERN = /(magnet:\?|https?:\/\/|[^\s<>\]]+\.torrent(?:[?#][^\s<>\]]*)?)/i;

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
    chrome.storage.local.set({ ...DEFAULT_OPTIONS, ...options });
  });
});

chrome.contextMenus.onClicked.addListener((info, tab) => {
  handleContextMenuClick(info, tab);
});

chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (!message || message.type !== "swiftgetx-download") {
    return false;
  }

  sendToSwiftGetX(message.payload)
    .then(sendResponse)
    .catch((error) => {
      sendResponse({
        ok: false,
        message: error.message || String(error)
      });
    });
  return true;
});

chrome.downloads.onCreated.addListener((downloadItem) => {
  chrome.storage.local.get(DEFAULT_OPTIONS, async (options) => {
    if (!options.takeoverDownloads || !isSupportedSource(downloadItem.url)) {
      return;
    }

    const result = await sendToSwiftGetX({
      url: downloadItem.url,
      suggestedFilename: downloadItem.filename,
      sourcePageUrl: downloadItem.referrer,
      source: "download-takeover"
    });

    if (result.ok) {
      chrome.downloads.cancel(downloadItem.id);
    }
  });
});

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
