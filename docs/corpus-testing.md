# Testing the table of contents and search on 50 real books

Owner: Kevin. Scripts: [`tool/corpus/`](../tool/corpus/). Tests: [`test/corpus/`](../test/corpus/). How to rerun it: [tool/corpus/README.md](../tool/corpus/README.md).

**Contents:** [What was tested](#what-was-tested) · [The books](#the-books) · [How](#how) · [What it found](#what-it-found-and-what-changed) · [Results](#results) · [What this does not prove](#what-this-does-not-prove)

## What was tested

Two features, on real books instead of the one or two we had been using:

1. **The table of contents.** A book with no usable contents list gets sections of about 5,000 words; choosing a chapter jumps to it; the chapter bar names the right chapter.
2. **Page-by-page spoiler-safe search** ([search.md](search.md)). Search finds text you have read up to the page you are on, and never text past it.

"Working correctly" means, in plain terms:

- the book opens, and a damaged file is refused with a message, not a crash;
- every book gets a contents list, made by us if the book has none;
- choosing an entry lands on that chapter, and the bar says so;
- a word before your place is found, a word after it is not, even one character short of a paragraph's end;
- the position we compute for the end of a page is the position in the text that the page really ends at.

## The books

50 public-domain books from Project Gutenberg, chosen for variety, plus 24 files made from them for the cases real books rarely show.

| | |
| :-- | :-- |
| **Languages (18)** | English 18, French 4, German 4, Spanish 3, Chinese 3, Italian 2, Portuguese 2, Dutch 2, Finnish 2, Japanese 2; one each of Latin, Greek, Esperanto, Hungarian, Polish, Russian, Hebrew, Arabic, Swedish |
| **Length** | 5,000 to 1,850,000 words; files from 80 KB to 85 MB. Includes War and Peace, Les Misérables, Don Quixote, the Count of Monte Cristo, a Bible, the complete Shakespeare (about one million words) and a 1.8-million-word dictionary |
| **Direction and script** | Latin, Cyrillic, Greek, Chinese, Japanese, Hebrew and Arabic (right to left) |
| **Layout** | one chapter per file, many chapters in one file (Gatsby), and books of thousands of short files; books with large images |

The 24 made files, each built from one of the books and marked as synthetic in the results:

| Kind | How it was made | Count |
| :-- | :-- | --: |
| `notoc` | contents document and NCX removed | 12 |
| `ghosttoc` | every contents link points to a file that does not exist | 3 |
| `onelink` | only the first contents link works | 2 |
| `onefile` | every chapter file merged into one, with the contents pointing into it | 4 |
| `truncated` | the first 60 percent of the zip | 2 |
| `notepub` | a text file named `.epub` | 1 |

Real EPUBs nearly always have a contents list, so the "no table of contents" cases are made, not found. One real book did lack a usable one: the Russian *1001 problems* (id 16527), which got sections on its own.

## How

**On the computer** ([`test/corpus/corpus_test.dart`](../test/corpus/corpus_test.dart)): every file goes through the app's own code, not a copy of it.

- Open it, read the text of every section, count the words.
- Build the 5,000-word sections and check they are in order, start where text is, and number about one per 5,000 words.
- Build the search index, save it, load it back, and check the passages cover the text exactly, with nothing lost or repeated.
- Search, 40 times per book: pick a random place in the book. A word that occurs in only one passage before that place must be found. A word that occurs in only one passage after it must not be. Every hit must be before the place. One character before the end of a passage, that passage must be hidden; at its exact end, shown. The same answers must come from the index read back from disk. Queries are quoted so the last word is not also a prefix.
- Page ends: for random blocks of text and positions inside them, compute where the page ends two ways, the app's way and an independent way (count the non-space characters in the markup in front of the block, then find that many in the plain text), and require the same answer. Also require that the 12-character check is accepted for the true tail and refused for a wrong one.

**On the emulator** ([`tool/corpus/device_run.py`](../tool/corpus/device_run.py)): the real renderer. For each of 38 books: add it to the app, open it fresh, search for a word from 20 to 30 percent in (must be hidden at the start), page forward 24 pages while reading the page-end reports, open Contents and scroll it, jump to the middle entry and check the page landed there and the bar names it, then search again (the word from 20 to 30 percent must now be found, and a word from 88 to 95 percent must stay hidden).

**Edge cases** ([`test/corpus/edge_cases_test.dart`](../test/corpus/edge_cases_test.dart), part of normal CI): awkward markup and text built by hand: entities, CDATA, comments, ruby, scripts, markup that is not XML, 400 nested elements, a 2 MB paragraph with no full stop, 20,000 tiny paragraphs, random punctuation, strange search queries (empty, regular-expression characters, 20,000 letters, emoji, a NUL), right-to-left text.

A test that cannot fail proves nothing, so the cutoff rule was broken on purpose by one character; the corpus test caught it in all three books tried.

## What it found and what changed

Everything below was found by this testing and fixed on this branch.

1. **Right-to-left books reported every file as finished on its first page.** Readium numbers the pages of a right-to-left file backwards (113 of 114 first, then 112). The reader treated "page number is the last one" as "last page", so the first page looked like the last, the position said "section finished", and search opened the whole file. Seen on the Hebrew book: the saved position was `progression 1.0` on page one. Fixed: the page index is read in the direction the progression runs, checked for every page of files of 1 to 200 pages in both directions. This was a spoiler leak, present before page-level search.
2. **Choosing a chapter in another file landed on its last page.** Readium opens a file you jump into at its end and ignores the chapter. The reader now asks again once the file shows. This was the Gatsby bug.
3. **The chapter bar named the last chapter in the file** (Gatsby always said "V"), and after a jump it could name the chapter before the one chosen, because the renderer names a page's chapter by its first line. It now uses the renderer's chapter, and keeps the chosen one until the reader moves off the landing page, including when the jump is slow.
4. **Sections for a book without a table of contents** did not exist; they are now made (and built off the UI thread, since the largest book took over a second).
5. **A safety check on the page-end position.** The page script now sends the last 12 characters before the page end, and the app drops the report if its own text disagrees, so a miscount between the web view and our copy of the chapter can only make search more cautious.

Things that looked like bugs and were not, worth knowing when reading the test code:

- Search stems words and treats the last word typed as a prefix, so a rare word can match a longer or inflected word in an earlier paragraph. Test queries are quoted and "rare" is judged on the indexed term, not the spelling.
- A one-character block (a "—" table cell, a "*" scene break) has no second character, so a page cannot end after it; the app correctly returns nothing.
- The first search in a long book waits for the index to be built; the driver now waits for an answer.

## Results

The numbers below come from `tool/corpus/report.py` over the last run of each file. A book that appears twice in the device table was run again after a fix; the table shows the last run.

**In short.**

- **Host:** all 74 files passed every check. Search found 2,835 of 2,835 words before the cutoff and hid 2,835 of 2,835 after it; the page-end positions matched the independent calculation every time.
- **Device:** all 38 books opened, paged, listed their Contents, jumped to the middle entry and named it in the bar. The web view sent 775 page-end reports and the 12-character check rejected none.
- **Not fully checked on the device:** the "a word from late in the book stays hidden" search. In 11 books (marked *unclear* below) the search answered with hits for related words ("steel" beside "steeled"), so the driver, which reads the screen, could tell the exact word was not shown but not that nothing past the cutoff was. The computer checks cover exactly this case (see Results, host totals). See [Open item](#open-item).

### Host results: every file through the app's own code

74 files (50 downloaded books, 24 made from them). 74 passed every check, 0 reported a problem.

| File | Lang | Size | Words | Sections | Parse | Text | Index | Index file | Pieces | Query p50 | Auto sections | Search | Page ends |
| :-- | :-: | --: | --: | --: | --: | --: | --: | --: | --: | --: | --: | :-: | :-: |
| notepub (notepub) |  | 1 KB | | | | | | | | | | refused: FormatException | |
| Frankenstein; or, The mo (truncated) | en | 258 KB | | | | | | | | | | refused: FormatException | |
| Pride and Prejudice (truncated) | en | 14.2 MB | | | | | | | | | | refused: FormatException | |
| Tribute to Michael Hart (notoc) | ar | 64 KB | 5,045 | 3 | 39 ms | 17 ms | 49 ms | 26 KB | 111 | 0.22 ms | 0 | 39/39, 39 hidden | 64/64 |
| Tribute to Michael Hart | ar | 78 KB | 5,045 | 3 | 0 ms | 3 ms | 23 ms | 26 KB | 111 | 0.23 ms | 0 | 39/39, 39 hidden | 64/64 |
| \u7f85\u751f\u9580 (ghosttoc) | ja | 72 KB | 6,901 | 3 | 0 ms | 2 ms | 25 ms | 30 KB | 107 | 0.11 ms | 0 | 40/40, 40 hidden | 64/64 |
| \u7f85\u751f\u9580 | ja | 84 KB | 6,901 | 3 | 0 ms | 2 ms | 16 ms | 30 KB | 107 | 0.10 ms | 0 | 40/40, 40 hidden | 64/64 |
| Mallonga biografio de Henry Fawcet | eo | 440 KB | 7,092 | 15 | 0 ms | 5 ms | 33 ms | 30 KB | 177 | 0.25 ms | 0 | 39/39, 39 hidden | 96/96 |
| Kaksi morsianta : $b Yksin\xe4yt\x | fi | 100 KB | 7,868 | 3 | 0 ms | 4 ms | 32 ms | 41 KB | 311 | 0.07 ms | 2 | 40/40, 40 hidden | 64/64 |
| The Yellow Wallpaper | en | 224 KB | 9,127 | 3 | 0 ms | 5 ms | 29 ms | 33 KB | 346 | 0.05 ms | 2 | 40/40, 40 hidden | 64/64 |
| Metamorphosis | en | 310 KB | 25,063 | 6 | 0 ms | 11 ms | 104 ms | 77 KB | 437 | 0.21 ms | 5 | 40/40, 40 hidden | 96/96 |
| Urwald | de | 5.1 MB | 25,327 | 13 | 1 ms | 28 ms | 93 ms | 125 KB | 670 | 0.09 ms | 5 | 40/40, 40 hidden | 128/128 |
| Alice's Adventures in Wo (notoc) | en | 181 KB | 29,568 | 15 | 0 ms | 21 ms | 126 ms | 92 KB | 929 | 0.24 ms | 6 | 40/40, 40 hidden | 128/128 |
| Alice's Adventures in Wonderland | en | 185 KB | 29,568 | 15 | 1 ms | 20 ms | 131 ms | 92 KB | 929 | 0.20 ms | 6 | 40/40, 40 hidden | 128/128 |
| 1001 \u0437\u0430\u0434\ (notoc) | ru | 130 KB | 30,072 | 4 | 0 ms | 16 ms | 122 ms | 110 KB | 1,079 | 0.11 ms | 6 | 40/40, 40 hidden | 96/96 |
| 1001 \u0437\u0430\u0434\u0430\u044 | ru | 145 KB | 30,072 | 4 | 0 ms | 17 ms | 133 ms | 110 KB | 1,079 | 0.10 ms | 6 | 40/40, 40 hidden | 96/96 |
| A Christmas Carol in Pro (onefile) | en | 620 KB | 31,763 | 1 | 0 ms | 19 ms | 118 ms | 111 KB | 930 | 0.10 ms | 6 | 40/40, 40 hidden | 32/32 |
| A Christmas Carol in Prose; Being  | en | 626 KB | 31,763 | 4 | 0 ms | 18 ms | 125 ms | 111 KB | 930 | 0.11 ms | 6 | 40/40, 40 hidden | 64/64 |
| Lintukoto : $b Muutamia p\xe4iv\xe | fi | 190 KB | 35,616 | 4 | 0 ms | 23 ms | 177 ms | 223 KB | 1,331 | 0.09 ms | 7 | 40/40, 40 hidden | 96/96 |
| Pan Tadeusz: Czyli Ostatni Zajazd  | pl | 1.2 MB | 35,979 | 6 | 1 ms | 43 ms | 229 ms | 192 KB | 749 | 0.29 ms | 7 | 40/40, 40 hidden | 96/96 |
| The Great Gatsby | en | 345 KB | 51,181 | 4 | 0 ms | 30 ms | 204 ms | 180 KB | 1,844 | 0.14 ms | 10 | 40/40, 40 hidden | 96/96 |
| Les enchantements de la for\xeat | fr | 5.1 MB | 52,104 | 29 | 1 ms | 31 ms | 280 ms | 197 KB | 1,384 | 0.21 ms | 10 | 40/40, 40 hidden | 160/160 |
| En pays lointain (onelink) | fr | 300 KB | 55,719 | 14 | 0 ms | 33 ms | 264 ms | 212 KB | 1,739 | 0.16 ms | 11 | 39/39, 39 hidden | 128/128 |
| En pays lointain | fr | 324 KB | 55,719 | 14 | 0 ms | 34 ms | 263 ms | 212 KB | 1,739 | 0.20 ms | 11 | 40/40, 40 hidden | 160/160 |
| Skizzen einer Fu\xdfreise durch Oe | de | 669 KB | 63,012 | 17 | 0 ms | 39 ms | 214 ms | 301 KB | 1,519 | 0.09 ms | 13 | 40/40, 40 hidden | 160/160 |
| Aeneidos (notoc) | la | 246 KB | 66,804 | 6 | 0 ms | 48 ms | 223 ms | 338 KB | 1,504 | 0.09 ms | 13 | 40/40, 40 hidden | 96/96 |
| Aeneidos | la | 259 KB | 66,804 | 6 | 0 ms | 51 ms | 218 ms | 338 KB | 1,504 | 0.08 ms | 13 | 40/40, 40 hidden | 96/96 |
| Lucifer : $b roman moderne | fr | 325 KB | 67,850 | 24 | 0 ms | 41 ms | 348 ms | 243 KB | 1,823 | 0.21 ms | 14 | 40/40, 40 hidden | 160/160 |
| Mathias Sandorf [1] : $b Een verij | nl | 10.4 MB | 70,527 | 14 | 53 ms | 95 ms | 255 ms | 267 KB | 2,545 | 0.09 ms | 14 | 40/40, 40 hidden | 128/128 |
| Tales (notoc) | he | 229 KB | 71,248 | 6 | 0 ms | 46 ms | 350 ms | 343 KB | 3,293 | 0.09 ms | 14 | 40/40, 40 hidden | 128/128 |
| Tales | he | 243 KB | 71,248 | 6 | 0 ms | 45 ms | 341 ms | 343 KB | 3,293 | 0.10 ms | 14 | 40/40, 40 hidden | 96/96 |
| Frankenstein; or, The mo (onefile) | en | 361 KB | 78,106 | 1 | 0 ms | 33 ms | 259 ms | 246 KB | 1,514 | 0.10 ms | 16 | 40/40, 40 hidden | 32/32 |
| Frankenstein; or, The mo (ghosttoc) | en | 401 KB | 78,106 | 32 | 1 ms | 40 ms | 248 ms | 246 KB | 1,514 | 0.11 ms | 16 | 40/40, 40 hidden | 128/128 |
| Frankenstein; or, The modern Prome | en | 430 KB | 78,106 | 32 | 0 ms | 36 ms | 256 ms | 246 KB | 1,514 | 0.13 ms | 16 | 40/40, 40 hidden | 160/160 |
| Andanzas y visiones espa\xf1olas | es | 521 KB | 79,977 | 50 | 1 ms | 43 ms | 239 ms | 293 KB | 1,561 | 0.09 ms | 16 | 40/40, 40 hidden | 128/128 |
| Liebe ist ewig : $b Roma (notoc) | de | 511 KB | 89,980 | 33 | 0 ms | 52 ms | 224 ms | 365 KB | 2,309 | 0.07 ms | 18 | 40/40, 40 hidden | 160/160 |
| Liebe ist ewig : $b Roman | de | 532 KB | 89,980 | 33 | 1 ms | 49 ms | 221 ms | 365 KB | 2,309 | 0.10 ms | 18 | 40/40, 40 hidden | 160/160 |
| La Divina Commedia di Dante | it | 319 KB | 100,873 | 7 | 0 ms | 105 ms | 408 ms | 396 KB | 5,004 | 0.08 ms | 20 | 40/40, 40 hidden | 96/96 |
| Ricordi d'infanzia e di scuola: se | it | 423 KB | 101,453 | 54 | 4 ms | 64 ms | 398 ms | 399 KB | 2,074 | 0.15 ms | 20 | 40/40, 40 hidden | 160/160 |
| Le Fant\xf4me de l'Op\xe (notoc) | fr | 417 KB | 103,977 | 7 | 0 ms | 54 ms | 312 ms | 364 KB | 3,476 | 0.08 ms | 21 | 40/40, 40 hidden | 160/160 |
| Le Fant\xf4me de l'Op\xe9ra | fr | 437 KB | 103,977 | 7 | 0 ms | 60 ms | 324 ms | 364 KB | 3,476 | 0.08 ms | 21 | 40/40, 40 hidden | 128/128 |
| The Adventures of Sherlo (onefile) | en | 353 KB | 107,575 | 1 | 0 ms | 58 ms | 419 ms | 339 KB | 3,205 | 0.15 ms | 22 | 40/40, 40 hidden | 32/32 |
| The Adventures of Sherlock Holmes | en | 371 KB | 107,575 | 15 | 0 ms | 58 ms | 420 ms | 339 KB | 3,205 | 0.20 ms | 22 | 40/40, 40 hidden | 128/128 |
| The Adventures of Sherlo (notoc) | en | 371 KB | 107,575 | 15 | 0 ms | 55 ms | 410 ms | 339 KB | 3,205 | 0.20 ms | 22 | 40/40, 40 hidden | 128/128 |
| Carl Svenske: Historisk ber\xe4tte | sv | 10.4 MB | 119,889 | 35 | 4 ms | 72 ms | 385 ms | 485 KB | 3,432 | 0.09 ms | 24 | 40/40, 40 hidden | 128/128 |
| Gevoel en verstand | nl | 393 KB | 129,509 | 10 | 43 ms | 145 ms | 555 ms | 433 KB | 2,807 | 0.20 ms | 26 | 40/40, 40 hidden | 160/160 |
| Pride and Prejudice | en | 23.7 MB | 130,144 | 9 | 5 ms | 87 ms | 530 ms | 388 KB | 3,105 | 0.24 ms | 26 | 40/40, 40 hidden | 96/96 |
| A Greek-English Lexicon to the New | el,en | 671 KB | 139,440 | 11 | 1 ms | 158 ms | 852 ms | 529 KB | 2,967 | 0.24 ms | 28 | 40/40, 40 hidden | 128/128 |
| \u7075\u5386\u96c6\u5149 (notoc) | zh | 390 KB | 158,176 | 5 | 0 ms | 22 ms | 264 ms | 775 KB | 1,041 | 0.14 ms | 32 | 40/40, 40 hidden | 96/96 |
| \u7075\u5386\u96c6\u5149 | zh | 402 KB | 158,176 | 5 | 0 ms | 21 ms | 251 ms | 775 KB | 1,041 | 0.13 ms | 32 | 40/40, 40 hidden | 96/96 |
| Pet\u0151fi S\xe1ndor \xf6sszes k\ | hu | 9.2 MB | 161,186 | 19 | 1 ms | 349 ms | 821 ms | 802 KB | 7,820 | 0.13 ms | 32 | 40/40, 40 hidden | 128/128 |
| Dracula (onefile) | en | 545 KB | 163,821 | 1 | 0 ms | 81 ms | 652 ms | 481 KB | 3,496 | 0.21 ms | 33 | 40/40, 40 hidden | 32/32 |
| Dracula | en | 589 KB | 163,821 | 33 | 0 ms | 82 ms | 633 ms | 481 KB | 3,496 | 0.19 ms | 33 | 40/40, 40 hidden | 128/128 |
| Dracula (onelink) | en | 592 KB | 163,821 | 33 | 0 ms | 77 ms | 633 ms | 481 KB | 3,496 | 0.18 ms | 33 | 40/40, 40 hidden | 160/160 |
| El crimen y el castigo | es | 622 KB | 179,281 | 47 | 1 ms | 98 ms | 568 ms | 631 KB | 5,427 | 0.09 ms | 36 | 40/40, 40 hidden | 160/160 |
| El crimen y el castigo (ghosttoc) | es | 627 KB | 179,281 | 47 | 0 ms | 90 ms | 568 ms | 631 KB | 5,427 | 0.10 ms | 36 | 40/40, 40 hidden | 160/160 |
| \u96f2\u5f62\u7d0b\u7ae0 (notoc) | ja | 361 KB | 182,606 | 7 | 0 ms | 32 ms | 201 ms | 674 KB | 1,764 | 0.07 ms | 37 | 40/40, 40 hidden | 128/128 |
| \u96f2\u5f62\u7d0b\u7ae0 | ja | 372 KB | 182,606 | 7 | 0 ms | 27 ms | 194 ms | 674 KB | 1,764 | 0.05 ms | 37 | 40/40, 40 hidden | 160/160 |
| The Origin of Species by Means of  | en | 995 KB | 211,649 | 26 | 0 ms | 115 ms | 627 ms | 595 KB | 3,776 | 0.13 ms | 42 | 40/40, 40 hidden | 160/160 |
| Moby Dick; Or, The Whale (notoc) | en | 793 KB | 215,845 | 13 | 0 ms | 116 ms | 877 ms | 731 KB | 4,581 | 0.10 ms | 43 | 40/40, 40 hidden | 128/128 |
| Moby Dick; Or, The Whale | en | 795 KB | 215,845 | 13 | 1 ms | 115 ms | 838 ms | 731 KB | 4,581 | 0.16 ms | 43 | 40/40, 40 hidden | 128/128 |
| Los miserables - Tomo 2 (de 2) | es | 1.9 MB | 266,730 | 48 | 0 ms | 153 ms | 588 ms | 992 KB | 11,584 | 0.05 ms | 53 | 40/40, 40 hidden | 160/160 |
| Allgemeine Physiologie | de | 38.9 MB | 296,407 | 39 | 6 ms | 242 ms | 1040 ms | 1.1 MB | 7,358 | 0.12 ms | 59 | 40/40, 40 hidden | 160/160 |
| Don Quixote | en | 44.0 MB | 429,294 | 400 | 16 ms | 241 ms | 1706 ms | 1.2 MB | 7,013 | 0.32 ms | 86 | 39/39, 39 hidden | 160/160 |
| \u897f\u904a\u8a18 | zh | 1.0 MB | 461,047 | 13 | 0 ms | 76 ms | 680 ms | 2.1 MB | 3,348 | 0.09 ms | 92 | 40/40, 40 hidden | 96/96 |
| The Count of Monte Cristo | en | 80.7 MB | 463,572 | 125 | 6 ms | 281 ms | 1901 ms | 1.4 MB | 16,151 | 0.17 ms | 93 | 40/40, 40 hidden | 160/160 |
| \u7d05\u6a13\u5922 | zh | 1.2 MB | 547,009 | 13 | 0 ms | 71 ms | 890 ms | 2.3 MB | 2,993 | 0.16 ms | 109 | 40/40, 40 hidden | 160/160 |
| War and Peace | en | 1.7 MB | 566,335 | 368 | 5 ms | 342 ms | 2075 ms | 1.7 MB | 14,968 | 0.18 ms | 113 | 40/40, 40 hidden | 160/160 |
| War and Peace (notoc) | en | 1.7 MB | 566,335 | 368 | 5 ms | 336 ms | 2082 ms | 1.7 MB | 14,968 | 0.19 ms | 113 | 40/40, 40 hidden | 160/160 |
| Les Mis\xe9rables | en | 9.7 MB | 568,032 | 380 | 5 ms | 331 ms | 1943 ms | 1.8 MB | 17,106 | 0.14 ms | 114 | 40/40, 40 hidden | 160/160 |
| The King James Version of the Bibl | en | 1.6 MB | 824,549 | 70 | 1 ms | 368 ms | 1274 ms | 1.9 MB | 24,883 | 0.06 ms | 165 | 40/40, 40 hidden | 160/160 |
| A Biblia Sagrada, Contendo o Velho | pt | 4.2 MB | 906,795 | 1198 | 12 ms | 1356 ms | 1829 ms | 2.6 MB | 55,295 | 0.06 ms | 181 | 40/40, 40 hidden | 160/160 |
| The Complete Works of William Shak | en | 2.7 MB | 966,482 | 278 | 6 ms | 818 ms | 3415 ms | 3.1 MB | 43,622 | 0.17 ms | 193 | 40/40, 40 hidden | 160/160 |
| Novo dicion\xe1rio da l\xedngua po | pt | 5.0 MB | 1,849,694 | 145 | 1 ms | 3243 ms | 3973 ms | 6.7 MB | 129,286 | 0.06 ms | 370 | 40/40, 40 hidden | 160/160 |

#### Benchmark summary

Times are from a debug (JIT) test run on a Windows laptop, so a phone running the app compiled ahead of time will differ. They are for comparing books with each other.

- Books of 100,000 words or more: 37. Slowest text extraction: 3.2 s; slowest index build: 4.0 s.
- Search query median across books: 0.12 ms; the slowest book's median is 0.32 ms.
- Building the automatic sections: median 68 ms, slowest 1388 ms.
- Search passages per book: median 2,309, most 129,286.
- Longest passage anywhere: 5,826 characters; books with any passage over 600 characters: 71.

#### Search and page-end totals

- Words before the cutoff found: 2835 of 2835.
- Words after the cutoff correctly not found: 2835 of 2835.
- Cutoffs one character short of a passage end that correctly hid it, and exact ones that showed it: 1649 pairs.
- Page-end positions checked against an independent calculation: 8640, mismatches: 0.

### Device results: real Readium on the emulator

38 books opened in the app. 37 had no problems.

| Book | Lang | Page ends | Rejected | Contents | Jump | Search at start (mid) | Search after jump (mid / late) |
| :-- | :-: | --: | --: | :-- | :-- | :-: | :-: |
| The Great Gatsby | en | 24 | 0 | 11 | V → 43% bar 'V' | ok | ok / ok |
| The Yellow Wallpaper | en | 24 | 0 | 2 | THE FULL PROJE → 73% bar 'THE FULL PROJE' | - | - / - |
| Metamorphosis | en | 23 | 0 | 6 | II → 32% bar 'II' | ok | - / ok |
| The Adventures of Sherlock Holmes | en | 23 | 0 | 16 | VI. THE MAN WI → 40% bar 'VI. THE MAN WI' | ok | ok / unclear |
| Frankenstein; or, The modern Prome | en | 19 | 0 | 29 | Chapter 11 → 43% bar 'Chapter 11' | ok | ok / unclear |
| Moby Dick; Or, The Whale | en | 24 | 0 | 143 | CHAPTER 69. Th → 55% bar 'CHAPTER 69. Th' | ok | ok / unclear |
| Dracula | en | 20 | 0 | 30 | CHAPTER XV DR. → 51% bar 'CHAPTER XV DR.' | ok | ok / ok |
| A Christmas Carol in Prose; Being  | en | 22 | 0 | 21 | THE FIRST OF T → 26% bar 'THE FIRST OF T' | ok | - / ok |
| Aeneidos | la | 24 | 0 | 20 | PUBLI VERGILI  → 62% bar 'PUBLI VERGILI ' | ok | ok / ok |
| 1001 \u0437\u0430\u0434\u0430\u044 | ru | 24 | 0 | 6 (made) | Section 4 → 49% bar 'Section 4' | - | - / - |
| Liebe ist ewig : $b Roman | de | 22 | 0 | 28 | XVI. → 56% bar 'XVI.' | ok | ok / ok |
| Le Fant\xf4me de l'Op\xe9ra | fr | 23 | 0 | 34 | XIII LA LYRE D → 42% bar 'XIII LA LYRE D' | ok | ok / unclear |
| Andanzas y visiones espa\xf1olas | es | 16 | 0 | 45 | EN LA ISLA DOR → 59% bar 'EN LA ISLA DOR' | ok | ok / ok |
| Gevoel en verstand | nl | 23 | 0 | 62 | Hoofdstuk XXVI → 43% bar 'Hoofdstuk XXVI' | ok | ok / ok |
| Lintukoto : $b Muutamia p\xe4iv\xe | fi | 24 | 0 | 3 | SISÄLLYS: → 2% bar 'SISÄLLYS:' | ok | - / ok |
| Tales | he | 0 | 0 | 2 | THE FULL PROJE → 96% bar 'THE FULL PROJE' | - | - / - |
| Tribute to Michael Hart | ar | 0 | 0 | 1 | THE FULL PROJE → 59% bar 'THE FULL PROJE' | - | - / - |
| \u7075\u5386\u96c6\u5149 | zh | 24 | 0 | 31 | Section 17 → 50% bar 'Section 17' | - | - / - |
| \u7f85\u751f\u9580 | ja | 23 | 0 | 2 | THE FULL PROJE → 65% bar 'THE FULL PROJE' | - | - / - |
| \u96f2\u5f62\u7d0b\u7ae0 | ja | 24 | 0 | 27 | 第十三章 → 49% bar '第十三章' | - | - / - |
| Frankenstein; or, The mo (onefile) | en | 25 | 0 | 29 | Chapter 11 → 40% bar 'Chapter 11' | ok | ok / unclear |
| The Adventures of Sherlo (onefile) | en | 25 | 0 | 16 | VI. THE MAN WI → 39% bar 'VI. THE MAN WI' | ok | - / unclear |
| Dracula (onefile) | en | 25 | 0 | 30 | CHAPTER XV DR. → 50% bar 'CHAPTER XV DR.' | ok | ok / ok |
| A Christmas Carol in Pro (onefile) | en | 23 | 0 | 21 | THE FIRST OF T → 25% bar 'THE FIRST OF T' | ok | - / ok |
| Frankenstein; or, The mo (ghosttoc) | en | 19 | 0 | 15 | Section 9 → 53% bar 'Section 9' | ok | ok / unclear |
| El crimen y el castigo (ghosttoc) | es | 1 | 0 | 35 | Section 19 → 51% bar 'Section 19' | ok | ok / ok |
| Dracula (onelink) | en | 20 | 0 | 32 | Section 18 → 53% bar 'Section 18' | ok | ok / ok |
| Moby Dick; Or, The Whale (notoc) | en | 24 | 0 | 42 | Section 23 → 51% bar 'Section 23' | ok | ok / unclear |
| Le Fant\xf4me de l'Op\xe (notoc) | fr | 23 | 0 | 20 | Section 12 → 53% bar 'Section 12' | ok | ok / unclear |
| Liebe ist ewig : $b Roma (notoc) | de | 22 | 0 | 17 | Section 10 → 51% bar 'Section 10' | ok | ok / ok |
| \u7075\u5386\u96c6\u5149 (notoc) | zh | 24 | 0 | 31 | Section 17 → 50% bar 'Section 17' | - | - / - |
| \u96f2\u5f62\u7d0b\u7ae0 (notoc) | ja | 24 | 0 | 36 | Section 20 → 51% bar 'Section 20' | - | - / - |
| Tales (notoc) | he | 0 | 0 | 13 | Section 8 → 51% bar 'Section 8' | - | - / - |
| Aeneidos (notoc) | la | 24 | 0 | 12 | Section 8 → 55% bar 'Section 8' | ok | ok / ok |
| War and Peace (notoc) | en | 24 | 0 | 112 | Section 58 → 50% bar 'Section 58' | ok | ok / ok |
| War and Peace | en | 24 | 0 | 30 | CHAPTER XV → 4% bar 'CHAPTER XV' | ok | - / ok |
| Les Mis\xe9rables | en | 20 | 0 | 426 | CHAPTER IV—M.  → 48% bar 'CHAPTER IV—M. ' | ok | ok / unclear |
| The Complete Works of William Shak | en | 22 | 0 | 448 | SCENE V. Anoth → 25% bar 'SCENE V. Anoth' | ok | - / ok |

#### Device problems

- **135** (Les Mis\xe9rables): search for 'steeled' gave no answer in 120s

Page ends reported by the web view across all books: 775; rejected by the tail check: 0.

### Open item

**The late-word search on the device (11 books, including Les Misérables).** Searching a word from 88 to 95 percent in, after a jump to about half way, should show "No matches". In 11 books the screen showed hits for related words instead, because the driver picks words by their spelling and ignores words under seven letters ("steel" is under seven, so it did not stop "steeled" from being chosen). The driver then saw neither the exact word nor "No matches", and for Les Misérables it waited 120 seconds and reported that. The exact word was never shown in any of them, and the computer checks, which compare against the exact indexed term, answered correctly 2,835 of 2,835 times. This is the most likely explanation, but it was not confirmed on the device: the emulator was needed for something else and the last run was stopped.

To close it: pick the late word by the indexed term (as the computer test does) or read the whole result list, and rerun those 11 books. Or by hand: after a jump, search a word that only occurs late in the book and check that nothing from past the page appears.

The right-to-left, Chinese and Japanese books have no search check on the device, as described below; their device checks are page ends, Contents, jumps and the saved position.

## What this does not prove

- **Timings are from a debug build on a laptop** (and the emulator for the device run), not a phone running the release build. They compare books with each other; they are not a promise about a phone.
- **One source.** All 50 books come from Project Gutenberg's EPUB 3 converter, so their markup is more alike than books from many publishers, Calibre, Sigil or Kindle conversions. Fixed-layout books, comics, EPUBs with only images, and DRM-protected books are not covered.
- **Search on the device is checked with ASCII words only.** `adb` can only type ASCII, so the device search checks skip books whose words are not (Chinese, Japanese, Hebrew, Arabic). Those books are checked by the computer tests. Their on-device checks were page ends, Contents and jumps, and the position the reader saves.
- **Right-to-left and vertical books do not get page-level search.** The page script does not measure them, so they use the coarser "finished files only" rule. That is safe, and the page-numbering fix above is what makes it safe.
- **Contents jumps for synthetic sections land near, not exactly on, the cut** (pages are not words). The bar shows the section that was chosen.
- **Spoilers from jumping ahead** (choosing a late chapter makes everything before it searchable) are unchanged; they belong to the reading-position tracker.
- The emulator hung or died twice during the long runs, so some books were run again; the tables show the last run of each.
