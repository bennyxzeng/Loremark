# Test fixtures

Everything here is synthetic and written for these tests. No text from a real novel is copied.

- `synthetic_chapter.txt`: an eight-paragraph chapter in the `[p0001] text` format that
  `chapter.txt` uses. It includes curly quotes, a reported claim, a flashback, and a line of
  dialogue that tries to override the instructions (prompt-injection check).
- `story/chapter1.txt`, `story/chapter2.txt`: a short two-chapter story for cumulative mode
  (a promotion, enemies becoming allies, a smuggler revealed to be a known ferryman, a
  flashback, a new character, an answered question).
- `story/chapter1_delta.json`: the StoryDelta that creates a store from Chapter 1 (an empty
  prior model, so every entity and record is new). One attribute (Tomas's age) is a
  deliberately unsupported inference that validation cannot catch.
- `story/chapter2_delta.json`: a valid StoryDelta for Chapter 2 against that first revision.

Synthetic EPUB files (including the story, with a prologue, an interlude, and a Chapter 3
holding sentinel text) are built in temporary directories by `conftest.py`, so no binary
EPUB fixtures are stored here.
