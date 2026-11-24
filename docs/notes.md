# Notes and highlights

How a reader's notes and highlights work (use case 3), where the code is, and the fixes from the
user study and peer review.

## What it does

- **In the Read tab**, selecting text shows **Highlight**, **Add note** and **Copy**. A highlight is
  always yellow. A note is green, blue or pink, picked when it is written, and also gets an
  underline in a darker shade. So notes and highlights look different on the page, and the
  underline shows the words can be tapped to read the note. Both stay as pages turn.
- **Tapping a highlight** opens it to write a note (which makes it a note in the picked color) or
  remove it. A highlight's own color doesn't change. When several notes are on the same words, the
  reader first picks which one.
- **The Notes tab** lists every note and highlight of the open book by chapter, with search, a
  chapter picker, color filters and an **All / Notes / Highlights** toggle. Each card says whether it
  is a note or a highlight. Tapping one jumps to its passage, where it shows in its own color.
- Leaving the Read tab clears any text selection, so the menu over it doesn't stay on screen.
- Notes are saved on the phone, one file per book, and are never used as facts about the story.

## Where the code is

| File | What it does |
| :--- | :--- |
| `lib/notes/note.dart` | `Note`, `NoteAnchor`, `HighlightColor`, the color rules (`highlightColor`, `noteColors`, `defaultNoteColor`) and the JSON format. A highlight is a note with no text. |
| `lib/notes/note_repository.dart` | Loads and saves `<app support>/library/notes/<book id>/notes.json`, through a temp file and a rename. |
| `lib/notes/annotation_service.dart` | The notes of one book, shared by the Read and Notes tabs: add, edit, delete, sort, filter, the color rules, and finding notes on the same words. |
| `lib/notes/add_note_sheet.dart` | The sheet for adding or editing a note, with the note colors. |
| `lib/notes/note_list.dart` | The Notes tab's list and filters, the edit flow, and the picker for notes on the same words. |
| `lib/notes/highlight_colors.dart` | Each color's label, swatch, page fill and underline shade. |
| `lib/home/read_screen.dart` | The selection menu's actions, tapping a highlight, drawing notes, jumping to a note, and `ReaderSelectionController`. |
| `lib/home/book_screen.dart` | Clears the selection when the reader leaves the Read tab. |
| `lib/reader/readium_reader_service.dart` | The Readium side: the menu, the `loremark-notes` and `loremark-note-marks` decoration groups, going to a note without a search highlight, the clear-selection signal, and redrawing after a page turn. |
| `assets/reader/note_selection.js` | Clears the selection once a note made from it is drawn, or when the app signals it to. |

## Fixes from the user study and peer review

These are on `fix/notes-highlights-issues` (PR #147). The full write-ups are in the
[bug log](bug-log.md) (BUG-24 to BUG-30).

| Issue | Bug log | What was wrong | Fix |
| :--- | :--- | :--- | :--- |
| [#99](https://github.com/bennyxzeng/Loremark/issues/99) | BUG-25 | The selection, and its Highlight / Add note / Copy menu, stayed on screen after Highlight and over other tabs. | `note_selection.js` clears it when a new note is drawn. On a tab switch, the app signals the script to clear it through an invisible decoration. |
| [#91](https://github.com/bennyxzeng/Loremark/issues/91) | BUG-24 | The first note seemed not to be highlighted. | Most likely the selection covering it (#99), so the same fix. To confirm on a phone. |
| [#115](https://github.com/bennyxzeng/Loremark/issues/115) | BUG-26 | After jumping to a note and deleting it, its passage stayed highlighted until a restart. It also hid the note's color and underline. | Opening a note goes to its passage without drawing the search highlight on top. |
| [#112](https://github.com/bennyxzeng/Loremark/issues/112) | BUG-27 | Two notes on the same words: only the top one could be opened. | Tapping such words lists the notes to pick from, but only when they share words, not when they are just near each other. Notes at the same spot keep a fixed order. |
| [#135](https://github.com/bennyxzeng/Loremark/issues/135) | BUG-28 | A highlight's color could only change by typing a note. | By design now: a highlight is always yellow, and picking a color means writing a note (see #124). |
| [#123](https://github.com/bennyxzeng/Loremark/issues/123) | BUG-29 | The Pink filter was off screen on a narrow phone. | The filters wrap onto a second line instead of scrolling sideways. |
| [#124](https://github.com/bennyxzeng/Loremark/issues/124) | BUG-30 | Notes and highlights looked the same. | Highlights are yellow and notes green, blue or pink. Notes also get an underline, in its own layer above the fills, and a "Note" label in the Notes tab. |
| [#71](https://github.com/bennyxzeng/Loremark/issues/71) | OPEN-06 | Android's menu lost Share and Select All. | Not changed: a limit of the reader plugin, explained under OPEN-06 in the bug log. |

Notes saved yellow before these rules keep their color until they are edited; the edit sheet then
starts on green.

The tests are in `test/notes/annotation_service_test.dart`, `test/notes/notes_ui_test.dart`,
`test/home/read_screen_notes_test.dart`, `test/reader/readium_reader_service_test.dart` and
`test/reader/readium_session_test.dart`. Each new test names its issue.
