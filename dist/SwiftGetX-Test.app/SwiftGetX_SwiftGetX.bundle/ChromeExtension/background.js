chrome.runtime.onInstalled.addListener(() => {
  chrome.contextMenus.create({
    id: "send-to-swiftgetx",
    title: "使用 SwiftGetX 下载",
    contexts: ["link"]
  });
});

chrome.contextMenus.onClicked.addListener((info) => {
  if (info.menuItemId !== "send-to-swiftgetx" || !info.linkUrl) {
    return;
  }

  chrome.runtime.sendNativeMessage("com.swiftgetx.native", {
    action: "download",
    url: info.linkUrl,
    browser: "Chrome"
  });
});
