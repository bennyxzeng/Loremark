/// A book in the reader's library: an imported EPUB stored inside the app.
class Book {
  const Book({
    required this.id,
    required this.title,
    required this.author,
    required this.epubPath,
    required this.coverPath,
    required this.importedAt,
  });

  factory Book.fromJson(Map<String, dynamic> json) => Book(
    id: json['id'] as String,
    title: json['title'] as String,
    author: json['author'] as String?,
    epubPath: json['epub_path'] as String,
    coverPath: json['cover_path'] as String?,
    importedAt: DateTime.parse(json['imported_at'] as String),
  );

  /// SHA-256 of the EPUB file, the same key story models use as
  /// `epub_sha256`.
  final String id;
  final String title;
  final String? author;

  /// The app's own copy of the EPUB.
  final String epubPath;

  /// The cover image extracted from the EPUB, if it has one.
  final String? coverPath;
  final DateTime importedAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'author': author,
    'epub_path': epubPath,
    'cover_path': coverPath,
    'imported_at': importedAt.toUtc().toIso8601String(),
  };
}
