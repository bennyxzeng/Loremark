# Test fixtures

Everything here is synthetic and written for these tests. No text from a real novel is copied.

- `synthetic_chapter.txt`: an eight-paragraph chapter in the `[p0001] text` format that
  `chapter.txt` uses. It includes curly quotes, a reported claim, a flashback, and a line of
  dialogue that tries to override the instructions (prompt-injection check).
- `synthetic_model.json`: a hand-written `ChapterStoryModel` for that chapter. Every quote is
  an exact substring of its paragraph, so it passes validation. Tests copy it and break one
  thing at a time.

Synthetic EPUB files are built in temporary directories by `conftest.py`, so no binary EPUB
fixtures are stored here.
