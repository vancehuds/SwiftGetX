browser.runtime.onInstalled.addListener(() => {
  browser.contextMenus.create({
    id: "send-to-swiftgetx",
    title: browser.i18n.getMessage("contextSendLink") || "Download link with SwiftGetX",
    contexts: ["link"]
  });
});

browser.contextMenus.onClicked.addListener((info) => {
  if (info.menuItemId !== "send-to-swiftgetx" || !info.linkUrl) {
    return;
  }

  browser.runtime.sendNativeMessage("com.swiftgetx.native", {
    action: "download",
    url: info.linkUrl,
    browser: "Safari"
  });
});
