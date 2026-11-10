# Ask

The Ask tab answers questions about the book from what the reader has read, up to the end of the
page they are on, and from nothing after it. The model sees that page, and looks the rest up in the
Story Map, following the paragraph numbers in its evidence back to the book's own text.

## How a question goes

1. The reader asks in the Ask tab.
2. The app works out how far they have read (`askReach`) and freezes that for the whole question.
3. It sends the question, the text of their page, and a short overview: the chapters reached and who
   and what has appeared, with ids. Not the book's title, and not the whole Story Map.
4. The model looks things up with four tools, as often as it needs, up to 10 requests a question.
   The app answers each call from what the reader has read.
5. The answer streams in, citing paragraphs as `[section-004/p0012]` or the page as `[page]`.
   Citations of paragraphs the model wasn't given are removed.
6. Tapping a citation shows the paragraph and its neighbors, without moving the reader. **Open in
   book** goes there.

Each request is paid for and is never retried by itself. A failed question offers **Try again**.

## The boundary

Ask counts the whole page as read. The Story Map counts only what comes before the page's first
element, since a page just turned to hasn't been read; Ask's reader is asking about what they are
looking at. Both use `StoryReadingProgress` and `hiddenWithinSection`; only where they measure to
differs.

| What | Up to | From |
| :--- | :--- | :--- |
| Story Map facts and paragraphs | The last paragraph wholly on the page | `page_end.js` reports the first text block past the page; `StoryBook.paragraphsBeforeBlock` counts the paragraphs before it |
| `CURRENT_PAGE` | The last character on the screen, with about 2,500 characters before it | `textBeforePageEnd`, from the spine item's plain text |

- A paragraph that runs onto the next page isn't counted as read, since a fact cited there may rest
  on its rest. Its part on the page is in `CURRENT_PAGE`.
- `CURRENT_PAGE` doesn't need the Story Map, so a chapter not yet updated can still be asked about.
  It starts a couple of pages back so a pronoun's name is in it. Only in the same spine item, so a
  reader who jumped into the middle of a chapter may get a page or two they skipped.
- On a spine item's last page the page script reports nothing, and the position's progression is
  1.0: the whole item counts as read.
- If the page's end can't be measured (vertical or right-to-left text, or the script failed), Ask
  falls back to the Story Map's boundary and sends no page.
- Everything a tool can reach is in `AskBoundary`, built from that progress. Nothing past it is
  loaded, so no check on each call can be forgotten. An id not reached yet and an id that doesn't
  exist get the same answer.
- When the reader is in chapters the Story Map doesn't cover (past its end, or a stretch it
  skipped), the overview says so, and the model says the map doesn't cover it rather than that the
  story hasn't said.

## The tools

All four read only the boundary. Facts come one per line, with the paragraphs that support them:

```
f000293 · section-008 · reported · according to 佐伯沙弥香 [c001] | 沙弥香向小糸侑表示… | section-008/p0069, section-008/p0077
```

| Tool | Gives |
| :--- | :--- |
| `find_facts(query)` | Facts that mention any of the words |
| `get_entity(entity_id)` | What is known about one character, place or group, as the character card shows it |
| `get_chapter(section_id)` | Who first appeared in a chapter, its events, relationships, changes and questions |
| `read_paragraphs(refs, context)` | The book's text for up to 20 references, with up to 3 neighbors on each side |

Each answer is cut at 8,000 characters. The overview lists at most 300 entities, the most mentioned.

## Requests

`ask_stream.dart` posts to the provider's Responses API with `stream: true`. Text deltas are only
shown; tool calls, usage and how the reply ended are read from the final event's full response. A
reply that goes quiet for 3 minutes is given up on.

Within a question, each request's output items (reasoning, tool calls) go back unchanged with the
tools' answers. OpenAI stores nothing (`store: false`), so its reasoning comes back sealed
(`include: ["reasoning.encrypted_content"]`). Tried with `gpt-6.1-terra` on OpenAI; DeepSeek's
Responses API documents the same function calls and events but hasn't been run.

