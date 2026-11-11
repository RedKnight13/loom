(function () {
  'use strict';
  document.querySelectorAll('.setup-doc table').forEach(function (table) {
    if (table.closest('.table-region')) return;
    var region = document.createElement('div');
    region.className = 'table-region';
    region.tabIndex = 0;
    region.setAttribute('role', 'region');
    region.setAttribute('aria-label', 'Reference table; scroll horizontally if needed');
    table.parentNode.insertBefore(region, table);
    region.appendChild(table);
  });
  document.querySelectorAll('.documentation-nav a').forEach(function (link) {
    if (link.pathname === window.location.pathname) link.setAttribute('aria-current', 'page');
  });
  var docsMenu = document.querySelector('.documentation-menu');
  if (docsMenu) {
    var narrowDocs = window.matchMedia('(max-width: 800px)');
    function sizeDocsMenu() { docsMenu.open = !narrowDocs.matches; }
    sizeDocsMenu();
    if (narrowDocs.addEventListener) narrowDocs.addEventListener('change', sizeDocsMenu);
  }
  var buttons = document.querySelectorAll('[data-copy-bootstrap]');
  var statuses = document.querySelectorAll('[data-copy-status]');
  var prompt = document.querySelector('textarea#bootstrap-prompt');
  var select = document.querySelector('[data-select-prompt]');
  var loadStatus = document.getElementById('prompt-load-status');


  function announce(message) {
    statuses.forEach(function (status) { status.textContent = message; });
  }
  async function loadPrompt() {
    var response = await fetch('bootstrap.txt', { cache: 'no-store' });
    if (!response.ok) throw new Error('Prompt download failed');
    var text = await response.text();
    if (!text.trim() || /^\s*(?:<!doctype html|<html)/i.test(text)) {
      throw new Error('Prompt response was empty or HTML');
    }
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
    var originalLabel = button.textContent;
    var resetLabel;
    button.hidden = false;
    button.addEventListener('click', async function () {
      var restoreFocus = document.activeElement === button;
      clearTimeout(resetLabel);
      button.disabled = true;
      button.textContent = 'Copying…';
      announce('Loading bootstrap prompt…');
      try {
        var text = await loadPrompt();
        if (await copy(text)) {
          button.textContent = 'Prompt copied';
          button.classList.add('is-copied');
          announce('Bootstrap prompt copied. Paste it into your coding agent.');
        } else {
          announce('Clipboard access failed. Open the raw prompt, select all its text, and copy manually.');
        }
      } catch (error) {
        announce('Could not load bootstrap.txt. Open the raw prompt or try copying again.');
      } finally {
        button.disabled = false;
        resetLabel = setTimeout(function () {
          button.textContent = originalLabel;
          button.classList.remove('is-copied');
        }, 2400);
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
  var explorer = document.querySelector('.pattern-explorer');
  if (explorer) {
    var picker = explorer.querySelector('.pattern-picker');
    var stories = explorer.querySelectorAll('.pattern-story');
    var choices = explorer.querySelectorAll('[data-pattern-target]');
    var motion = window.matchMedia('(prefers-reduced-motion: reduce)');
    var flowTimer;
    function stopFlows() {
      clearTimeout(flowTimer);
      stories.forEach(function (story) {
        story.classList.remove('is-flowing');
        story.querySelector('[data-play-pattern]').disabled = false;
      });
    }
    function playFlow(story) {
      stopFlows();
      if (motion.matches || document.hidden) return;
      void story.offsetWidth;
      story.classList.add('is-flowing');
      story.querySelector('[data-play-pattern]').disabled = true;
      flowTimer = setTimeout(stopFlows, 3600);
    }
    function selectPattern(id) {
      stopFlows();
      stories.forEach(function (story) { story.hidden = story.dataset.pattern !== id; });
      choices.forEach(function (choice) { choice.setAttribute('aria-pressed', String(choice.dataset.patternTarget === id)); });
      stories.forEach(function (story) { if (!story.hidden) playFlow(story); });
    }
    choices.forEach(function (choice) { choice.addEventListener('click', function () { selectPattern(choice.dataset.patternTarget); }); });
    stories.forEach(function (story) {
      var play = story.querySelector('[data-play-pattern]');
      play.addEventListener('click', function () {
        playFlow(story);
      });
    });
    function flowPreference() {
      stopFlows();
      stories.forEach(function (story) { story.querySelector('[data-play-pattern]').hidden = motion.matches; });
    }
    picker.hidden = false;
    flowPreference();
    selectPattern(choices[0].dataset.patternTarget);
    if (motion.addEventListener) motion.addEventListener('change', flowPreference);
    document.addEventListener('visibilitychange', function () { if (document.hidden) stopFlows(); });
  }
  var scene = document.querySelector('[data-handoff]');
  if (scene) {
    var replay = scene.querySelector('[data-replay-handoff]');
    var reduced = window.matchMedia('(prefers-reduced-motion: reduce)');
    var finish;
    function settle() {
      clearTimeout(finish);
      scene.classList.remove('is-playing');
      replay.disabled = false;
    }
    function play() {
      settle();
      if (reduced.matches || document.hidden) return;
      scene.classList.add('is-playing');
      replay.disabled = true;
      finish = setTimeout(settle, 4600);
    }
    function preference() {
      settle();
      replay.hidden = reduced.matches;
    }
    replay.addEventListener('click', play);
    if (reduced.addEventListener) reduced.addEventListener('change', preference);
    document.addEventListener('visibilitychange', function () { if (document.hidden) settle(); });
    preference();
    play();
  }
})();
