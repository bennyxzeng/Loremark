import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:loremark/notes/annotation_service.dart';
import 'package:loremark/notes/note.dart';
import 'package:loremark/notes/theory.dart';
import 'package:loremark/reader/reader_position.dart';
import 'package:loremark/settings/ai_settings.dart';
import 'package:loremark/story_update/story_api_client.dart';
import 'package:loremark/theories/theory_checker.dart';

import '../notes/in_memory_note_repository.dart';

/// One completed Responses API reply holding [output] as the model's JSON.
StoryHttpResponse reply(Object output) => StoryHttpResponse(
  200,
  jsonEncode({
    'status': 'completed',
    'output': [
      {
        'type': 'message',
        'content': [
          {'type': 'output_text', 'text': jsonEncode(output)},
        ],
      },
    ],
  }),
);

Map<String, Object> split(List<String> texts) => {
  'sub_theories': [
    for (final text in texts) {'text': text},
  ],
};

Map<String, Object> verdicts(Map<String, (String, String)> byId) => {
  'results': [
    for (final entry in byId.entries)
      {
        'id': entry.key,
        'verdict': entry.value.$1,
        'evidence_quote': entry.value.$2,
      },
  ],
};

void main() {
  // Section 4 and 5 are "in progress" and "later": their marker phrases must
  // never leave the device.
  const sections = [
    'Chapter one.\nMara hid the ledger under the floor.\nNothing else happened.',
    'Chapter two.\nElian\nburned   the ledger.\nThe harbor was quiet. MARK-1',
    'Chapter three.\nThe lamp stayed dark. MARK-2',
    'Chapter four.\nA storm came in. MARK-3',
    'Chapter five, in progress. IN-PROGRESS-MARKER',
    'Chapter six, later. LATER-CHAPTER-MARKER',
  ];

  late AnnotationService notes;
  late List<Map<String, dynamic>> bodies;
  late Future<StoryHttpResponse> Function(Map<String, dynamic> body) handler;
  late AiCredentials? key;
  late bool online;
  late int sectionLoads;
  late int credentialReads;

  Future<StoryHttpResponse> fakePost(
    Uri url,
    Map<String, String> headers,
    String body,
  ) {
    expect(url.scheme, 'https');
    expect(
      {'api.openai.com', 'api.deepseek.com'},
      contains(url.host),
      reason: 'requests go only to the reader\'s AI provider',
    );
    final decoded = jsonDecode(body) as Map<String, dynamic>;
    bodies.add(decoded);
    return handler(decoded);
  }

  TheoryChecker newChecker() => TheoryChecker(
    annotations: notes,
    loadSectionTexts: () async {
      sectionLoads++;
      return sections;
    },
    credentials: () {
      credentialReads++;
      return key;
    },
    isOnline: () => online,
    post: fakePost,
    clock: () => DateTime.utc(2026, 11, 8, 12),
  );

  Future<Note> addTheory(
    String body, {
    int section = 0,
    String? dependsOnId,
    String passage = 'Mara hid the ledger under the floor.',
  }) => notes.addNote(
    anchor: NoteAnchor(section, 0.5),
    chapterLabel: 'Chapter ${section + 1}',
    selectedText: passage,
    body: body,
    kind: NoteKind.theory,
    dependsOnId: dependsOnId,
  );

  /// Gives a theory its sub-theories directly, as a finished split would.
  Future<void> presplit(Note theory, List<String> texts) => notes.updateTheory(
    theory.id,
    (state) => state.copyWith(
      subTheories: [
        for (var i = 0; i < texts.length; i++)
          SubTheory(id: 's${i + 1}', text: texts[i]),
      ],
    ),
  );

  /// The reader has finished sections 0..[finished]-1 and is partway through
  /// the next.
  ReaderPosition inProgressAfter(int finished) => ReaderPosition(finished, 0.5);

  List<String> userMessages() => [
    for (final body in bodies)
      ((body['input'] as List)[1] as Map)['content'] as String,
  ];

  bool isSplit(Map<String, dynamic> body) =>
      ((body['input'] as List)[1] as Map)['content'].toString().startsWith(
        'THEORY',
      );

  setUp(() async {
    notes = AnnotationService(
      bookId: 'abc',
      repository: InMemoryNoteRepository(),
      clock: () => DateTime.utc(2026, 11, 2),
    );
    await notes.load();
    bodies = [];
    sectionLoads = 0;
    credentialReads = 0;
    key = const AiCredentials(
      provider: AiProvider.deepseek,
      apiKey: 'sk-very-secret',
    );
    online = true;
    handler = (body) async =>
        reply(isSplit(body) ? split(['Mara is the thief']) : verdicts({}));
  });

  group('splitting', () {
    test(
      'a theory is split into sub-theories from its text and passage',
      () async {
        final theory = await addTheory('Mara is the thief and works for Elian');
        handler = (body) async =>
            reply(split(['Mara is the thief', 'Mara works for Elian']));

        await newChecker().run();

        final subs = notes.theories.single.theory!.subTheories;
        expect(
          [for (final sub in subs) sub.text],
          ['Mara is the thief', 'Mara works for Elian'],
        );
        expect(subs.every((sub) => sub.isOpen), isTrue);
        expect(bodies, hasLength(1));
        final text = userMessages().single;
        expect(text, contains('Mara is the thief and works for Elian'));
        expect(text, contains('Mara hid the ledger under the floor.'));
        expect(theory.id, notes.theories.single.id);
      },
    );

    test('a model that returns more than five keeps the first five', () async {
      await addTheory('Many things');
      handler = (body) async =>
          reply(split([for (var i = 1; i <= 8; i++) 'Part $i']));

      await newChecker().run();

      expect(notes.theories.single.theory!.subTheories, hasLength(5));
    });

    test(
      'an answer with no usable sub-theory leaves the theory unsplit',
      () async {
        await addTheory('Mara is the thief');
        handler = (body) async => reply(split(['  ']));
        final checker = newChecker();

        await checker.run();

        expect(notes.theories.single.theory!.subTheories, isEmpty);
        expect(checker.lastError, 'invalid_output');
      },
    );

    test(
      'a theory edited while its split was out is not overwritten',
      () async {
        final theory = await addTheory('Mara is the thief');
        final gate = Completer<void>();
        handler = (body) async {
          await gate.future;
          return reply(split(['Mara is the thief']));
        };

        final run = newChecker().run();
        await Future<void>.delayed(Duration.zero);
        await notes.editNote(theory.id, body: 'Elian is the thief');
        gate.complete();
        await run;

        expect(notes.theories.single.body, 'Elian is the thief');
        expect(notes.theories.single.theory!.subTheories, isEmpty);
      },
    );
  });

  group('verdicts and evidence', () {
    test('a verdict with a real quote is applied with its evidence', () async {
      final theory = await addTheory('Elian burns the ledger');
      await presplit(theory, ['Elian burns the ledger']);
      handler = (body) async => reply(
        verdicts({
          '${theory.id}/s1': ('confirmed', 'Elian burned the ledger.'),
        }),
      );

      // The quote's line breaks and spacing differ from the section's.
      await newChecker().run(current: inProgressAfter(2));

      final state = notes.theories.single.theory!;
      final sub = state.subTheories.single;
      expect(sub.verdict, SubTheoryVerdict.confirmed);
      expect(sub.evidence!.sectionIndex, 1);
      expect(sub.evidence!.quote, 'Elian burned the ledger.');
      expect(sub.resolvedAt, DateTime.utc(2026, 11, 8, 12));
      expect(state.checkedThroughSection, 1);
      expect(notes.statusOf(theory.id), TheoryStatus.confirmed);
    });

    test(
      'an invented quote is rejected and the sub-theory stays open',
      () async {
        final theory = await addTheory('Elian burns the ledger');
        await presplit(theory, ['Elian burns the ledger']);
        handler = (body) async => reply(
          verdicts({
            '${theory.id}/s1': ('confirmed', 'Elian set fire to the ledger.'),
          }),
        );

        await newChecker().run(current: inProgressAfter(2));

        final state = notes.theories.single.theory!;
        expect(state.subTheories.single.isOpen, isTrue);
        expect(state.subTheories.single.evidence, isNull);
        // The sections were still read, so they are not asked about again.
        expect(state.checkedThroughSection, 1);
      },
    );

    test('a verdict without a quote is not accepted', () async {
      final theory = await addTheory('Elian burns the ledger');
      await presplit(theory, ['Elian burns the ledger']);
      handler = (body) async =>
          reply(verdicts({'${theory.id}/s1': ('refuted', '   ')}));

      await newChecker().run(current: inProgressAfter(2));

      expect(notes.theories.single.theory!.subTheories.single.isOpen, isTrue);
    });

    test('a resolved sub-theory is not sent again and never changes', () async {
      final theory = await addTheory('Mara hid it and Elian burned it');
      await presplit(theory, [
        'Mara hid the ledger',
        'Elian burned the ledger',
      ]);
      handler = (body) async {
        final text = ((body['input'] as List)[1] as Map)['content'] as String;
        if (text.contains('Chapter one.')) {
          return reply(
            verdicts({
              '${theory.id}/s1': ('confirmed', 'Mara hid the ledger'),
              '${theory.id}/s2': ('undecided', ''),
            }),
          );
        }
        // The model contradicts itself about s1 on the next section.
        return reply(
          verdicts({
            '${theory.id}/s1': ('refuted', 'The lamp stayed dark.'),
            '${theory.id}/s2': ('undecided', ''),
          }),
        );
      };

      await newChecker().run(current: inProgressAfter(3));

      final subs = notes.theories.single.theory!.subTheories;
      expect(subs[0].verdict, SubTheoryVerdict.confirmed);
      expect(subs[0].evidence!.sectionIndex, 0);
      expect(subs[1].isOpen, isTrue);
      // Later requests only carry the sub-theory that is still open.
      final later = userMessages().skip(1);
      expect(later, isNotEmpty);
      for (final text in later) {
        expect(text, isNot(contains('Mara hid the ledger\n')));
        expect(text, contains('Elian burned the ledger'));
      }
      expect(notes.statusOf(theory.id), TheoryStatus.partiallyCorrect);
    });

    test(
      'a theory is only checked from the section it was written in',
      () async {
        final theory = await addTheory('Storm coming', section: 3);
        await presplit(theory, ['A storm comes']);

        await newChecker().run(current: inProgressAfter(4));

        expect(bodies, hasLength(1));
        expect(userMessages().single, contains('Chapter four.'));
        expect(userMessages().single, isNot(contains('Chapter one.')));
      },
    );
  });

  group('statuses end to end', () {
    test('every part refuted gives Different outcome and invalidates a theory built on it', () async {
      final older = await addTheory('Mara hid the ledger in the cellar');
      final newer = await addTheory(
        'The cellar holds more',
        section: 1,
        dependsOnId: older.id,
      );
      await presplit(older, ['The ledger is in the cellar']);
      await presplit(newer, ['The cellar holds more']);
      handler = (body) async => reply(
        verdicts({
          '${older.id}/s1': ('refuted', 'Mara hid the ledger under the floor.'),
        }),
      );
      final checker = newChecker();
      final changes = <TheoryStatusChange>[];
      checker.changes.listen(changes.add);

      await checker.run(current: inProgressAfter(2));
      await Future<void>.delayed(Duration.zero);

      expect(notes.statusOf(older.id), TheoryStatus.differentOutcome);
      expect(notes.statusOf(newer.id), TheoryStatus.invalidated);
      expect(
        {for (final c in changes) c.noteId: c.to},
        {
          older.id: TheoryStatus.differentOutcome,
          newer.id: TheoryStatus.invalidated,
        },
      );
      expect(
        changes.firstWhere((c) => c.noteId == older.id).bannerText,
        'Theory had a different outcome: "Mara hid the ledger in the cellar"',
      );
    });

    test('an invalidated theory is not checked any more', () async {
      final older = await addTheory('Mara hid it in the cellar');
      final newer = await addTheory(
        'More in the cellar',
        section: 0,
        dependsOnId: older.id,
      );
      await presplit(older, ['In the cellar']);
      await presplit(newer, ['More in the cellar']);
      handler = (body) async =>
          reply(verdicts({'${older.id}/s1': ('refuted', 'under the floor')}));

      await newChecker().run(current: inProgressAfter(3));

      // After section 0 refuted the older theory, the newer one is lost, so
      // later sections only ask about nothing: no more requests are sent.
      expect(bodies, hasLength(1));
    });

    test(
      'a mix is Partially correct and a banner change is reported once',
      () async {
        final theory = await addTheory('Mara hid it and Elian burned it');
        await presplit(theory, ['Mara hid it', 'Elian burned it']);
        handler = (body) async => reply(
          verdicts({'${theory.id}/s1': ('confirmed', 'Mara hid the ledger')}),
        );
        final checker = newChecker();
        final changes = <TheoryStatusChange>[];
        checker.changes.listen(changes.add);

        await checker.run(current: inProgressAfter(1));
        await Future<void>.delayed(Duration.zero);

        expect(changes, hasLength(1));
        expect(changes.single.from, TheoryStatus.unconfirmed);
        expect(changes.single.to, TheoryStatus.partiallyCorrect);
      },
    );
  });

  group('what is sent', () {
    setUp(() async {
      final theory = await addTheory('Storm theory', section: 0);
      await presplit(theory, ['A storm comes']);
    });

    test('never the section in progress or any later one', () async {
      // Reading section 4: sections 0..3 are finished.
      await newChecker().run(current: const ReaderPosition(4, 0.9));

      expect(bodies, hasLength(4));
      for (final text in userMessages()) {
        expect(text, isNot(contains('IN-PROGRESS-MARKER')));
        expect(text, isNot(contains('LATER-CHAPTER-MARKER')));
      }
      expect(jsonEncode(bodies), isNot(contains('IN-PROGRESS-MARKER')));
      expect(jsonEncode(bodies), isNot(contains('LATER-CHAPTER-MARKER')));
    });

    test(
      'the furthest position counts, but still only finished sections',
      () async {
        await newChecker().run(
          current: const ReaderPosition(0, 0.2),
          furthest: const ReaderPosition(3, 0.4),
        );

        // Furthest is partway through section 3, so 0..2 are finished.
        expect(bodies, hasLength(3));
        expect(jsonEncode(bodies), isNot(contains('MARK-3')));
      },
    );

    test('a section that was just finished is sent', () async {
      await newChecker().run(current: const ReaderPosition(1, 1));

      expect(bodies, hasLength(2));
      expect(jsonEncode(bodies), contains('MARK-1'));
      expect(jsonEncode(bodies), isNot(contains('MARK-2')));
    });

    test('at the start of the book nothing is sent', () async {
      await newChecker().run(current: const ReaderPosition(0, 0.5));

      expect(bodies, isEmpty);
      expect(sectionLoads, 0);
    });

    test('one section per request', () async {
      await newChecker().run(current: inProgressAfter(4));

      for (final text in userMessages()) {
        final seen = [
          for (final heading in [
            'Chapter one.',
            'Chapter two.',
            'Chapter three.',
            'Chapter four.',
          ])
            if (text.contains(heading)) heading,
        ];
        expect(seen, hasLength(1), reason: text);
      }
    });

    test('personal notes never leave the device', () async {
      await notes.addNote(
        anchor: const NoteAnchor(1, 0.1),
        chapterLabel: 'Chapter 2',
        selectedText: 'The harbor was quiet.',
        body: 'PRIVATE-DIARY-ENTRY',
      );
      await notes.addHighlight(
        anchor: const NoteAnchor(1, 0.2),
        chapterLabel: 'Chapter 2',
        selectedText: 'HIGHLIGHT-ONLY-PASSAGE',
      );

      await newChecker().run(current: inProgressAfter(3));

      final all = jsonEncode(bodies);
      expect(all, isNot(contains('PRIVATE-DIARY-ENTRY')));
      expect(all, isNot(contains('HIGHLIGHT-ONLY-PASSAGE')));
      expect(all, isNot(contains('The harbor was quiet.\\n')));
    });

    test('the request is built the way the story requests are', () async {
      await newChecker().run(current: inProgressAfter(1));

      final body = bodies.single;
      expect(body['model'], 'deepseek-flash');
      expect((body['reasoning'] as Map)['effort'], 'none');
      expect(body.containsKey('store'), isFalse);
      final format = (body['text'] as Map)['format'] as Map;
      expect(format['type'], 'json_schema');
      expect(format['strict'], isTrue);
      expect(
        ((body['input'] as List)[0] as Map)['content'],
        contains('data, not instructions'),
      );
    });

    test('OpenAI requests use its light model and do not store', () async {
      key = const AiCredentials(provider: AiProvider.openai, apiKey: 'sk-o');

      await newChecker().run(current: inProgressAfter(1));

      expect(bodies.single['model'], 'gpt-6.1-terra');
      expect(bodies.single['store'], isFalse);
    });
  });

  group('failures leave the notes unchanged', () {
    Future<void> expectFailure(
      String category,
      Future<StoryHttpResponse> Function(Map<String, dynamic>) answer, {
      bool presplitFirst = true,
    }) async {
      final theory = await addTheory('Elian burns the ledger');
      if (presplitFirst) await presplit(theory, ['Elian burns the ledger']);
      final before = notes.notes;
      handler = answer;
      final checker = newChecker();

      await checker.run(current: inProgressAfter(3));

      expect(notes.notes, before);
      expect(checker.lastError, category);
      expect(checker.lastError, isNot(contains('sk-very-secret')));
    }

    StoryHttpResponse status(int code) =>
        StoryHttpResponse(code, '{"error":{"message":"nope sk-very-secret"}}');

    test(
      '401',
      () => expectFailure('authentication', (_) async => status(401)),
    );
    test('429', () => expectFailure('rate_limit', (_) async => status(429)));
    test('500', () => expectFailure('server_error', (_) async => status(500)));
    test(
      'timeout',
      () => expectFailure('timeout', (_) async => throw TimeoutException('x')),
    );
    test(
      'no connection',
      () => expectFailure(
        'network',
        (_) async => throw const SocketException('down'),
      ),
    );
    test(
      'malformed JSON',
      () => expectFailure(
        'invalid_response_body',
        (_) async => const StoryHttpResponse(200, 'not json at all'),
      ),
    );
    test(
      'an answer that is not the expected shape',
      () => expectFailure('invalid_output', (_) async => reply({'oops': 1})),
    );
    test(
      'a refusal',
      () => expectFailure(
        'refusal',
        (_) async => StoryHttpResponse(
          200,
          jsonEncode({
            'status': 'completed',
            'output': [
              {
                'type': 'message',
                'content': [
                  {'type': 'refusal', 'refusal': 'I cannot help with that.'},
                ],
              },
            ],
          }),
        ),
      ),
    );
    test(
      'a failure while splitting',
      () => expectFailure(
        'rate_limit',
        (_) async => status(429),
        presplitFirst: false,
      ),
    );

    test('work already applied is kept when a later section fails', () async {
      final theory = await addTheory('Mara hid it');
      await presplit(theory, ['Mara hid it']);
      var calls = 0;
      handler = (body) async {
        calls++;
        if (calls == 1) {
          return reply(verdicts({'${theory.id}/s1': ('undecided', '')}));
        }
        return status(500);
      };
      final checker = newChecker();

      await checker.run(current: inProgressAfter(3));

      expect(checker.lastError, 'server_error');
      expect(notes.theories.single.theory!.checkedThroughSection, 0);
      // The next trigger picks up at section 1 without repeating section 0.
      handler = (body) async =>
          reply(verdicts({'${theory.id}/s1': ('undecided', '')}));
      bodies.clear();
      await checker.run(current: inProgressAfter(3));
      expect(checker.lastError, isNull);
      expect(bodies, hasLength(2));
      expect(jsonEncode(bodies), isNot(contains('Chapter one.')));
    });

    test('a failed run never throws into the caller', () async {
      await addTheory('Mara');
      handler = (_) async => throw StateError('boom');

      await expectLater(
        newChecker().run(current: inProgressAfter(2)),
        completes,
      );
    });
  });

  group('when it does nothing', () {
    setUp(() async {
      final theory = await addTheory('Storm theory');
      await presplit(theory, ['A storm comes']);
    });

    test('without an API key', () async {
      key = null;
      await newChecker().run(current: inProgressAfter(3));
      expect(bodies, isEmpty);
      expect(sectionLoads, 0);
    });

    test('offline', () async {
      online = false;
      await newChecker().run(current: inProgressAfter(3));
      expect(bodies, isEmpty);
    });

    test('with no unresolved theory', () async {
      final theory = notes.theories.single;
      await notes.updateTheory(
        theory.id,
        (state) => state.copyWith(
          subTheories: [
            state.subTheories.single.copyWith(
              verdict: SubTheoryVerdict.confirmed,
              evidence: const TheoryEvidence(
                sectionIndex: 0,
                chapterLabel: 'Section 1',
                quote: 'q',
              ),
              resolvedAt: DateTime.utc(2026),
            ),
          ],
        ),
      );
      await newChecker().run(current: inProgressAfter(3));
      expect(bodies, isEmpty);
      expect(sectionLoads, 0);
    });

    test('with only personal notes', () async {
      final solo = AnnotationService(
        bookId: 'abc',
        repository: InMemoryNoteRepository(),
      );
      await solo.load();
      await solo.addNote(
        anchor: const NoteAnchor(0, 0.1),
        chapterLabel: 'Chapter 1',
        selectedText: 'x',
        body: 'just a thought',
      );
      notes = solo;
      await newChecker().run(current: inProgressAfter(3));
      expect(bodies, isEmpty);
    });
  });

  group('triggers', () {
    test('triggers during a run are merged into one follow-up run', () async {
      final theory = await addTheory('Storm theory');
      await presplit(theory, ['A storm comes']);
      final gate = Completer<void>();
      handler = (body) async {
        await gate.future;
        return reply(verdicts({'${theory.id}/s1': ('undecided', '')}));
      };
      final checker = newChecker();

      final first = checker.run(current: inProgressAfter(1));
      await Future<void>.delayed(Duration.zero);
      final second = checker.run(current: inProgressAfter(2));
      final third = checker.run(current: inProgressAfter(3));
      gate.complete();
      await Future.wait([first, second, third]);

      // One run for the first trigger and one for the other two together.
      expect(credentialReads, 2);
      // The follow-up used the latest positions: sections 0, 1 and 2 once each.
      expect(bodies, hasLength(3));
    });

    test('a run after the previous one finished starts a new run', () async {
      final theory = await addTheory('Storm theory');
      await presplit(theory, ['A storm comes']);
      handler = (body) async =>
          reply(verdicts({'${theory.id}/s1': ('undecided', '')}));
      final checker = newChecker();

      await checker.run(current: inProgressAfter(1));
      await checker.run(current: inProgressAfter(2));

      expect(credentialReads, 2);
      // Section 0, then only section 1: nothing is checked twice.
      expect(bodies, hasLength(2));
    });
  });

  test('finishedSectionCount follows the finished-section cutoff', () {
    expect(finishedSectionCount(), 0);
    expect(finishedSectionCount(current: const ReaderPosition(0, 0.9)), 0);
    expect(finishedSectionCount(current: const ReaderPosition(0, 1)), 1);
    expect(finishedSectionCount(current: const ReaderPosition(4, 0.1)), 4);
    expect(
      finishedSectionCount(
        current: const ReaderPosition(1, 0.1),
        furthest: const ReaderPosition(5, 1),
      ),
      6,
    );
  });
}
