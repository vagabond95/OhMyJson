const INSTALL_URL = "https://github.com/vagabond95/OhMyJson#installation";

// Register context menu when extension is installed
chrome.runtime.onInstalled.addListener(() => {
  chrome.contextMenus.create({
    id: "open-in-ohmyjson",
    title: "Open in OhMyJson",
    contexts: ["selection"],
  });
});

// Handle context menu click
chrome.contextMenus.onClicked.addListener((info, tab) => {
  if (info.menuItemId !== "open-in-ohmyjson") return;

  const selectedText = info.selectionText;
  if (!selectedText || selectedText.trim().length === 0) return;

  // Inject content script and execute copy+open
  chrome.scripting
    .executeScript({
      target: { tabId: tab.id },
      files: ["content.js"],
    })
    .then(() => {
      chrome.tabs.sendMessage(tab.id, {
        action: "copyAndOpen",
        text: selectedText,
        installUrl: INSTALL_URL,
      });
    })
    .catch((err) => {
      // chrome:// or edge:// pages don't allow script injection
      console.warn("OhMyJson: Cannot run on this page.", err.message);
    });
});
