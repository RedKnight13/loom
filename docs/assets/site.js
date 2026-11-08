(function () {
  'use strict';
  var buttons = document.querySelectorAll('[data-copy-bootstrap]');
  var statuses = document.querySelectorAll('[data-copy-status]');
  var prompt = document.getElementById('bootstrap-prompt');
  var select = document.querySelector('[data-select-prompt]');
  var loadStatus = document.getElementById('prompt-load-status');
  var cached;

  function announce(message) {
    statuses.forEach(function (status) { status.textContent = message; });
  }
  async function loadPrompt() {
    if (cached) return cached;
    var response = await fetch('bootstrap.txt', { cache: 'no-store' });
    if (!response.ok) throw new Error('Prompt download failed');
    var text = await response.text();
    if (!text.trim() || /^\s*(?:<!doctype html|<html)/i.test(text)) {
      throw new Error('Prompt response was empty or HTML');
    }
    cached = text;
    if (prompt) {
      prompt.value = text;
      loadStatus.textContent = 'Prompt loaded from bootstrap.txt.';
      select.hidden = false;
    }
    return text;
  }
  async function copy(text) {
    try {
      await navigator.clipboard.writeText(text);
      return true;
    } catch (error) {
      var active = document.activeElement;
      var field = document.createElement('textarea');
      field.value = text;
      field.style.position = 'fixed';
      field.style.left = '-9999px';
      document.body.appendChild(field);
      field.select();
      var copied = false;
      try { copied = document.execCommand('copy'); } catch (ignored) { /* Manual copy remains available. */ }
      field.remove();
      if (active) active.focus();
      return copied;
    }
  }
  buttons.forEach(function (button) {
    button.hidden = false;
    button.addEventListener('click', async function () {
      var restoreFocus = document.activeElement === button;
      button.disabled = true;
      announce('Loading bootstrap prompt…');
      try {
        var text = await loadPrompt();
        if (await copy(text)) {
          announce('Bootstrap prompt copied. Paste it into your coding agent.');
        } else {
          announce('Clipboard access failed. Open the raw prompt, select all its text, and copy manually.');
        }
      } catch (error) {
        announce('Could not load bootstrap.txt. Open the raw prompt or try copying again.');
      } finally {
        button.disabled = false;
        if (restoreFocus) button.focus();
      }
    });
  });
  if (prompt) {
    loadStatus.textContent = 'Loading prompt…';
    loadPrompt().catch(function () {
      loadStatus.textContent = 'Could not load the prompt. Open the raw prompt above, or use Copy bootstrap prompt to retry.';
    });
    select.addEventListener('click', function () {
      prompt.focus();
      prompt.select();
      announce('Prompt selected. Use your keyboard’s copy command.');
    });
  }
})();
