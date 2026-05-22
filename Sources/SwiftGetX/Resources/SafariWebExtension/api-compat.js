function createSwiftGetXExtensionAPI() {
  const rawAPI = globalThis.browser || globalThis.chrome;
  const prefersPromiseAPI = Boolean(globalThis.browser);
  const runtimeState = { lastError: undefined };

  if (!rawAPI) {
    throw new Error("SwiftGetX requires a Safari Web Extension API namespace.");
  }

  const missingEvent = {
    addListener() {},
    removeListener() {},
    hasListener() {
      return false;
    }
  };

  const event = (candidate) => candidate || missingEvent;
  const errorMessage = (error) => error?.message || String(error || "Extension API unavailable");

  const finishCallback = (callback, error, values = []) => {
    runtimeState.lastError = error ? { message: errorMessage(error) } : undefined;
    try {
      callback(...values);
    } finally {
      setTimeout(() => {
        runtimeState.lastError = undefined;
      }, 0);
    }
  };

  const wrapAsync = (target, methodName) => (...incomingArgs) => {
    const args = [...incomingArgs];
    const callback = typeof args[args.length - 1] === "function" ? args.pop() : undefined;
    const method = target?.[methodName];

    if (typeof method !== "function") {
      const error = new Error(`Unsupported Safari Web Extension API: ${methodName}`);
      if (callback) {
        finishCallback(callback, error);
        return undefined;
      }
      return Promise.reject(error);
    }

    if (prefersPromiseAPI) {
      let promise;
      try {
        promise = Promise.resolve(method.apply(target, args));
      } catch (error) {
        promise = Promise.reject(error);
      }

      if (callback) {
        promise.then(
          (value) => finishCallback(callback, undefined, [value]),
          (error) => finishCallback(callback, error)
        );
        return undefined;
      }
      return promise;
    }

    if (callback) {
      try {
        return method.apply(target, [
          ...args,
          (...values) => finishCallback(callback, rawAPI.runtime?.lastError, values)
        ]);
      } catch (error) {
        finishCallback(callback, error);
        return undefined;
      }
    }

    return new Promise((resolve, reject) => {
      try {
        method.apply(target, [
          ...args,
          (value) => {
            const runtimeError = rawAPI.runtime?.lastError;
            if (runtimeError) {
              reject(new Error(errorMessage(runtimeError)));
            } else {
              resolve(value);
            }
          }
        ]);
      } catch (error) {
        reject(error);
      }
    });
  };

  const noopAsync = () => Promise.resolve();
  const action = rawAPI.action || rawAPI.browserAction || {};
  const downloads = rawAPI.downloads || {};

  return {
    runtime: {
      get id() {
        return rawAPI.runtime?.id || "";
      },
      get lastError() {
        return runtimeState.lastError || rawAPI.runtime?.lastError;
      },
      getManifest: () => rawAPI.runtime.getManifest(),
      onInstalled: event(rawAPI.runtime?.onInstalled),
      onStartup: event(rawAPI.runtime?.onStartup),
      onMessage: event(rawAPI.runtime?.onMessage),
      sendMessage: wrapAsync(rawAPI.runtime, "sendMessage"),
      sendNativeMessage: wrapAsync(rawAPI.runtime, "sendNativeMessage")
    },
    i18n: {
      getMessage: (...args) => rawAPI.i18n?.getMessage?.(...args) || "",
      getUILanguage: () => rawAPI.i18n?.getUILanguage?.() || "en"
    },
    storage: {
      local: {
        get: wrapAsync(rawAPI.storage?.local, "get"),
        set: wrapAsync(rawAPI.storage?.local, "set")
      },
      onChanged: event(rawAPI.storage?.onChanged)
    },
    contextMenus: {
      create: rawAPI.contextMenus?.create
        ? (...args) => rawAPI.contextMenus.create(...args)
        : noopAsync,
      removeAll: wrapAsync(rawAPI.contextMenus, "removeAll"),
      onClicked: event(rawAPI.contextMenus?.onClicked)
    },
    tabs: {
      query: wrapAsync(rawAPI.tabs, "query"),
      create: wrapAsync(rawAPI.tabs, "create")
    },
    scripting: {
      executeScript: wrapAsync(rawAPI.scripting, "executeScript")
    },
    alarms: {
      create: rawAPI.alarms?.create
        ? (...args) => rawAPI.alarms.create(...args)
        : noopAsync,
      onAlarm: event(rawAPI.alarms?.onAlarm)
    },
    webRequest: {
      onBeforeRequest: event(rawAPI.webRequest?.onBeforeRequest),
      onBeforeSendHeaders: event(rawAPI.webRequest?.onBeforeSendHeaders)
    },
    downloads: {
      download: downloads.download ? wrapAsync(downloads, "download") : undefined,
      cancel: downloads.cancel ? wrapAsync(downloads, "cancel") : undefined,
      erase: downloads.erase ? wrapAsync(downloads, "erase") : undefined,
      onDeterminingFilename: event(downloads.onDeterminingFilename)
    },
    action: {
      setBadgeText: action.setBadgeText
        ? (...args) => action.setBadgeText(...args)
        : noopAsync,
      setBadgeBackgroundColor: action.setBadgeBackgroundColor
        ? (...args) => action.setBadgeBackgroundColor(...args)
        : noopAsync
    }
  };
}
