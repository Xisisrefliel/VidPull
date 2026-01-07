// VidPull Chrome Extension - Background Service Worker

// Handle keyboard shortcut command
chrome.commands.onCommand.addListener((command) => {
  if (command === 'toggle-overlay') {
    // Send message to all tabs to toggle overlay
    chrome.tabs.query({}, (tabs) => {
      tabs.forEach(tab => {
        if (tab.id) {
          chrome.tabs.sendMessage(tab.id, { action: 'toggle-overlay' }).catch(() => {
            // Ignore errors for tabs where content script isn't loaded
          });
        }
      });
    });
  }
});

// Initialize default settings on install
chrome.runtime.onInstalled.addListener((details) => {
  if (details.reason === 'install') {
    chrome.storage.sync.set({
      overlaysVisible: true,
      extensionEnabled: true
    });
  }
});
