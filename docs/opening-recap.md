# Opening recap

When a book opens, a "welcome back" pop-up offers a recap of the story up to
where the reader stopped (use case 1). The recap itself shows at the top of
the Ask tab, above the Ask conversation (use case 6), so a follow-up question
goes right below it (use case 1, 3a). It is one paid request to the reader's own provider, sent only when they press
**Catch me up**.

A recap is built from the book's Story Map and stops exactly where the Story
Map stops: down to the page, partway through a chapter. A book without a Story
Map has no recap.

## What the reader sees

1. **On the Read tab,** each time the book opens, a pop-up says where the
   reader stopped ("Last time you stopped partway through Chapter 3: The
   Letter", or "Last time you finished Chapter 2: …") with **Catch me up** and
   **Keep reading** (use case 1, steps 1 to 3). The book behind it is dimmed
   and blurred, so it is answered before reading on (`showWelcomeBack`).
   - It shows only with a Story Map, once the reader has read some of what it
     covers, with an API key, and online. Otherwise there is nothing it could
     do.
   - **Keep reading**, or tapping beside it, puts it away until the book is
     opened again.
   - Readium draws the book natively. If a phone can't blur a native view, the
     book is still dimmed.
2. **Catch me up** sends one request and opens the Ask tab, scrolled to the
   recap at its top. While it runs, the buttons are off, so one press is one
   request.
3. **The recap** is four to eight numbered moments in story order, the last one
   where the reader stopped. Each has a short title, a one- or two-sentence
   summary and its chapter. A moment the Story Map has evidence for has **View
   passage**, which shows the paragraphs of the book it cites.
   - **Read it in the book** under a paragraph opens the Read tab at it,
     highlighted. **Back to your page** then returns the reader to where they
     were, or the × keeps them at the passage.
4. **Back to the book →** returns to the Read tab. **New recap** asks again,
   which is another paid request. "Questions about it? Ask below." points to the
   Ask conversation under the recap.
5. **If it fails,** the tab says why (a rejected key, no credit, no connection,
   a busy provider) and offers **Try again**. Nothing retries by itself.
6. **The top of the Ask tab on its own** shows where the recap would stop and
   its own **Catch me up**, so a reader who closed the pop-up can still get
   one.
   - Without a Story Map, or before the reader has read any of what it covers
     (use case 1, exception 1a), it shows nothing: Ask's own line under the
     header already says what the Story Map covers and offers to open it.
   - If the reader has read everything the map holds, it offers **Read
     further? Update your Story Map →**, which opens the Story Map tab: the map
     is only updated when they ask, so it can be behind them.

Ask is locked without a key or a connection (`AiLock`).

## The boundary

The recap uses the Story Map's reading progress, so it never disagrees with
the map:

- `StoryMapBackend.readingProgress` gives how many sections the reader has
  turned past, and, if they are partway through the next one, how many of its
  paragraphs and which of its records they haven't reached (`hiddenInNext`).
  "Read" means turned past: the page on screen doesn't count yet.
- **Facts** come from `StorySnapshot(model, section, hidden: hiddenInNext)`.
- **Text** comes from `StoryMapBackend.paragraphs(book, progress)`, which holds
  only what the reader has read. Nothing past it is at hand, so nothing past it
  can be sent or shown.
- The two come from one look at the progress, so they stop at the same
  paragraph.

Turning back moves the recap back too. A recap belongs to the place it was
written for (`RecapPlace`: sections finished, paragraphs read in the next one,
and the map's revision). When the reader turns back, reads on or updates the
map, the old recap is dropped and **Catch me up** asks again.

## How it fits together

- `RecapController` (`lib/recap/recap_controller.dart`) holds one open book's
  recap. `BookScreen` makes it and shares it with the pop-up
  (`lib/home/welcome_back_card.dart`) and `RecapPanel`
  (`lib/home/recap_panel.dart`), so a recap started from the pop-up shows in
  Ask.
- `RecapPanel` is passed to the Ask tab as `AskScreen.recap`, which puts it
  above the conversation, or above its empty state (`EmptyState.top`) before
  the first question. The Ask conversation itself is separate
  (`AskController`, see [ask.md](ask.md)). When a recap starts or arrives, the
  panel scrolls itself into view, since the conversation may have been
  scrolled to its end.
- It looks for the reader's place when the book opens (once there is a key),
  and again each time the Ask tab opens, never on a page turn. A slower, older
  look can't replace a newer one.
- `RecapBackend` is what it needs from the device and the network, so tests can
  stand in for both. `DeviceRecapBackend` is the real one. It uses the same
  `StoryMapBackend` as the Story Map tab, which `BookScreen` passes in.
- `RecapBackend.prepare` returns a `RecapStart`: `RecapNeedsStoryMap`,
  `RecapNeedsReading`, or `RecapCanStart` with the `RecapSource`.
- **Read it in the book** goes through `PassageJumpController`
  (`lib/home/read_screen.dart`), which adds **Back to your page**. An Ask
  answer's citations go through `NoteJumpController.showPassage` instead, since
  they are usually on the reader's recent pages. Each paragraph's place (`RecapPassage.target`) is its
  section's document and its first words, which Readium finds on the page. If
  they aren't found, a paragraph in the chapter being read opens at the
  chapter's start, never past the reader.

## What is sent

`RecapSource` (`lib/recap/recap_source.dart`) decides, and nothing else is sent:

- **Where it stops,** such as "partway through Chapter 3: The Letter".
- **Story facts:** the 15 most recent events the reader knows, the characters
  met so far, and open questions. Each event goes with an ID (`E1`, `E2`, ...)
  and its chapter. Flashbacks are marked, so they aren't told as happening now.
- **Text:** the last 12,000 characters the reader read, ending where they
  stopped. When they are only a little way into a chapter, it starts in the one
  before, and each part starts with its chapter's title. The privacy
  requirement is that a request never carries more than one chapter, so the
  book so far is never sent.
- **Not sent:** notes and theories, which are the reader's views, not facts
  about the book, and the passages behind each event, which stay on the device
  for **View passage**.

The prompt (`recapPrompt` in `lib/recap/recap_client.dart`) marks the book's
text as data, and tells the model not to mention anything past where the text
ends, even partway through a chapter and even if it knows the book.

## The request

`requestRecap` uses the Story Map's `callResponsesApi`, so it works with OpenAI
and DeepSeek the same way: a JSON-schema answer, the key kept out of anything
saved, and no retries. A recap uses the provider's default model (DeepSeek
Flash, or GPT-6.1 Terra) with low reasoning effort, since reasoning is billed
as output. It gives up after two minutes.

The answer is a list of `items`, each with a `title`, a `summary` and the
`event_ids` it is based on. `parseRecap` checks it:

- A moment without a title or a summary is dropped, and at most eight are kept.
- A moment's chapter and passages come from the events it names. IDs that
  weren't sent are ignored, so a made-up one can't attach a chapter or a
  passage the reader hasn't reached. A moment with no known events is placed in
  the chapter where the reader stopped.
- An answer with no usable moment is turned away, not shown.

A recap is roughly 15,000 tokens in and 500 out, about half a cent with
DeepSeek Flash.

## Tests

- `test/recap/recap_source_test.dart`: the boundary. Two paragraphs into a
  chapter, nothing from paragraph 3 on reaches the prompt or the screen; a
  record in `hiddenInNext` reaches neither; turning back or updating the map is
  a new place.
- `test/recap/recap_backend_test.dart`: no Story Map, nothing read yet, one
  look at the progress for both facts and text, and text that can't be read
  failing the recap.
- `test/recap/recap_controller_test.dart`: no request when nothing is read, an
  old recap never shown after turning back, an error and no recap when the text
  can't be read, and one request at a time.
- `test/recap/recap_client_test.dart`: the request for each provider, how
  moments are checked, and the messages for each failure, with a fake provider.
- `test/home/recap_panel_test.dart`: the recap at the top of the Ask tab, with
  a fake backend.
- `test/home/read_screen_passage_test.dart`: opening the book at a passage,
  and **Back to your page**.
- `test/widget_test.dart` (`welcome back`): the pop-up over the Read tab, and
  **Catch me up** opening Ask with the recap.

`test/recap/recap_test_book.dart` is the small book they share: the Story Map
fixture's two chapters, with paragraphs that say which they are, such as
"[s2 p3]", and a fake `StoryMapBackend`. None of the tests call a real
provider.

## Not done yet

- **Choosing another stopping point** (use case 1, 2a).
- **More**, to carry on in the chat (use case 1, 3a). That waits for the Ask
  chat (use case 6), which can share the same boundary.
- **Notes in the recap.** The use case's welcome-back recap mentions the
  reader's notes. They are left out for now.
- **The reader's name.** The prototype greets the reader by name, but the app
  doesn't ask for one, so the pop-up says "Welcome back."
- **Keeping the reader's place after a jump.** Like a jump to a note or a
  search hit, **Read it in the book** moves the saved position. If the reader
  closes the book there instead of going back, it reopens at the passage, and
  the recap follows it.
