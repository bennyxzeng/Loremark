/// This file holds the data classes for a reader's personal notes and highlights.
/// Notes are the reader's own thoughts and are never used as facts about the book.
library;

import 'theory.dart';

/// This enum is used to tell apart a plain personal note from a theory.
/// Theories are tracked against the book (see Use Case #2) and carry a [TheoryState].
enum NoteKind { personalNote, theory }

/// This enum lists the highlight colors a reader can pick for a note.
/// The reader can also filter the Notes tab by these colors.
enum HighlightColor { yellow, green, blue, pink }

/// This class marks the spot in the book that a note is attached to.
/// It uses the same JSON keys as `TextPosition` so that, once the reading
/// position branch is merged, a note can switch over to `TextPosition` easily.
/// Ex. NoteAnchor(7, 0.25) is a quarter of the way into the 8th spine section.
class NoteAnchor implements Comparable<NoteAnchor> {
  /// This is the index of the section (EPUB spine item) the note is in.
  final int sectionIndex;

  /// This is how far into that section the note is, from 0.0 to 1.0.
  final double progression;

  const NoteAnchor(this.sectionIndex, this.progression);

  /// This reads an anchor that was saved by [toJson].
  /// Throws a [FormatException] if a value is missing or out of range.
  factory NoteAnchor.fromJson(Map<String, dynamic> json) {
    final sectionIndex = json['sectionIndex'];
    final progression = json['progression'];
    if (sectionIndex is! int ||
        progression is! num ||
        sectionIndex < 0 ||
        progression < 0 ||
        progression > 1) {
      throw FormatException('Invalid NoteAnchor: $json');
    }
    return NoteAnchor(sectionIndex, progression.toDouble());
  }

  /// This turns the anchor into JSON so it can be saved in the notes file.
  Map<String, dynamic> toJson() => {
    'sectionIndex': sectionIndex,
    'progression': progression,
  };

  /// This compares two anchors so notes can be sorted in reading order.
  /// The section is compared first, then how far into the section it is.
  @override
  int compareTo(NoteAnchor other) {
    if (sectionIndex != other.sectionIndex) {
      return sectionIndex.compareTo(other.sectionIndex);
    }
    return progression.compareTo(other.progression);
  }

  bool operator <(NoteAnchor other) => compareTo(other) < 0;

  @override
  bool operator ==(Object other) =>
      other is NoteAnchor &&
      other.sectionIndex == sectionIndex &&
      other.progression == progression;

  @override
  int get hashCode => Object.hash(sectionIndex, progression);

  @override
  String toString() => 'NoteAnchor($sectionIndex, $progression)';
}

/// This class represents a single note or highlight that a reader made on a passage.
/// Each note keeps the passage it was made on, where that passage is in the book,
/// and what the reader wrote about it.
class Note {
  /// This is the unique id of the note.
  final String id;

  /// This is the id of the book that the note belongs to.
  final String bookId;

  /// This is the spot in the book where the selected passage is.
  final NoteAnchor anchor;

  /// This is the chapter name shown in the Notes tab. (Ex. 'Chapter 8')
  /// It is only used for display, the [anchor] is what decides the order.
  final String chapterLabel;

  /// This is the passage of the book the reader selected.
  final String selectedText;

  /// This is the text just before and after the passage in the book.
  /// The reader uses it to find the right spot when the same passage shows up
  /// more than once. (Empty for notes saved before it was kept)
  final String textBefore;
  final String textAfter;

  /// This is what the reader wrote. (Empty when it is only a highlight)
  final String body;

  /// This is the highlight color of the passage.
  final HighlightColor color;

  /// This tells if the note is a personal note or a theory.
  final NoteKind kind;

  /// This is what is tracked about a theory: its sub-theories, the older theory
  /// it builds on, and how far it has been checked. It is present exactly when
  /// [kind] is [NoteKind.theory] and null for a personal note.
  final TheoryState? theory;

  /// These are the timestamps of when the note was created and last edited.
  final DateTime createdAt;
  final DateTime updatedAt;

  const Note({
    required this.id,
    required this.bookId,
    required this.anchor,
    required this.chapterLabel,
    required this.selectedText,
    this.textBefore = '',
    this.textAfter = '',
    required this.body,
    required this.color,
    this.kind = NoteKind.personalNote,
    this.theory,
    required this.createdAt,
    required this.updatedAt,
  }) : assert(
         (kind == NoteKind.theory) == (theory != null),
         'A note has theory data exactly when it is a theory.',
       );

