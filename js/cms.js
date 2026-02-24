/* ============================================================
   DEBTORA CZ — CMS Content Loader (Supabase version)
   Replaces: js/cms.js (Netlify Blobs version)
   
   Reads content from Supabase 'content' table and applies
   values to DOM elements with data-cms="blockKey.fieldName"
   ============================================================ */

(function () {
  'use strict';

  async function loadContent() {
    try {
      // Fetch all content blocks from Supabase
      const blocks = await API.getContent();
      if (!blocks || Object.keys(blocks).length === 0) return;

      // Find all elements with data-cms attribute
      const elements = document.querySelectorAll('[data-cms]');
      elements.forEach(el => {
        const key = el.getAttribute('data-cms');
        const value = resolveValue(key, blocks);
        if (value !== undefined && value !== null && value !== '') {
          el.innerHTML = value;
        }
        // If no CMS value, keep the original HTML content (fallback)
      });
    } catch (err) {
      // Silent fail — original HTML content remains
      console.warn('CMS load failed:', err.message);
    }
  }

  function resolveValue(key, blocks) {
    // key format: "blockKey.fieldName" or "blockKey.nested.field"
    const parts = key.split('.');
    const block = parts[0];
    const fieldParts = parts.slice(1);
    const field = fieldParts.join('.');
    
    if (!blocks[block]) return undefined;
    
    // Support nested fields
    let value = blocks[block];
    for (const part of fieldParts) {
      if (value && typeof value === 'object') {
        value = value[part];
      } else {
        return undefined;
      }
    }
    return value;
  }

  // Run on DOM ready
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', loadContent);
  } else {
    loadContent();
  }

  // Expose for manual refresh (e.g., after admin saves content)
  window.CMS = { reload: loadContent };
})();
