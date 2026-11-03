/// This file holds the data classes for a reader's personal notes and highlights.
/// Notes are the reader's own thoughts and are never used as facts about the book.
library;

/// This enum is used to tell apart a plain personal note from a theory.
/// Theories are tracked and checked against the book later (see Use Case #2),
/// but for now every note is created as a personal note.
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

  /// This is what the reader wrote. (Empty when it is only a highlight)
  final String body;

  /// This is the highlight color of the passage.
  final HighlightColor color;

  /// This tells if the note is a personal note or a theory.
  final NoteKind kind;

  /// These are the timestamps of when the note was created and last edited.
  final DateTime createdAt;
  final DateTime updatedAt;

  const Note({
    required this.id,
    required this.bookId,
    required this.anchor,
    required this.chapterLabel,
    required this.selectedText,
    required this.body,
    required this.color,
    this.kind = NoteKind.personalNote,
    required this.createdAt,
    required this.updatedAt,
  });

  /// This is true when the reader only highlighted the passage without writing anything.
  bool get isHighlightOnly => body.trim().isEmpty;

  /// This reads a note that was saved by [toJson].
  /// Parameters:
  /// - json: The map for one note from the notes file.
  /// Returns: The note, or throws a [FormatException] if any field is missing or invalid.
  factory Note.fromJson(Map<String, dynamic> json) {
    try {
      return Note(
        id: json['id'] as String,
        bookId: json['bookId'] as String,
        anchor: NoteAnchor.fromJson(json['anchor'] as Map<String, dynamic>),
        chapterLabel: json['chapterLabel'] as String,
        selectedText: json['selectedText'] as String,
        body: json['body'] as String,
        color: HighlightColor.values.byName(json['color'] as String),
        kind: NoteKind.values.byName(json['kind'] as String),
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
    'body': body,
    'color': color.name,
    'kind': kind.name,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };

  /// This makes a copy of the note with only the given fields changed.
  /// Used when the reader edits a note. (Ex. changing the text or the color)
  Note copyWith({
    String? body,
    HighlightColor? color,
    NoteKind? kind,
    DateTime? updatedAt,
  }) => Note(
    id: id,
    bookId: bookId,
    anchor: anchor,
    chapterLabel: chapterLabel,
    selectedText: selectedText,
    body: body ?? this.body,
    color: color ?? this.color,
    kind: kind ?? this.kind,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  @override
  bool operator ==(Object other) =>
      other is Note &&
      other.id == id &&
      other.bookId == bookId &&
      other.anchor == anchor &&
      other.chapterLabel == chapterLabel &&
      other.selectedText == selectedText &&
      other.body == body &&
      other.color == color &&
      other.kind == kind &&
      other.createdAt.isAtSameMomentAs(createdAt) &&
      other.updatedAt.isAtSameMomentAs(updatedAt);

  @override
  int get hashCode => Object.hash(
    id,
    bookId,
    anchor,
    chapterLabel,
    selectedText,
    body,
    color,
    kind,
    createdAt.millisecondsSinceEpoch,
    updatedAt.millisecondsSinceEpoch,
  );
}