  /// This is true when the reader only highlighted the passage without writing anything.
  bool get isHighlightOnly => body.trim().isEmpty;

  /// This reads a note that was saved by [toJson].
  /// Parameters:
  /// - json: The map for one note from the notes file.
  /// Returns: The note, or throws a [FormatException] if any field is missing or invalid.
  factory Note.fromJson(Map<String, dynamic> json) {
    try {
      final kind = NoteKind.values.byName(json['kind'] as String);
      final theory = json['theory'];
      // Notes saved before theories were tracked have no theory data, so a
      // theory without any starts out unsplit and unchecked.
      if (kind != NoteKind.theory && theory != null) {
        throw FormatException('Invalid Note: $json');
      }
      return Note(
        id: json['id'] as String,
        bookId: json['bookId'] as String,
        anchor: NoteAnchor.fromJson(json['anchor'] as Map<String, dynamic>),
        chapterLabel: json['chapterLabel'] as String,
        selectedText: json['selectedText'] as String,
        // Older notes files do not have these, so a missing one is empty.
        textBefore: json['textBefore'] as String? ?? '',
        textAfter: json['textAfter'] as String? ?? '',
        body: json['body'] as String,
        color: HighlightColor.values.byName(json['color'] as String),
        kind: kind,
        theory: kind != NoteKind.theory
            ? null
            : theory == null
            ? const TheoryState()
            : TheoryState.fromJson(theory as Map<String, dynamic>),
        createdAt: DateTime.parse(json['createdAt'] as String),
        updatedAt: DateTime.parse(json['updatedAt'] as String),
      );
    } on FormatException {
      rethrow;
    } catch (_) {
      // A missing field shows up as a TypeError and an unknown color as an
      // ArgumentError, so both are turned into one FormatException for the caller.
      throw FormatException('Invalid Note: $json');
    }
  }

  /// This turns the note into JSON so it can be saved in the notes file.
  Map<String, dynamic> toJson() => {
    'id': id,
    'bookId': bookId,
    'anchor': anchor.toJson(),
    'chapterLabel': chapterLabel,
    'selectedText': selectedText,
    'textBefore': textBefore,
    'textAfter': textAfter,
    'body': body,
    'color': color.name,
    'kind': kind.name,
    if (theory != null) 'theory': theory!.toJson(),
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };

  /// This makes a copy of the note with only the given fields changed.
  /// Used when the reader edits a note. (Ex. changing the text or the color)
  /// A note that ends up as a personal note drops its theory data. One that
  /// ends up as a theory keeps its own, takes [theory] if given, and otherwise
  /// starts with an empty [TheoryState].
  Note copyWith({
    String? body,
    HighlightColor? color,
    NoteKind? kind,
    TheoryState? theory,
    DateTime? updatedAt,
  }) {
    final newKind = kind ?? this.kind;
    return Note(
      id: id,
      bookId: bookId,
      anchor: anchor,
      chapterLabel: chapterLabel,
      selectedText: selectedText,
      textBefore: textBefore,
      textAfter: textAfter,
      body: body ?? this.body,
      color: color ?? this.color,
      kind: newKind,
      theory: newKind == NoteKind.theory
          ? theory ?? this.theory ?? const TheoryState()
          : null,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Note &&
      other.id == id &&
      other.bookId == bookId &&
      other.anchor == anchor &&
      other.chapterLabel == chapterLabel &&
      other.selectedText == selectedText &&
      other.textBefore == textBefore &&
      other.textAfter == textAfter &&
      other.body == body &&
      other.color == color &&
      other.kind == kind &&
      other.theory == theory &&
      other.createdAt.isAtSameMomentAs(createdAt) &&
      other.updatedAt.isAtSameMomentAs(updatedAt);

  @override
  int get hashCode => Object.hash(
    id,
    bookId,
    anchor,
    chapterLabel,
    selectedText,
    textBefore,
    textAfter,
    body,
    color,
    kind,
    theory,
    createdAt.millisecondsSinceEpoch,
    updatedAt.millisecondsSinceEpoch,
  );
}
