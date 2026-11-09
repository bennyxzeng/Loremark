# Theories

How a reader keeps a theory in Loremark, what its status means, and why it is built this way. Owner: Kevin. Code: [`lib/theories/`](../lib/theories/) (the checker, part 2), [`lib/notes/theory.dart`](../lib/notes/theory.dart) (the data and the status rule), [`lib/notes/annotation_service.dart`](../lib/notes/annotation_service.dart) (saving and the dependency rules), [`lib/notes/add_note_sheet.dart`](../lib/notes/add_note_sheet.dart) and [`lib/notes/note_list.dart`](../lib/notes/note_list.dart) (the screens).

**Contents:** [Part 2: checking a theory](#part-2-checking-a-theory) (at the end) · [Part 1: keeping a theory](#part-1-keeping-a-theory) · [What a theory is](#what-a-theory-is) · [Using it](#using-it) · [Statuses](#statuses) · [Building on an older theory](#building-on-an-older-theory) · [What is stored](#what-is-stored) · [Why it is built this way](#why-it-is-built-this-way) · [Spoilers](#spoilers) · [Testing](#testing) · [Not done yet](#not-done-yet)

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

- Splitting a theory and checking it against the book, and the banner: these are part 2 below.
- The Notes tab does not search a theory's sub-theories.
- A theory can't be moved to another passage.
- The Notes tab is not lazy (see above).

# Part 2: checking a theory

This part is what the `feat/theory-correctness-check` branch adds. With an API key saved and a connection, Loremark splits each theory into sub-theories, checks them against each section the reader finishes, and tells the reader when a theory's status changes. It follows Use Case #2 (steps 1 to 3, and 3a to 3c), the Features #4 rule that a theory's result must be backed by the text, and the privacy requirement. Code: [`lib/theories/theory_requests.dart`](../lib/theories/theory_requests.dart) (the prompts, schemas and answer reading), [`lib/theories/theory_checker.dart`](../lib/theories/theory_checker.dart) (what runs and when), and the wiring in [`lib/home/book_screen.dart`](../lib/home/book_screen.dart).

## How checking works

1. **Split.** A theory with no sub-theories is sent to the model with the passage it was written on. The model returns one to five sub-theories (one when the theory makes a single prediction). They are saved as open.
2. **Check.** For each section the reader has finished, in order, Loremark sends that one section's text and the open sub-theories that still need it. The model answers `confirmed`, `refuted` or `undecided` for each, and for the first two it must quote the section word for word.
3. **Accept only real evidence.** A verdict counts only if its quote occurs in that section's text (ignoring differences in spaces and line breaks). Otherwise the sub-theory stays open. Once a sub-theory is confirmed or refuted it never changes again and is not sent again. The evidence (section, chapter label and quote) is saved with it.
4. **Status.** The overall status is still derived by `theoryStatus` (part 1), so one confirmed sub-theory out of two gives Partially correct, and a refuted older theory makes the theories built on it Invalidated. Nothing about status is stored.
5. **Banner.** When a theory's status moves from Unconfirmed or Partially correct to something new, a bar appears: `Theory confirmed: "<theory, shortened>"` with a **View** button that opens the Notes tab on that theory. This includes theories that became Invalidated because the one they build on was refuted. One bar per theory per run.

A theory is only checked against sections from the one it was written in onward, and each theory remembers the last section it has seen (`checkedThroughSection`), so no section is asked about twice. A theory that is already Invalidated through its dependency is not checked any more, so no money is spent on it.

## When it runs

- When a book is opened, when the number of finished sections goes up, and when a theory is saved or edited (so it gets split).
- Only if the book has an unresolved theory, an API key is saved, and the device is online. Without a key or offline nothing is sent and nothing breaks: theories can still be written, edited and deleted.
- One run at a time. A trigger that arrives during a run is merged into a single follow-up run that uses the latest position.
- No automatic retries. A failed run is simply tried again at the next trigger (the next finished section, the next time the book is opened, or the next theory saved).

## What is sent, and what is not

| Request | Contents | Never contains |
|---|---|---|
| Split | The theory's text and the passage the reader selected when writing it | Any section of the book, personal notes, other theories |
| Check | The paragraphs of exactly one finished section, and the open sub-theories' text (from one or more theories) | Any other section, personal notes, highlights |

How this maps to the privacy requirement and its verification:

- **Spoilers.** The boundary is `completedSectionCutoff` (the same one search uses), turned into a count of finished sections. A section whose index is not below that count is never sent: not the section the reader is in, not a later one. Turning back to reread an earlier chapter does not shrink it (it uses the furthest position reached in this session). Tests capture every request body and check that marker phrases planted in the section in progress and in a later chapter never appear.
- **One chapter per request.** A check request carries one section. A test checks that each captured request holds exactly one chapter heading.
- **Theory text only in theory requests.** Personal notes and highlights are never read by the checker. A test plants a diary-style note and a highlight and checks neither appears.
- **HTTPS and the AI provider only.** The checker uses the same sender as the Story Map (`callResponsesApi`), so it goes to the reader's own provider (api.openai.com or api.deepseek.com) over HTTPS with the reader's own key. The tests assert the scheme and host of every request.
- **Provider settings.** The OpenAI request asks for no storage (`store: false`), as the story requests do.

The split request includes the passage the theory was written on, which is a short excerpt the reader chose and has read. It can be in the section the reader is still reading. It is not a whole section, but it is the one place where text from an unfinished section can leave the device (see the open questions in the hand-off notes).

## Which model, and what it costs

The check uses the provider's light default model (`StoryModelChoice.forProvider(provider).first`: DeepSeek Flash or GPT-6.1 Terra) at the lowest effort that model accepts, not the Story Map model the reader picked. The team agreed in chat that DeepSeek or Terra are fine for light tasks, and the Story Map's most expensive model costs about $1.50 per four chapters, which is far too much for a background check. One check request is one section plus a few sentences. The cost has not been measured on a real key.

## When it fails

A request can fail with a bad key (401), a rate limit (429), a server error (500), a timeout, no connection, an answer that is not JSON, a refusal, or an answer in the wrong shape. In every case:

- no note changes (verdicts and progress already saved for earlier sections of the same run are kept, because each section's answer is saved before the next is asked for);
- the checker records only the failure's category (such as `authentication` or `rate_limit`), never the key, the provider's message or any book text;
- the run stops and reading is not interrupted: nothing is shown and no reader screen waits for it.

If the reader edits a theory while its request is out, the answer is dropped, because the theory is a new prediction (part 1, D4).

## Why it is built this way

- **Quote check instead of trusting the model (D8).** A model can say "confirmed" about a claim the text does not settle. Requiring a quote that really occurs in that section makes every verdict traceable to words the reader can find, and invented evidence is thrown away. The cost is that a correct verdict with a slightly reworded quote is also ignored; the sub-theory stays open and is not asked about that section again.
- **Undecided is the default.** The prompt tells the model to answer undecided unless the section settles the prediction, because a wrongly resolved sub-theory can never be undone.
- **Whole finished sections only (D5).** The app's page-level reading position is not exact enough to cut a section safely, so only sections the reader has completely finished count, which is the same rule search already uses.
- **One section per request.** The privacy requirement allows at most one chapter. Checking several theories in the same section shares one request, so adding theories does not add requests.
- **The same sender as the Story Map.** No second HTTP client to keep safe. The request shape mirrors `buildUpdateRequest`, which is tied to the Story Map's context, so the checker builds its own bodies in the same shape instead of calling it.

## Limits

- The verdicts are a model's judgement, only checked for having real evidence, not for being right. The reader can read the quote and decide.
- Only whole finished sections count, so a theory is settled only after the reader finishes the section that settles it.
- The furthest position is kept for the current session only. When a book is reopened, the saved page is the reader's position, so sections beyond it that were read in an earlier session are not checked until the reader gets back to them. This errs on the safe side.
- Evidence labels say `Section N` (the book's file order), not the book's own chapter title.
- Checks do not start by themselves when a key is saved or the connection returns; they wait for the next trigger.
- Nothing here has been tried against a real API key or on a device. The tests use a fake network.

## Testing

`test/theories/theory_checker_test.dart` (splitting, verdicts and evidence, every status outcome including dependencies, what is sent and not sent, each failure type, no key or offline, merged triggers) and `test/home/theory_banner_test.dart` (the bar and its View button opening the Notes tab on the theory).
