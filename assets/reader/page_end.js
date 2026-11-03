// Added to every chapter by the reader (see readium_reader_service.dart).
//
// Spoiler-safe search needs to know how much of the chapter the reader has
// fully seen. Readium reports where a page starts; this reports where it ends:
// the first text block that does not fit on the page, and how much of that
// block does.
//
// It rides on the plugin's own page report. Readium calls
// window.flutterReadium.getPageInformation() for every page and passes the
// `physicalPage` string through to the app untouched, so a marker there
// reaches Dart without any native code. The marker is
// "loremark-end:<n>:<k>:<tail>": <n> counts the chapter's text blocks from 0,
// in document order, <k> is how many characters of block <n>, not counting
// whitespace, are on the page (0 if the block starts on the next one), and
// <tail> is the last few of those characters before the page ends, URL-encoded.
// epub_sections.dart counts the same blocks and characters in its own copy of
// the chapter, so extra elements Readium adds to the page, and different
// whitespace, cannot shift anything. It then checks the tail against its own
// text, and drops the report if they differ, so a miscount can never open
// more of the book than the reader has seen.
//
// Anything unexpected reports nothing, and the app then falls back to
// counting only finished chapter files.
(function () {
  'use strict';

  var MARKER = 'loremark-end:';

  // Must match leafBlockTags in lib/reader/epub_sections.dart.
  var BLOCKS = 'p,h1,h2,h3,h4,h5,h6,li,blockquote,dt,dd,pre,figcaption,td,th,div';

  // Text that is not part of the chapter's plain text. Must match the
  // elements skipped in epub_sections.dart.
  var SKIPPED = { script: 1, style: 1, svg: 1, rt: 1, rp: 1, head: 1 };

  // How many characters of the text before the page end are sent to check.
  var TAIL = 12;

  var leaves = null;

  // Blocks that hold text and contain no other block.
  function textBlocks() {
    if (leaves) return leaves;
    leaves = [];
    var all = document.body ? document.body.querySelectorAll(BLOCKS) : [];
    for (var i = 0; i < all.length; i++) {
      var el = all[i];
      if (el.querySelector(BLOCKS)) continue;
      if (!/\S/.test(el.textContent)) continue;
      leaves.push(el);
    }
    return leaves;
  }

  // Where the last line of [el] is on screen, or null if it is not shown.
  function lastLine(el) {
    var range = document.createRange();
    range.selectNodeContents(el);
    var rects = range.getClientRects();
    for (var i = rects.length - 1; i >= 0; i--) {
      if (rects[i].width > 0 && rects[i].height > 0) return rects[i];
    }
    return null;
  }

  // Pages follow each other to the right, one screen width apart. Other
  // layouts (right-to-left, vertical) are not measured.
  function horizontalLtr() {
    var nodes = [document.documentElement, document.body];
    for (var i = 0; i < nodes.length; i++) {
      var style = getComputedStyle(nodes[i]);
      if (style.direction !== 'ltr') return false;
      if (style.writingMode && style.writingMode !== 'horizontal-tb') return false;
    }
    return true;
  }

  // The first text block whose last line is past the right edge of the screen,
  // so it is not fully on this page, with how much of it is. Null if there is
  // none, as on the last page of a chapter.
  function firstBlockPastPage() {
    if (!horizontalLtr()) return null;
    var blocks = textBlocks();
    var width = window.innerWidth;
    if (!(width > 0)) return null;

    function shownAtOrAfter(i, end) {
      while (i < end && !lastLine(blocks[i])) i++;
      return i;
    }
    function past(i) {
      return lastLine(blocks[i]).left >= width;
    }

    // Blocks in layout order are on this page or an earlier one (not past),
    // then past. Blocks that are not shown are skipped.
    var low = 0;
    var high = blocks.length;
    while (low < high) {
      var middle = (low + high) >> 1;
      var probe = shownAtOrAfter(middle, high);
      if (probe === high) {
        high = middle;
      } else if (past(probe)) {
        high = probe;
      } else {
        low = probe + 1;
      }
    }
    var found = shownAtOrAfter(low, blocks.length);
    if (found >= blocks.length || !past(found)) return null;
    var characters = charactersOnPage(blocks[found], width);
    var tail = '';
    try {
      tail = encodeURIComponent(tailBefore(blocks, found, characters));
    } catch (e) {
      // A lone surrogate can't be encoded: send no tail, so no check.
    }
    return { block: found, characters: characters, tail: tail };
  }

  function isSkipped(node, block) {
    for (var el = node.parentElement; el && el !== block; el = el.parentElement) {
      if (SKIPPED[el.localName]) return true;
    }
    return false;
  }

  function countNonWhitespace(text) {
    var n = 0;
    for (var i = 0; i < text.length; i++) {
      if (/\S/.test(text.charAt(i))) n++;
    }
    return n;
  }

  // Where character [i] of [node] is, or null if it is not shown.
  function charLeft(node, i) {
    var range = document.createRange();
    range.setStart(node, i);
    range.setEnd(node, i + 1);
    var rects = range.getClientRects();
    for (var r = 0; r < rects.length; r++) {
      if (rects[r].width > 0 && rects[r].height > 0) return rects[r].left;
    }
    return null;
  }

  // The first character of [node] shown past the right edge, or -1.
  function firstCharPastPage(node, width) {
    var text = node.nodeValue;
    function shown(i) {
      return /\S/.test(text.charAt(i)) && charLeft(node, i) !== null;
    }
    var low = 0;
    var high = text.length;
    while (low < high) {
      var middle = (low + high) >> 1;
      var probe = middle;
      while (probe < high && !shown(probe)) probe++;
      if (probe === high) {
        high = middle;
      } else if (charLeft(node, probe) >= width) {
        high = probe;
      } else {
        low = probe + 1;
      }
    }
    var i = low;
    while (i < text.length && !shown(i)) i++;
    return i < text.length && charLeft(node, i) >= width ? i : -1;
  }

  // How many characters of [block], not counting whitespace, come before the
  // first one shown past the right edge.
  function charactersOnPage(block, width) {
    var walker = document.createTreeWalker(block, NodeFilter.SHOW_TEXT);
    var count = 0;
    for (var node = walker.nextNode(); node; node = walker.nextNode()) {
      if (isSkipped(node, block)) continue;
      var first = firstCharPastPage(node, width);
      if (first >= 0) return count + countNonWhitespace(node.nodeValue.slice(0, first));
      count += countNonWhitespace(node.nodeValue);
    }
    return 0;
  }

  // All characters of [block], not counting whitespace.
  function nonWhitespaceText(block) {
    var walker = document.createTreeWalker(block, NodeFilter.SHOW_TEXT);
    var out = '';
    for (var node = walker.nextNode(); node; node = walker.nextNode()) {
      if (isSkipped(node, block)) continue;
      out += node.nodeValue.replace(/\s+/g, '');
    }
    return out;
  }

  // The last TAIL characters, not counting whitespace, before the page end:
  // [characters] characters into block [index].
  function tailBefore(blocks, index, characters) {
    var text = nonWhitespaceText(blocks[index]).slice(0, characters);
    for (var i = index - 1; text.length < TAIL && i >= 0; i--) {
      text = nonWhitespaceText(blocks[i]) + text;
    }
    return text.slice(-TAIL);
  }

  function install() {
    var tools = window.flutterReadium;
    if (!tools || typeof tools.getPageInformation !== 'function') return false;
    var original = tools.getPageInformation;
    tools.getPageInformation = function () {
      var info = original.apply(this, arguments);
      try {
        var end = firstBlockPastPage();
        if (info && end !== null) {
          info.physicalPage =
            MARKER + end.block + ':' + end.characters + ':' + end.tail;
        }
      } catch (e) {
        // Report the page as Readium would have.
      }
      return info;
    };
    return true;
  }

  // The plugin creates window.flutterReadium after this script runs.
  if (!install()) {
    var tries = 0;
    var timer = setInterval(function () {
      if (install() || ++tries > 200) clearInterval(timer);
    }, 50);
  }
})();
