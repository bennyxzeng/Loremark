# flutter_readium 0.8.0, patched

A copy of [flutter_readium](https://github.com/notalib/flutter_readium) 0.8.0 from pub.dev, without
`example/` and `test/`, with one change.

## The change

`setJavaScriptInjections` does nothing on iOS: the plugin keeps the list but never adds it to the
page (0.8.0 and 0.9.0 alike). Loremark's page script, `assets/reader/page_end.js`, therefore never
ran on iPhone, so no page end was measured there: Ask showed "Can’t see this page" everywhere but
a chapter file's last page, and search fell back to finished files.

The patch, in `ios/flutter_readium/Sources/flutter_readium/reader/EPUBReaderView+JSBridge.swift`
(marked "Loremark patch"), adds each registered asset as a `WKUserScript` at document end, for every
web view Readium sets up, the way Android adds a `<script>` to every resource.

## Going back to pub.dev

Once upstream applies JavaScript injections on iOS, set `flutter_readium` in `pubspec.yaml` back to
a version from pub.dev and delete this folder. Then check on an iPhone simulator that the debug log
shows `LOREMARK_PAGE_TEXT` lines while turning pages.
