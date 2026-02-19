// Prevent duplicate listener registration when script is re-injected
if (!window.__ohmyjson_registered) {
  window.__ohmyjson_registered = true;

  chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
    if (message.action !== "copyAndOpen") return;

    const text = message.text;
    if (!text) return;

    copyToClipboard(text).then(() => {
      openOhMyJson(message.installUrl);
    });
  });
}

// Copy text to clipboard with fallback
function copyToClipboard(text) {
  return navigator.clipboard.writeText(text).catch(() => {
    // Clipboard API failed — fall back to execCommand
    const textarea = document.createElement("textarea");
    textarea.value = text;
    textarea.style.position = "fixed";
    textarea.style.left = "-9999px";
    document.body.appendChild(textarea);
    textarea.select();
    document.execCommand("copy");
    document.body.removeChild(textarea);
  });
}

// Open OhMyJson via URL scheme, guide to install if app is missing
function openOhMyJson(installUrl) {
  const appOpenTimeout = setTimeout(() => {
    if (
      installUrl &&
      confirm(
        "OhMyJson app is not installed.\nWould you like to go to the installation page?"
      )
    ) {
      window.open(installUrl, "_blank");
    }
  }, 2500);

  // If the app opens, the page loses focus — cancel the install prompt
  window.addEventListener("blur", () => clearTimeout(appOpenTimeout), {
    once: true,
  });

  const link = document.createElement("a");
  link.href = "ohmyjson://open";
  link.style.display = "none";
  document.body.appendChild(link);
  link.click();
  document.body.removeChild(link);
}
