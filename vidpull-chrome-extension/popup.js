// VidPull Chrome Extension - Popup Script

document.addEventListener('DOMContentLoaded', () => {
  const extensionEnabledCheckbox = document.getElementById('extensionEnabled');
  const overlaysVisibleCheckbox = document.getElementById('overlaysVisible');
  const shortcutLink = document.getElementById('shortcutLink');

  // Load current settings
  chrome.storage.sync.get(['extensionEnabled', 'overlaysVisible'], (result) => {
    extensionEnabledCheckbox.checked = result.extensionEnabled !== false;
    overlaysVisibleCheckbox.checked = result.overlaysVisible !== false;
  });

  // Save settings on change
  extensionEnabledCheckbox.addEventListener('change', () => {
    chrome.storage.sync.set({ extensionEnabled: extensionEnabledCheckbox.checked });
  });

  overlaysVisibleCheckbox.addEventListener('change', () => {
    chrome.storage.sync.set({ overlaysVisible: overlaysVisibleCheckbox.checked });
  });

  // Open Chrome keyboard shortcuts page
  shortcutLink.addEventListener('click', (e) => {
    e.preventDefault();
    chrome.tabs.create({ url: 'chrome://extensions/shortcuts' });
  });
});
