# Opening recap

When a book opens, a "welcome back" pop-up offers a recap of the story up to
the end of the last section the reader finished (use case 1). The recap itself
shows in the Ask tab. It is one paid request to the reader's own provider, sent
only when they press **Catch me up**.

## What the reader sees

1. **On the Read tab,** each time the book opens, a pop-up says where the
   reader stopped ("Last time you finished Chapter 3: The Letter") with **Catch
   me up** and **Keep reading** (use case 1, steps 1 to 3). The book behind it
   is dimmed and blurred, so it is answered before reading on
   (`showWelcomeBack`).
   - It shows only once the reader has finished a section, with an API key, and
     online. Otherwise there is nothing it could do.
   - **Keep reading**, or tapping beside it, puts it away until the book is
     opened again.
   - Readium draws the book natively. If a phone can't blur a native view, the
     book is still dimmed.
2. **Catch me up** sends one request and opens the Ask tab. While it runs, the
   buttons are off, so one press is one request.
3. **The recap** is four to eight numbered moments in story order, the last one
   where the reader stopped. Each has a short title, a one- or two-sentence
   summary and its chapter. A moment the Story Map has a quote for has **View
   passage**, which shows the book's own words.
   - **Read it in the book** under a quote opens the Read tab at that passage,
     highlighted. **Back to your page** then returns the reader to where they
     were, or the × keeps them at the passage.
   - Quotes are only looked for in the sections the reader has finished, so the
     button never opens the book past them. A quote the book doesn't contain
     word for word is looked for by its first six words, with curly and
     straight quotes treated alike. A quote that still isn't found shows
     without the button.
4. **Back to the book →** returns to the Read tab. **New recap** asks again,
   which is another paid request.
5. **If it fails,** the tab says why (a rejected key, no credit, no connection,
   a busy provider) and offers **Try again**. Nothing retries by itself.
6. **The Ask tab on its own** shows where the recap would stop and its own
   **Catch me up**, so a reader who closed the pop-up can still get one. Before
   the reader finishes a section, it says to read on instead (use case 1,
   exception 1a).

Ask is locked without a key or a connection (`AiLock`).

## How it fits together

- `RecapController` (`lib/recap/recap_controller.dart`) holds one open book's
  recap. `BookScreen` makes it and shares it with the pop-up
  (`lib/home/welcome_back_card.dart`) and the Ask tab
  (`lib/home/ask_screen.dart`), so a recap started from the pop-up shows in
  Ask.
- **Read it in the book** goes through `PassageJumpController`
  (`lib/home/read_screen.dart`), like a tapped note goes through
  `NoteJumpController`. Where each quote is (`RecapQuote.target`) is worked out
  with search's `buildPassageTarget`, when the recap's source is built.
- It looks for the reader's place when the book opens (once there is a key),
  and again each time the Ask tab opens, since the reader may have read on. A
  slower, older look can't replace a newer one.
- `RecapBackend` is what it needs from the device and the network, so tests can
  stand in for both. `DeviceRecapBackend` is the real one.

## What is sent

`RecapSource` (`lib/recap/recap_source.dart`) decides, and nothing else is sent:

- **Where it stops:** the end of the last finished section, worked out from the
  saved position the same way the Story Map does (`finishedStorySections`). A
  section counts once the reader has turned past its end, so the one they are
  in, even on its last page, doesn't count yet.
- **Story facts, if the book has a Story Map:** the snapshot of the model as of
  the last story section the reader finished, never a later one, even if the map
  was built past the reader. That is the 15 most recent events, the characters
  met so far, and open questions. Each event goes with an ID (`E1`, `E2`, ...)
  and its chapter. Flashbacks are marked, so they aren't told as happening now.
- **Text:** the end of one section, at most 12,000 characters. The privacy
  requirement is that a request never carries more than one chapter, so the
  book so far is never sent. Footnotes and nearly empty pages are stepped over.
- **Not sent:** notes and theories, which are the reader's views, not facts
  about the book, and the Story Map's quotes, which stay on the device for
  **View passage**.

The prompt (`recapPrompt` in `lib/recap/recap_client.dart`) marks the book's
text as data, and tells the model not to mention anything past the cutoff even
if it knows the book.

## The request

`requestRecap` uses the Story Map's `callResponsesApi`, so it works with OpenAI
and DeepSeek the same way: a JSON-schema answer, the key kept out of anything
saved, and no retries. A recap uses the provider's default model (DeepSeek
Flash, or GPT-6.1 Terra) with low reasoning effort, since reasoning is billed
as output. It gives up after two minutes.

The answer is a list of `items`, each with a `title`, a `summary` and the
`event_ids` it is based on. `parseRecap` checks it:

- A moment without a title or a summary is dropped, and at most eight are kept.
- A moment's chapter and quotes come from the events it names. IDs that weren't
  sent are ignored, so a made-up one can't attach a chapter or a quote the
  reader hasn't reached. A moment with no known events is placed at the end of
  the last finished section.
- An answer with no usable moment is turned away, not shown.

A recap is roughly 15,000 tokens in and 500 out, about half a cent with
DeepSeek Flash.

## Tests

- `test/recap/recap_source_test.dart`: nothing past the cutoff, with and
  without a Story Map, including a map built past the reader.
- `test/recap/recap_client_test.dart`: the request for each provider, how
  moments are checked, and the messages for each failure, with a fake provider.
- `test/recap/recap_controller_test.dart`: one request at a time, and an older
  look at the reader's place never replacing a newer one.
- `test/home/ask_screen_test.dart`: the Ask tab, with a fake backend.
- `test/home/read_screen_passage_test.dart`: opening the book at a passage,
  and **Back to your page**.
- `test/widget_test.dart` (`welcome back`): the pop-up over the Read tab, and
  **Catch me up** opening Ask with the recap.

None of them call a real provider.

## Not done yet

- **Whole paragraphs.** **View passage** shows the Story Map's short quotes.
  Frank's `feat/ai-chat` branch (#80) reads the Story Map's paragraphs
  (`StoryParagraphs`). Once it is on `main`, **View passage** can show the whole
  paragraph behind each moment instead.
- **Keeping the reader's place after a jump.** Like a jump to a note or a
  search hit, **Read it in the book** moves the saved position. If the reader
  closes the book there instead of going back, it reopens at the passage. The
  furthest position (#53) would keep the recap's stopping point.
- **Choosing another stopping point** (use case 1, 2a).
- **More**, to carry on in the chat (use case 1, 3a). That waits for the Ask
  chat (use case 6), which can reuse `RecapSource` and `callResponsesApi`.
- **The furthest position.** The recap stops at the saved position, so turning
  back to reread moves it back. Once the progress tracker (#53) keeps the
  furthest position, use it in `DeviceRecapBackend.prepare`.
- **Notes in the recap.** The use case's welcome-back recap mentions the
  reader's notes. They are left out for now.
- **The reader's name.** The prototype greets the reader by name, but the app
  doesn't ask for one, so the card says "Welcome back."
