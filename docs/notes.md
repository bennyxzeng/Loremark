# Notes and highlights

How a reader's notes and highlights work (use case 3), where the code is, and the fixes from the
user study and peer review.

## What it does

- **In the Read tab**, selecting text shows **Highlight**, **Add note** and **Copy**. Highlights are
  drawn on the page in the color picked (yellow, green, blue or pink) and stay as pages turn. A
  note with text also gets an underline in a darker shade, so it stands out from a plain highlight.
- **Tapping a highlight** opens it to add a note, change its color, or remove it. When several notes
  are on the same words, the reader first picks which one.
- **The Notes tab** lists every note and highlight of the open book by chapter, with search, a
  chapter picker, color filters and an **All / Notes / Highlights** toggle. Each card says whether it
  is a note or a highlight. Tapping one jumps to its passage.
- Notes are saved on the phone, one file per book, and are never used as facts about the story.

## Where the code is

| File | What it does |
| :--- | :--- |
| `lib/notes/note.dart` | `Note`, `NoteAnchor`, `HighlightColor`, and the JSON format. A highlight is a note with no text. |
| `lib/notes/note_repository.dart` | Loads and saves `<app support>/library/notes/<book id>/notes.json`, through a temp file and a rename. |
| `lib/notes/annotation_service.dart` | The notes of one book, shared by the Read and Notes tabs: add, edit, delete, sort, filter, and find notes on the same words. |
| `lib/notes/add_note_sheet.dart` | The sheet for adding or editing a note. |
| `lib/notes/note_list.dart` | The Notes tab's list and filters, the edit flow, and the picker for notes on the same words. |
| `lib/notes/highlight_colors.dart` | Each color's label, swatch, page fill and underline shade. |
| `lib/home/read_screen.dart` | The selection menu's actions, tapping a highlight, drawing notes, and jumping to a note. |
| `lib/reader/readium_reader_service.dart` | The Readium side: the menu, the `loremark-notes` decoration group, underlines, and redrawing after a page turn. |
| `assets/reader/note_selection.js` | Clears the selection once a note made from it is drawn, and when the page loses focus. |

## Fixes from the user study and peer review

These are on `fix/notes-highlights-issues`. The full write-ups are in the
[bug log](bug-log.md) (BUG-24 to BUG-30).

| Issue | Bug log | What was wrong | Fix |
| :--- | :--- | :--- | :--- |
| [#99](https://github.com/bennyxzeng/Loremark/issues/99) | BUG-25 | The selection stayed on screen after Highlight, and over other tabs. | `note_selection.js` clears it when a new note is drawn and when the page loses focus; `BookScreen` takes the focus away on a tab switch. |
| [#91](https://github.com/bennyxzeng/Loremark/issues/91) | BUG-24 | The first note seemed not to be highlighted. | Most likely the selection covering it (#99), so the same fix. To confirm on a phone. |
| [#115](https://github.com/bennyxzeng/Loremark/issues/115) | BUG-26 | After jumping to a note and deleting it, its passage stayed highlighted until a restart. | The Read tab clears the jump highlight when the note it shows is deleted or changed. |
| [#112](https://github.com/bennyxzeng/Loremark/issues/112) | BUG-27 | Two notes on the same words: only the top one could be opened. | Tapping such words lists the notes to pick from. Notes at the same spot keep a fixed order. |
| [#135](https://github.com/bennyxzeng/Loremark/issues/135) | BUG-28 | A highlight's color could only change by typing a note. | Editing a highlight can be saved with no text. |
| [#123](https://github.com/bennyxzeng/Loremark/issues/123) | BUG-29 | The Pink filter was off screen on a narrow phone. | The filters wrap onto a second line instead of scrolling sideways. |
| [#124](https://github.com/bennyxzeng/Loremark/issues/124) | BUG-30 | Notes and highlights looked the same. | Notes get an underline on the page and a "Note" label in the Notes tab. |
| [#71](https://github.com/bennyxzeng/Loremark/issues/71) | OPEN-06 | Android's menu lost Share and Select All. | Not changed: a limit of the reader plugin, explained under OPEN-06 in the bug log. |

The tests are in `test/notes/annotation_service_test.dart`, `test/notes/notes_ui_test.dart`,
`test/home/read_screen_notes_test.dart`, `test/reader/readium_reader_service_test.dart` and
`test/reader/readium_session_test.dart`. Each new test names its issue.
