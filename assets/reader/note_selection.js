// Added to every chapter by the reader (see readium_reader_service.dart).
//
// Clears the reader's text selection once a note or highlight made from it
// is drawn, and when the reader leaves the page (issues #99 and #91).
//
// On Android, Loremark's Highlight / Add note / Copy menu replaces the system
// one, and flutter_readium 0.8.0 closes the menu after an action without
// clearing the selection (EpubReaderFragment.onActionItemClicked calls
// mode.finish() but never navigator.clearSelection()). The plugin has no
// clearSelection call for the app either. So the selection stayed on top of
// the new highlight, which looked as if nothing had been highlighted, and it
// stayed on screen over the other tabs.
//
// Readium draws every decoration group in this same document: a
// <div data-group="<group name>"> under <body>, holding one <div id="..."> per
// decoration (decorator.js in the Readium toolkits). So this watches the
// group the app draws notes in, and clears the selection when a decoration it
// has not seen before appears. A brand-new id means a note was just added or
// changed. Readium also removes and re-adds the whole group when the page is
// resized (requestLayout), but those items keep their ids, so a resize alone
// never clears anything.
//
// Copy draws nothing, so the selection stays after Copy, as it does in most
// apps.
//
// Anything unexpected does nothing, and the reader then clears the selection
// by tapping the page, as before.
(function () {
  'use strict';

  // Must match noteHighlightGroup in lib/reader/readium_reader_service.dart.
  var GROUP = 'loremark-notes';

  // The ids of the decorations already drawn, so only new ones count.
  var seen = {};

  function clearSelection() {
    try {
      var selection = window.getSelection && window.getSelection();
      if (selection && !selection.isCollapsed) selection.removeAllRanges();
    } catch (e) {
      // Leave the selection; the reader can still tap it away.
    }
  }

  // Whether [node] is the notes group's container.
  function isNotesGroup(node) {
    return (
      node &&
      node.nodeType === 1 &&
      node.getAttribute('data-group') === GROUP
    );
  }

  // Records the ids of the decorations in [container], and returns whether
  // any of them is new.
  function recordItems(container) {
    var found = false;
    var items = container.children;
    for (var i = 0; i < items.length; i++) {
      var id = items[i].id;
      if (!id || seen[id]) continue;
      seen[id] = true;
      found = true;
    }
    return found;
  }

  // Whether [node], just added to the page, is or holds a new notes decoration.
  function addsNewNote(node) {
    if (!node || node.nodeType !== 1) return false;
    // The whole group, as on the first note or after a resize.
    if (isNotesGroup(node)) return recordItems(node);
    // One decoration added to a group that was already there.
    if (isNotesGroup(node.parentNode) && node.id && !seen[node.id]) {
      seen[node.id] = true;
      return true;
    }
    return false;
  }

  function start() {
    var root = document.body || document.documentElement;
    if (!root || typeof MutationObserver === 'undefined') return;
    // Notes already on the page when it loads are not new.
    var existing = root.querySelectorAll('[data-group="' + GROUP + '"]');
    for (var i = 0; i < existing.length; i++) recordItems(existing[i]);

    new MutationObserver(function (records) {
      var drawn = false;
      for (var r = 0; r < records.length; r++) {
        var added = records[r].addedNodes;
        for (var n = 0; n < added.length; n++) {
          if (addsNewNote(added[n])) drawn = true;
        }
      }
      if (drawn) clearSelection();
    }).observe(root, { childList: true, subtree: true });
  }

  if (document.body) {
    start();
  } else {
    document.addEventListener('DOMContentLoaded', start);
  }

  // The page loses focus when the reader switches to another tab (BookScreen
  // takes the focus away from the reader view then), so the selection and its
  // handles don't stay on screen over the other tabs.
  window.addEventListener('blur', clearSelection);
})();
