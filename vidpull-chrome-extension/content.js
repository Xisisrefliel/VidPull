// VidPull Chrome Extension - Content Script
// Detects video elements and adds download overlay buttons

(function() {
  'use strict';

  const OVERLAY_CLASS = 'vidpull-overlay-button';
  const CONTAINER_CLASS = 'vidpull-overlay-container';
  const STORAGE_KEY_POSITION = 'vidpullButtonPosition';
  
  let overlaysVisible = true;
  let extensionEnabled = true;
  
  // Default position: top-right corner (as percentage offsets from top-left)
  let buttonPosition = { xPercent: 95, yPercent: 5 };

  // Known video platform patterns for extracting video URLs from embeds
  const EMBED_PATTERNS = [
    // YouTube
    { pattern: /youtube\.com\/embed\/([^?&/]+)/, buildUrl: (id) => `https://www.youtube.com/watch?v=${id}` },
    { pattern: /youtube-nocookie\.com\/embed\/([^?&/]+)/, buildUrl: (id) => `https://www.youtube.com/watch?v=${id}` },
    // Vimeo
    { pattern: /player\.vimeo\.com\/video\/(\d+)/, buildUrl: (id) => `https://vimeo.com/${id}` },
    // Dailymotion
    { pattern: /dailymotion\.com\/embed\/video\/([^?&/]+)/, buildUrl: (id) => `https://www.dailymotion.com/video/${id}` },
    // Twitch clips
    { pattern: /clips\.twitch\.tv\/embed\?.*?clip=([^&]+)/, buildUrl: (id) => `https://clips.twitch.tv/${id}` },
    // Twitch videos
    { pattern: /player\.twitch\.tv\/\?.*?video=v?(\d+)/, buildUrl: (id) => `https://www.twitch.tv/videos/${id}` },
    // Facebook
    { pattern: /facebook\.com\/plugins\/video\.php\?.*?href=([^&]+)/, buildUrl: (encoded) => decodeURIComponent(encoded) },
    // Twitter/X
    { pattern: /platform\.twitter\.com\/embed\/Tweet\.html\?.*?id=(\d+)/, buildUrl: (id) => `https://twitter.com/i/status/${id}` },
  ];

  // Load initial settings
  chrome.storage.sync.get(['overlaysVisible', 'extensionEnabled', STORAGE_KEY_POSITION], (result) => {
    overlaysVisible = result.overlaysVisible !== false;
    extensionEnabled = result.extensionEnabled !== false;
    
    if (result[STORAGE_KEY_POSITION]) {
      buttonPosition = result[STORAGE_KEY_POSITION];
    }
    
    if (extensionEnabled) {
      init();
    }
  });

  // Listen for settings changes
  chrome.storage.onChanged.addListener((changes, namespace) => {
    if (namespace === 'sync') {
      if (changes.overlaysVisible) {
        overlaysVisible = changes.overlaysVisible.newValue;
        updateOverlayVisibility();
      }
      if (changes.extensionEnabled) {
        extensionEnabled = changes.extensionEnabled.newValue;
        if (extensionEnabled) {
          init();
        } else {
          removeAllOverlays();
        }
      }
      if (changes[STORAGE_KEY_POSITION]) {
        buttonPosition = changes[STORAGE_KEY_POSITION].newValue;
        repositionAllOverlays();
      }
    }
  });

  // Listen for keyboard shortcut from background script
  chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
    if (message.action === 'toggle-overlay') {
      overlaysVisible = !overlaysVisible;
      chrome.storage.sync.set({ overlaysVisible });
      updateOverlayVisibility();
    }
  });

  function init() {
    findAndProcessVideos();
    findAndProcessIframes();
    observeDOM();
  }

  function findAndProcessVideos() {
    const videos = document.querySelectorAll('video');
    videos.forEach(video => attachOverlayToVideo(video));
  }

  function findAndProcessIframes() {
    const iframes = document.querySelectorAll('iframe');
    iframes.forEach(iframe => attachOverlayToIframe(iframe));
  }

  function observeDOM() {
    const observer = new MutationObserver((mutations) => {
      mutations.forEach((mutation) => {
        mutation.addedNodes.forEach((node) => {
          if (node.nodeType === Node.ELEMENT_NODE) {
            if (node.tagName === 'VIDEO') {
              attachOverlayToVideo(node);
            }
            if (node.tagName === 'IFRAME') {
              attachOverlayToIframe(node);
            }
            const videos = node.querySelectorAll?.('video');
            if (videos) {
              videos.forEach(video => attachOverlayToVideo(video));
            }
            const iframes = node.querySelectorAll?.('iframe');
            if (iframes) {
              iframes.forEach(iframe => attachOverlayToIframe(iframe));
            }
          }
        });
      });
    });

    observer.observe(document.body, {
      childList: true,
      subtree: true
    });
  }

  /**
   * Get the best downloadable URL for a video element (called at click time)
   */
  function getBestVideoUrl(video) {
    // 1. Try direct video src (if it's a real URL, not blob)
    const videoSrc = video.src || video.currentSrc;
    if (videoSrc && isDownloadableUrl(videoSrc)) {
      return videoSrc;
    }
    
    // 2. Try source elements
    const sourceEl = video.querySelector('source[src]');
    if (sourceEl && sourceEl.src && isDownloadableUrl(sourceEl.src)) {
      return sourceEl.src;
    }
    
    // 3. Try to find the canonical/permalink URL for this video
    const permalink = findVideoPermalink(video);
    if (permalink) {
      return permalink;
    }
    
    // 4. Try og:video meta tags
    const ogVideo = document.querySelector('meta[property="og:video:url"], meta[property="og:video"]');
    if (ogVideo?.content && isDownloadableUrl(ogVideo.content)) {
      return ogVideo.content;
    }
    
    // 5. Use page URL as last resort
    return window.location.href;
  }

  /**
   * Find permalink/canonical URL for a video by looking at surrounding elements
   */
  function findVideoPermalink(video) {
    // For Twitter/X: Find the closest status link to the video
    // This handles quote retweets where the video is in the quoted tweet
    const closestStatusLink = findClosestStatusLink(video);
    if (closestStatusLink) {
      return closestStatusLink;
    }
    
    // Walk up the DOM tree looking for links that might be the video permalink
    let element = video.parentElement;
    let depth = 0;
    const maxDepth = 15;
    
    while (element && depth < maxDepth) {
      const redditLink = element.querySelector('a[href*="/comments/"]'); // Reddit
      if (redditLink) {
        return redditLink.href;
      }
      
      // Check for data attributes that might contain video ID
      const tweetId = element.dataset?.tweetId || element.closest('[data-tweet-id]')?.dataset?.tweetId;
      if (tweetId) {
        return `https://twitter.com/i/status/${tweetId}`;
      }
      
      element = element.parentElement;
      depth++;
    }
    
    // Check for Twitter/X specific URL patterns in current page
    const currentUrl = window.location.href;
    if (currentUrl.match(/https?:\/\/(twitter\.com|x\.com)\/[^/]+\/status\/\d+/)) {
      return currentUrl;
    }
    
    return null;
  }

  /**
   * Find the closest status link to a video element (for Twitter/X)
   * This traverses up from the video and finds the first valid status link
   * at each level, ensuring we get the quoted tweet's link, not the outer tweet's
   */
  function findClosestStatusLink(video) {
    let element = video.parentElement;
    let depth = 0;
    const maxDepth = 20;
    
    while (element && depth < maxDepth) {
      // Check if this element itself is a link to a status
      if (element.tagName === 'A' && element.href) {
        if (isValidStatusLink(element.href)) {
          return element.href;
        }
      }
      
      // Look for direct child links (not nested in sub-containers)
      // This prevents finding links from the outer tweet when we're in a quoted tweet
      const directLinks = Array.from(element.children).filter(child => 
        child.tagName === 'A' && child.href && isValidStatusLink(child.href)
      );
      if (directLinks.length > 0) {
        return directLinks[0].href;
      }
      
      // Look for a timestamp link at this level (common pattern for tweet permalinks)
      const timeEl = element.querySelector(':scope > a[href*="/status/"] time, :scope > div > a[href*="/status/"] time');
      if (timeEl) {
        const timeLink = timeEl.closest('a');
        if (timeLink && isValidStatusLink(timeLink.href)) {
          return timeLink.href;
        }
      }
      
      // For quoted tweets: check if we're in a quoted tweet container
      // Quoted tweets often have a specific structure with the status link nearby
      if (element.getAttribute('data-testid') === 'tweetPhoto' || 
          element.getAttribute('role') === 'link' ||
          element.querySelector('[data-testid="tweetPhoto"]')) {
        // Look for the closest ancestor that contains a status link
        const statusLink = element.querySelector('a[href*="/status/"]');
        if (statusLink && isValidStatusLink(statusLink.href)) {
          return statusLink.href;
        }
      }
      
      // If we hit an article boundary, search within it but prioritize 
      // links closer to the video (quoted content)
      if (element.tagName === 'ARTICLE') {
        // First, try to find links within quoted tweet containers
        const quotedTweet = element.querySelector('[data-testid="quoteTweet"], [role="link"][tabindex="0"]');
        if (quotedTweet && quotedTweet.contains(video)) {
          // Video is in quoted tweet - find status link in quoted section
          const quotedLink = quotedTweet.querySelector('a[href*="/status/"]');
          if (quotedLink && isValidStatusLink(quotedLink.href)) {
            return quotedLink.href;
          }
          // Sometimes the quoted tweet container itself is a link
          if (quotedTweet.tagName === 'A' && isValidStatusLink(quotedTweet.href)) {
            return quotedTweet.href;
          }
          // Check parent of quoted tweet for the link
          const quotedParent = quotedTweet.closest('a[href*="/status/"]');
          if (quotedParent && isValidStatusLink(quotedParent.href)) {
            return quotedParent.href;
          }
        }
        
        // Fallback: find all status links and get the one closest to the video
        const allStatusLinks = element.querySelectorAll('a[href*="/status/"]');
        let closestLink = null;
        let closestDistance = Infinity;
        
        for (const link of allStatusLinks) {
          if (!isValidStatusLink(link.href)) continue;
          
          // Calculate DOM distance from video to this link
          const distance = getDomDistance(video, link);
          if (distance < closestDistance) {
            closestDistance = distance;
            closestLink = link;
          }
        }
        
        if (closestLink) {
          return closestLink.href;
        }
      }
      
      element = element.parentElement;
      depth++;
    }
    
    return null;
  }

  /**
   * Check if a URL is a valid Twitter/X status link
   */
  function isValidStatusLink(href) {
    if (!href) return false;
    // Must match /status/ followed by digits, and not be a /photo/ or /video/ subpath
    return href.match(/\/(status|statuses)\/\d+/) && 
           !href.includes('/photo/') && 
           !href.includes('/video/');
  }

  /**
   * Calculate a simple DOM distance between two elements
   * Lower number = closer in the DOM tree
   */
  function getDomDistance(el1, el2) {
    const path1 = getPathToRoot(el1);
    const path2 = getPathToRoot(el2);
    
    // Find common ancestor
    let commonDepth = 0;
    while (commonDepth < path1.length && commonDepth < path2.length && 
           path1[path1.length - 1 - commonDepth] === path2[path2.length - 1 - commonDepth]) {
      commonDepth++;
    }
    
    // Distance = steps from el1 to common ancestor + steps from common ancestor to el2
    return (path1.length - commonDepth) + (path2.length - commonDepth);
  }

  /**
   * Get path from element to document root
   */
  function getPathToRoot(el) {
    const path = [];
    while (el) {
      path.push(el);
      el = el.parentElement;
    }
    return path;
  }

  /**
   * Check if URL is downloadable (not blob, data URI, etc.)
   */
  function isDownloadableUrl(url) {
    if (!url || typeof url !== 'string') return false;
    if (url.startsWith('blob:')) return false;
    if (url.startsWith('data:')) return false;
    if (url.trim() === '') return false;
    return true;
  }

  /**
   * Get URL from embedded iframe
   */
  function getIframeVideoUrl(iframe) {
    const src = iframe.src;
    if (!src) return null;
    
    for (const { pattern, buildUrl } of EMBED_PATTERNS) {
      const match = src.match(pattern);
      if (match) {
        return buildUrl(match[1]);
      }
    }
    
    return null;
  }

  function attachOverlayToVideo(video) {
    if (video.dataset.vidpullAttached) return;
    attachOverlay(video, () => getBestVideoUrl(video));
  }

  function attachOverlayToIframe(iframe) {
    if (iframe.dataset.vidpullAttached) return;
    
    const embedUrl = getIframeVideoUrl(iframe);
    if (!embedUrl) return; // Only attach to recognized video embeds
    
    attachOverlay(iframe, () => embedUrl);
  }

  /**
   * Attach overlay to any element
   * @param {HTMLElement} element - The video or iframe element
   * @param {Function} getUrl - Function that returns the URL to download (called at click time)
   */
  function attachOverlay(element, getUrl) {
    element.dataset.vidpullAttached = 'true';

    const container = document.createElement('div');
    container.className = CONTAINER_CLASS;
    
    const button = document.createElement('button');
    button.className = OVERLAY_CLASS;
    button.title = 'Download with VidPull (drag to reposition)';
    button.innerHTML = `
      <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
        <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/>
        <polyline points="7 10 12 15 17 10"/>
        <line x1="12" y1="15" x2="12" y2="3"/>
      </svg>
    `;
    
    container._video = element;
    container._getUrl = getUrl;
    
    setupDrag(button, container, element);
    
    let isDragging = false;
    button.addEventListener('mousedown', () => { isDragging = false; });
    
    button.addEventListener('click', (e) => {
      if (isDragging) {
        e.preventDefault();
        e.stopPropagation();
        return;
      }
      
      e.preventDefault();
      e.stopPropagation();
      
      // Get URL at click time (dynamic)
      const url = container._getUrl();
      const encodedUrl = encodeURIComponent(url);
      const vidpullUrl = `vidpull://download?url=${encodedUrl}`;
      
      console.log('[VidPull] Downloading:', url);
      window.location.href = vidpullUrl;
    });
    
    button._setDragging = (val) => { isDragging = val; };

    container.appendChild(button);
    positionOverlay(element, container);
    
    const parent = element.parentElement;
    if (parent) {
      const parentPosition = window.getComputedStyle(parent).position;
      if (parentPosition === 'static') {
        parent.style.position = 'relative';
      }
      parent.appendChild(container);
    }

    container.style.display = overlaysVisible ? 'block' : 'none';

    const resizeObserver = new ResizeObserver(() => {
      positionOverlay(element, container);
    });
    resizeObserver.observe(element);

    const mutationObserver = new MutationObserver(() => {
      if (!document.contains(element)) {
        container.remove();
        resizeObserver.disconnect();
        mutationObserver.disconnect();
      }
    });
    mutationObserver.observe(document.body, { childList: true, subtree: true });
  }

  function setupDrag(button, container, video) {
    let startX, startY, startLeft, startTop, hasMoved = false;

    button.addEventListener('mousedown', (e) => {
      if (e.button !== 0) return;
      
      e.preventDefault();
      hasMoved = false;
      startX = e.clientX;
      startY = e.clientY;
      
      const rect = container.getBoundingClientRect();
      startLeft = rect.left;
      startTop = rect.top;
      
      button.classList.add('vidpull-dragging');
      document.addEventListener('mousemove', onMouseMove);
      document.addEventListener('mouseup', onMouseUp);
    });

    function onMouseMove(e) {
      const deltaX = e.clientX - startX;
      const deltaY = e.clientY - startY;
      
      if (Math.abs(deltaX) > 5 || Math.abs(deltaY) > 5) {
        hasMoved = true;
        button._setDragging(true);
      }
      
      if (!hasMoved) return;
      
      const videoRect = video.getBoundingClientRect();
      const parentRect = video.parentElement?.getBoundingClientRect();
      if (!parentRect) return;
      
      const newLeft = startLeft + deltaX - parentRect.left;
      const newTop = startTop + deltaY - parentRect.top;
      const buttonSize = 40;
      
      container.style.left = `${Math.max(0, Math.min(newLeft, videoRect.width - buttonSize))}px`;
      container.style.top = `${Math.max(0, Math.min(newTop, videoRect.height - buttonSize))}px`;
    }

    function onMouseUp() {
      document.removeEventListener('mousemove', onMouseMove);
      document.removeEventListener('mouseup', onMouseUp);
      button.classList.remove('vidpull-dragging');
      
      if (hasMoved) {
        const videoRect = video.getBoundingClientRect();
        const containerRect = container.getBoundingClientRect();
        const parentRect = video.parentElement?.getBoundingClientRect();
        
        if (parentRect && videoRect.width > 0 && videoRect.height > 0) {
          buttonPosition = {
            xPercent: ((containerRect.left - parentRect.left + 20) / videoRect.width) * 100,
            yPercent: ((containerRect.top - parentRect.top + 20) / videoRect.height) * 100
          };
          chrome.storage.sync.set({ [STORAGE_KEY_POSITION]: buttonPosition });
        }
        
        setTimeout(() => button._setDragging(false), 50);
      }
    }
  }

  function positionOverlay(video, container) {
    const rect = video.getBoundingClientRect();
    const parentRect = video.parentElement?.getBoundingClientRect();
    
    if (parentRect && rect.width > 0 && rect.height > 0) {
      const buttonSize = 40;
      const xPos = (buttonPosition.xPercent / 100) * rect.width - (buttonSize / 2);
      const yPos = (buttonPosition.yPercent / 100) * rect.height - (buttonSize / 2);
      
      const videoOffsetX = rect.left - parentRect.left;
      const videoOffsetY = rect.top - parentRect.top;
      
      container.style.position = 'absolute';
      container.style.left = `${videoOffsetX + Math.max(0, Math.min(xPos, rect.width - buttonSize))}px`;
      container.style.top = `${videoOffsetY + Math.max(0, Math.min(yPos, rect.height - buttonSize))}px`;
      container.style.zIndex = '2147483647';
    }
  }

  function repositionAllOverlays() {
    document.querySelectorAll(`.${CONTAINER_CLASS}`).forEach(container => {
      if (container._video) positionOverlay(container._video, container);
    });
  }

  function updateOverlayVisibility() {
    document.querySelectorAll(`.${CONTAINER_CLASS}`).forEach(container => {
      container.style.display = overlaysVisible ? 'block' : 'none';
    });
  }

  function removeAllOverlays() {
    document.querySelectorAll(`.${CONTAINER_CLASS}`).forEach(c => c.remove());
    document.querySelectorAll('[data-vidpull-attached]').forEach(el => delete el.dataset.vidpullAttached);
  }

})();
