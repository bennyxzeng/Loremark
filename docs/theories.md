# Theories

How a reader keeps a theory in Loremark, what its status means, and why it is built this way. Owner: Kevin. Code: [`lib/notes/theory.dart`](../lib/notes/theory.dart) (the data and the status rule), [`lib/notes/annotation_service.dart`](../lib/notes/annotation_service.dart) (saving and the dependency rules), [`lib/notes/add_note_sheet.dart`](../lib/notes/add_note_sheet.dart) and [`lib/notes/note_list.dart`](../lib/notes/note_list.dart) (the screens).

**Contents:** [Part 1: keeping a theory](#part-1-keeping-a-theory) · [What a theory is](#what-a-theory-is) · [Using it](#using-it) · [Statuses](#statuses) · [Building on an older theory](#building-on-an-older-theory) · [What is stored](#what-is-stored) · [Why it is built this way](#why-it-is-built-this-way) · [Spoilers](#spoilers) · [Testing](#testing) · [Not done yet](#not-done-yet)

# Part 1: keeping a theory

This part is what the `feat/theory-notes` branch adds. There are no AI calls in it. A theory can be written down, linked to an older theory, edited and deleted, and it shows its status in the Notes tab. Checking a theory against the book comes in part 2, with the check branch.

## What a theory is

A theory is a note in which the reader predicts what will happen later in the book. It is the same kind of note as a personal note (it has a passage, a color, and text, and it lives in the same file), plus a little extra data Loremark tracks: the parts of the prediction (sub-theories), the older theory it builds on, and how far through the book it has been checked.

The theory is the reader's guess. It is never treated as a fact about the story and never enters the Story Map or any story model.

## Using it

- Select text in the reader, choose **Add note**, and pick **Theory** instead of **Personal note** in the sheet. Personal note is the default, so ordinary notes work as before. (Living doc, Use Case #2: the reader selects Personal Note or the Theory tag.)
- If the book already has older theories, a **Builds on** picker appears under Theory. It lists **None** and each older theory with its text shortened.
- Saving with no text keeps the sheet open and shows the empty-note message (Use Case #2 3d).
- In the **Notes** tab a theory shows a **Theory** tag, a status chip, **Builds on: ...** when it is linked, and, once it has been split, each sub-theory with its verdict and, if the book settled it, the quote and chapter that did. Tapping it still jumps to its passage. The All / Notes / Highlights filter is unchanged, and a theory counts as a note.
- **Edit** opens the same sheet with the current kind and link. A note can be switched between personal note and theory.

Other code (the banner in part 2) can open the Notes tab on one note with `NoteFocusController.focus(noteId)`. The tab scrolls to that note, clears any filter that would hide it, and outlines it for two seconds.

## Statuses

The five names come from Use Case #2 and milestone #8 of the living doc. The status is **worked out, never stored**, by one function, `theoryStatus` in `theory.dart`, so it can't go out of date. The rules, in order:

| Rule | Status | Where it comes from |
| :--- | :--- | :--- |
| The theory builds on a theory whose own verdicts make it Different outcome, or on one that is Invalidated | **Invalidated** | Features #4 and Use Case #2 3a/3b: a theory that depends on a wrong one is no longer meaningful |
| No sub-theories yet, or every sub-theory still open | **Unconfirmed** | Use Case #2 step 1: a new theory starts unconfirmed |
| Every sub-theory confirmed | **Confirmed** | Use Case #2 3a |
| Every sub-theory refuted | **Different outcome** | Use Case #2 3b |
| Anything else, including a mix with some still open | **Partially correct** | Use Case #2 and milestone #8 |

The sub-theory verdicts are `open`, `confirmed` and `refuted`. Invalidation is transitive: if A builds on B and B builds on C, and C ends as Different outcome, then B and A are both Invalidated. A link to a theory that no longer exists is ignored, and a loop in the links can't hang the function (the links can't form a loop anyway, see below).

## Building on an older theory

A theory may build on **at most one older theory of the same book** (Features #4, "older theory"). The reader picks it in the sheet. Because a theory can only point at one that was made before it, the links can never form a loop.

- If the theory it builds on is deleted, the link is cleared (in the same save as the delete).
- If the older theory ends Confirmed or Partially correct, the newer one keeps being tracked as normal.
- The service refuses a link to a note that is not a theory of this book, to the theory itself, or to a newer theory, with an `ArgumentError`.
- The "Builds on" box only matters under Theory, but its space is kept whenever the book has an older theory, and the box is hidden under Personal note. The sheet sits at the bottom of the screen, so adding the box on choosing Theory used to push the text box up and make taps miss (bug THY-01). A test checks the text box does not move.

"Older" means made earlier. Notes made at the same moment (only possible in tests) are ordered by the counter at the end of their id.

## What is stored

Each theory is a normal note in the book's `notes.json`, with one extra key, `theory`:

```json
"kind": "theory",
"theory": {
  "subTheories": [
    { "id": "a", "text": "Mara is the thief", "verdict": "confirmed",
      "evidence": { "sectionIndex": 9, "chapterLabel": "Chapter 10", "quote": "..." },
      "resolvedAt": "2026-11-03T10:00:00.000Z" }
  ],
  "dependsOnId": "1730000000000000-2",
  "checkedThroughSection": 9
}
```

This is what the living doc's Data storage section asks for: the tag, the theory state, the result, and the evidence passage with its position (section and quote). `checkedThroughSection` is the last section already checked (-1 for none). `resolvedAt` is set when a verdict is first set. Personal notes have no `theory` key. The file version stays at 1 because the change only adds a key, so notes files saved before this branch still load; a theory without the key starts unsplit.

Writes go through one method, `AnnotationService.updateTheory(id, change)`, which the checker will use. It saves first and only then updates the screen, like every other write to the notes.

## Why it is built this way

- **Status is derived, not stored (D2).** Storing it would mean updating every dependent theory whenever one changes, and a missed update would show a wrong status. Working it out each time from the verdicts costs nothing for a few theories and can't be wrong.
- **Only one older theory (D3).** The spec says "older theory", singular. Limiting links to older theories makes loops impossible, so there is no loop handling to get wrong. The alternative, any theory depends on any other, needs cycle checks everywhere and was not in the spec.
- **Editing the text starts the theory over (D4).** Changing the words makes it a different prediction, so verdicts from the old words would be misleading. Changing only the color or the link keeps the progress. Saving the same text keeps it too. Turning a theory into a personal note drops its theory data so it can't resurface by accident.
- **Names and labels in one place (D1).** The enum has a `label`, and the screens use only that, so renaming a status is a one-line change if the team prefers other wording.
- **Theories count as notes in the Notes tab (D9).** The spec has no separate theory tab and keeps the All / Notes / Highlights filter, so a theory is shown as a note with a tag and a status chip rather than in its own list.
- **The tab shows every card at once.** The Notes tab scrolls with a plain column so it can scroll to any note by id. A book has few enough notes for that to be fine; a lazy list would be needed for thousands.

## Spoilers

Theories are written from what the reader has read, and nothing in this branch sends anything anywhere. Evidence quotes are only ever saved from sections the reader has finished (part 2 enforces that). A theory is never added to the Story Map or to any story model.

## Testing

`test/notes/theory_test.dart` (JSON, invalid data, every status rule, dependencies), `test/notes/theory_service_test.dart` (add, edit, delete, `updateTheory`, saving and reloading, files from before theories), `test/notes/theory_ui_test.dart` (the sheet, the Notes tab tile, scroll to a note), and one case in `test/home/read_screen_notes_test.dart` (saving a theory from the reader).

## Not done yet

- Splitting a theory into sub-theories and checking it against the book. Until the check branch, every theory stays Unconfirmed.
- The banner that tells the reader a theory changed. It will use `NoteFocusController`.
- The Notes tab does not search a theory's sub-theories.
- A theory can't be moved to another passage.
- The Notes tab is not lazy (see above).