The conversation so far goes with a new question as plain question and answer: all of it, in
order, and nothing from the book's other conversations. It isn't cut to where the reader is now. A
reader who asked something has read that far, so turning back a few chapters and asking again in
the same conversation keeps what it already said. The tools and the page still stop at the reader.

Only the question and answer text go back, not the pages and lookups behind earlier answers, so the
history stays small. A new question's own requests repeat its start, so providers that cache a
repeated start (OpenAI and DeepSeek do it by themselves) charge less for all but the first.

Debug and profile builds log each question's tokens as a `LOREMARK_ASK_USAGE` line: the status, how
many earlier questions went with it, the totals of input, cached input and output, and each
request's `[input, cached, output]`. On the iOS simulator:

```bash
xcrun simctl spawn <udid> log show --last 1h --predicate 'process == "Runner"' | grep LOREMARK_ASK_USAGE
```

## Conversations

A book can have many conversations. Each is saved once its first question is answered, as
`library/chats/<book id>/<conversation id>.json`.

- Opening a book starts a new conversation, so leaving the book or the app and coming back does too.
- Leaving the Ask tab, or the app, for 5 minutes or more (`askIdleGap`) and coming back also starts
  a new one. Back sooner, the reader is where they left off.
- **New conversation** in the strip above the thread starts one by hand. **Conversations** lists
  the book's saved ones, the latest first, by their first question; tapping one carries it on, and
  each can be deleted.
- Nothing switches while a question is under way.
- A book's one conversation from before there could be several (`library/chats/<book id>.json`)
  becomes a conversation of its own the first time the list is read.

## Files

| File | Holds |
| :--- | :--- |
| `lib/ask/ask_boundary.dart` | `AskReach`, `AskPage`, `AskBoundary`: what an answer may draw on |
| `lib/ask/story_lookup.dart` | The overview and the four tools |
| `lib/ask/ask_stream.dart` | One streamed request |
| `lib/ask/ask_engine.dart` | A question: requests, tool calls, history |
| `lib/ask/ask_citations.dart` | Reading and cleaning citations |
| `lib/ask/ask_history.dart` | Each book's conversations, in `library/chats/<book id>/<conversation id>.json` |
| `lib/ask/ask_controller.dart` | The tab's state, kept above `AiLock` so going offline loses nothing |
| `lib/ask/ask_backend.dart` | What Ask needs from the device; `DeviceStoryMapBackend` provides it |
| `lib/home/ask_screen.dart` | The tab |
| `assets/chat/answer_v1.txt` | The prompt |

Ask's model and effort are set in Settings, apart from Story Map updates (`chat_model`,
`chat_effort`), and default the same way.

## Trying a question by hand

```bash
dart run tool/ask/run.dart --epub=book.epub --store=some/store \
  --through=section-005:40 --model=gpt-6.1-terra --effort=high --question="Who is Lena?"
```

`--through=<section>:<n>` puts the reader after the first n paragraphs of that section, and
`--through=<section>` at its end. The page is the last 2,500 characters read. `--dry-run` prints the
first request, and `--tool=get_entity --args='{"entity_id":"c001"}'` runs one lookup; neither sends
anything. Otherwise the key comes from `OPENAI_API_KEY` or `DEEPSEEK_API_KEY`.

## Tests

- `test/ask/story_lookup_test.dart` calls every tool with every id at points through seeded books,
  partway through sections included, and checks nothing learned later comes back.
- `test/ask/ask_engine_test.dart` plays a model that asks for everything there is, and checks that
  no request body holds anything past the reader.
- Page ends: `test/reader/page_end_test.dart`, `test/story_update/story_progress_test.dart`,
  `test/story_map/story_map_backend_test.dart`.
- The tab: `test/home/ask_screen_test.dart`, `test/ask/ask_controller_test.dart`.

## Known limits

- **Open in book** moves the saved position back, and with it the boundary, until the reader turns
  forward again. The Story Map does the same; a stored furthest position would fix both.
- A fact's wording was written by a model that had read its whole section. Partway through a
  section, a fact shows only after its last citation, and an inferred one only at the section's end,
  but its words can still lean on later paragraphs of that section. The Story Map has the same risk.
