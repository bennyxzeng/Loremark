# Opening recap

When a book opens, a "welcome back" pop-up offers a recap of the story up to
where the reader stopped (use case 1). **Catch me up** opens the Ask tab on a
new conversation that starts with the recap, so the reader can ask more about
it right there (use case 1, 3a), or go back to reading.

The recap is an Ask question like any other, asked with its own prompt. It
uses Ask's boundary, Ask's tools and Ask's model settings, and it is kept with
the book's Ask conversations. See [ask.md](ask.md) for how Ask works.

## What the reader sees

1. **On the Read tab,** each time the book opens, a pop-up says where the
   reader stopped ("Last time you stopped partway through Chapter 3: The
   Letter", or "Last time you finished Chapter 2: …") with **Catch me up** and
   **Keep reading** (use case 1, steps 1 to 3). The book behind it is dimmed
   and blurred, so it is answered before reading on (`showWelcomeBack`).
   - It shows only for a book with a Story Map, once the reader has read some
     of what it covers, with an API key, and online.
   - **Keep reading**, or tapping beside it, puts it away until the book is
     opened again.
   - Readium draws the book natively. If a phone can't blur a native view, the
     book is still dimmed.
2. **Catch me up** opens the Ask tab on a new conversation. The conversation
   shown before stays in Ask's list of conversations.
3. **The recap** shows as Ask's answer to "Catch me up on the story so far.":
   four to eight numbered moments in story order, the last one where the
   reader stopped, each with a short title, a sentence or two, and citation
   numbers. Tapping a citation shows the passage, and **Open in book** goes
   there.
4. **Back to your page.** Opening any passage an Ask answer cites, in a recap
   or not, offers **Back to your page** over the book, to return to where the
   reader was. Its × keeps them at the passage and takes the highlight off.
5. **Follow-up questions** go in the same conversation, with Ask's usual
   prompt. The recap is part of the conversation they see.

## How it fits together

- `RecapController` (`lib/recap/recap_controller.dart`) finds where the reader
  stopped when the book opens, from the Story Map's own progress
  (`StoryMapBackend.readingProgress`), so the pop-up names the place the map
  shows up to. `RecapBackend.prepare` returns a `RecapStart`:
  `RecapNeedsStoryMap`, `RecapNeedsReading`, or `RecapCanStart` with the
  `RecapStop`.
- `BookScreen` shows the pop-up the first time it knows, and on **Catch me up**
  calls `AskController.catchUp` and opens the Ask tab.
- `AskController.catchUp` starts a new conversation and asks
  `askRecapQuestion` with the recap prompt, `assets/chat/recap_v1.txt`, in place
  of Ask's `answer_v3.txt`. A failed recap is tried again as a recap.
- **Back to your page** is `PassageJumpController` (`lib/home/read_screen.dart`).
  `BookScreen` sends Ask's citations through it.

## The boundary

The recap is written from what Ask may see: the reader's recent pages, up to
the end of the page they are on, and the Story Map up to there (see
[ask.md](ask.md)). Nothing past their page is sent. The pop-up names the Story
Map section the reader is in, which is measured to the start of their page, so
it can say "partway through" a chapter whose end the recap won't mention.

The recap prompt keeps Ask's rules: only what the reader has read, nothing
about what happens later even if the model knows the book, flashbacks told as
the past, and the book's text treated as data. If the reader is past what the
Story Map covers, the recap says so in a line.

## Tests

- `test/ask/ask_recap_test.dart`: **Catch me up** starts a new conversation,
  asked with the recap prompt and kept; a follow-up uses Ask's prompt and sees
  the recap; a failed recap is retried as a recap; nothing is sent with
  nothing read, or while another question is under way.
- `test/recap/`: where the reader stopped, and when there is no recap to offer.
- `test/home/read_screen_passage_test.dart`: opening the book at a passage,
  and **Back to your page**.
- `test/widget_test.dart` (`welcome back`): the pop-up over the Read tab, and
  **Catch me up** opening Ask with the recap question.

None of them call a real provider.

## Not done yet

- **Choosing another stopping point** (use case 1, 2a).
- **Notes in the recap.** The use case's welcome-back recap mentions the
  reader's notes. They are left out for now.
- **The reader's name.** The prototype greets the reader by name, but the app
  doesn't ask for one, so the pop-up says "Welcome back."
- **Keeping the reader's place after a jump.** If the reader closes the book at
  a passage instead of going **Back to your page**, it reopens there.
