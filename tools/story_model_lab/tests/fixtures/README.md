# Test fixtures

Everything here is synthetic and written for these tests. No text from a real novel is copied.

- `synthetic_chapter.txt`: an eight-paragraph chapter in the `[p0001] text` format that
  `chapter.txt` uses. It includes curly quotes, a reported claim, a flashback, and a line of
  dialogue that tries to override the instructions (prompt-injection check).
- `synthetic_model.json`: a hand-written `ChapterStoryModel` for that chapter. Every quote is
  an exact substring of its paragraph, so it passes validation. Tests copy it and break one
  thing at a time.

- `story/chapter1.txt`, `story/chapter2.txt`: a short two-chapter story for cumulative mode
  (a promotion, enemies becoming allies, a smuggler revealed to be a known ferryman, a
  flashback, a new character, an answered question).
- `story/chapter1_model.json`: a v1 model of Chapter 1. One attribute (Tomas's age) is a
  deliberately unsupported inference, to check that `init` imports errors unchanged.
- `story/chapter2_delta.json`: a valid StoryDelta for Chapter 2 against the imported model.

Synthetic EPUB files (including the story, with a prologue, an interlude, and a Chapter 3
holding sentinel text) are built in temporary directories by `conftest.py`, so no binary
EPUB fixtures are stored here.
