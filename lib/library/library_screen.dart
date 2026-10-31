import 'dart:io';

import 'package:flutter/material.dart';

import '../home/book_screen.dart';
import '../theme/loremark_theme.dart';
import 'book.dart';
import 'book_repository.dart';

/// Asks the reader for an EPUB and returns its path, or null if they cancel.
typedef EpubPicker = Future<String?> Function();

/// The home screen: the reader's imported books and the way to add more.
///
/// On launch it resumes the last opened book; the book's header leads back
/// here.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({
    super.key,
    required this.repository,
    required this.pickEpub,
  });

  final Future<BookRepository> repository;
  final EpubPicker pickEpub;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  BookRepository? _repository;
  Object? _loadError;
  bool _importing = false;

  @override
  void initState() {
    super.initState();
    widget.repository.then(
      (repository) {
        if (!mounted) return;
        setState(() => _repository = repository);
        if (repository.lastOpened case final book?) _open(book);
      },
      onError: (Object error) {
        if (mounted) setState(() => _loadError = error);
      },
    );
  }

  Future<void> _open(Book book) async {
    _repository!.markOpened(book);
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => BookScreen(book: book)));
    if (mounted) setState(() {});
  }

  void _say(String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));

  Future<void> _import() async {
    final repository = _repository!;
    final path = await widget.pickEpub();
    if (path == null || !mounted) return;

    final wasEmpty = repository.books.isEmpty;
    setState(() => _importing = true);
    try {
      final (:book, :isNew) = await repository.importEpub(path);
      if (!mounted) return;
      if (!isNew) {
        _say('“${book.title}” is already in your library.');
      } else if (wasEmpty) {
        // A first book goes straight to the reader.
        _open(book);
      }
    } on FormatException {
      _say('That file isn’t an EPUB Loremark can read.');
    } on FileSystemException {
      _say('Couldn’t import that file.');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _remove(Book book) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove “${book.title}”?'),
        content: const Text(
          'The book is deleted from this device. '
          'The original file you imported is not affected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _repository!.remove(book);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final repository = _repository;
    final books = repository?.books ?? const <Book>[];

    return Scaffold(
      floatingActionButton: books.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: _importing ? null : _import,
              backgroundColor: LoremarkColors.olive,
              foregroundColor: LoremarkColors.onOlive,
              icon: const Icon(Icons.add),
              label: Text(_importing ? 'Importing…' : 'Import EPUB'),
            ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 96),
          children: [
            const _Wordmark(),
            const SizedBox(height: 36),
            Text('YOUR LIBRARY', style: kicker()),
            const SizedBox(height: 9),
            Text('Books', style: serif(29, height: 1.18)),
            const SizedBox(height: 20),
            if (_loadError != null)
              Text(
                'Couldn’t open your library.\n$_loadError',
                style: const TextStyle(color: LoremarkColors.muted),
              )
            else if (repository == null)
              const Text(
                'Opening your library…',
                style: TextStyle(color: LoremarkColors.muted),
              )
            else if (books.isEmpty)
              _EmptyLibrary(importing: _importing, onImport: _import)
            else
              for (final book in books)
                _BookTile(
                  book: book,
                  isLastOpened: book.id == repository.lastOpened?.id,
                  onOpen: () => _open(book),
                  onRemove: () => _remove(book),
                ),
          ],
        ),
      ),
    );
  }
}

class _Wordmark extends StatelessWidget {
  const _Wordmark();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 24,
          height: 30,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: LoremarkColors.olive,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(4),
              topRight: Radius.circular(4),
              bottomLeft: Radius.circular(4),
              bottomRight: Radius.circular(9),
            ),
          ),
          child: Text('L', style: serif(20, color: LoremarkColors.paper)),
        ),
        const SizedBox(width: 9),
        const Text(
          'loremark',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w600,
            letterSpacing: -1,
          ),
        ),
        const Text(
          '.',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w600,
            color: LoremarkColors.gold,
          ),
        ),
      ],
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary({required this.importing, required this.onImport});

  final bool importing;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 28),
        const Icon(
          Icons.auto_stories_outlined,
          size: 44,
          color: LoremarkColors.line,
        ),
        const SizedBox(height: 14),
        const Text(
          'Import a DRM-free EPUB to start reading.\n'
          'Books stay on this device.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            height: 1.6,
            color: LoremarkColors.muted,
          ),
        ),
        const SizedBox(height: 22),
        FilledButton.icon(
          onPressed: importing ? null : onImport,
          icon: const Icon(Icons.add),
          label: Text(importing ? 'Importing…' : 'Import EPUB'),
        ),
      ],
    );
  }
}

class _BookTile extends StatelessWidget {
  const _BookTile({
    required this.book,
    required this.isLastOpened,
    required this.onOpen,
    required this.onRemove,
  });

  final Book book;
  final bool isLastOpened;
  final VoidCallback onOpen;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 4, 14),
          child: Row(
            children: [
              BookCover(book: book, width: 48),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (isLastOpened) ...[
                      Text('LAST OPENED', style: kicker(size: 9)),
                      const SizedBox(height: 5),
                    ],
                    Text(book.title, style: serif(17, height: 1.3)),
                    if (book.author case final author?) ...[
                      const SizedBox(height: 4),
                      Text(
                        author,
                        style: const TextStyle(
                          fontSize: 13,
                          color: LoremarkColors.muted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              PopupMenuButton<void>(
                tooltip: 'Book options',
                icon: const Icon(Icons.more_vert, color: LoremarkColors.muted),
                itemBuilder: (context) => [
                  PopupMenuItem(
                    onTap: onRemove,
                    child: const Text('Remove from library'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A book's cover, or its initial on a tinted card when it has none.
class BookCover extends StatelessWidget {
  const BookCover({super.key, required this.book, required this.width});

  final Book book;
  final double width;

  @override
  Widget build(BuildContext context) {
    final placeholder = ColoredBox(
      color: LoremarkColors.panel,
      child: Center(
        child: Text(
          book.title.characters.first.toUpperCase(),
          style: serif(width * 0.45, color: LoremarkColors.gold),
        ),
      ),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        width: width,
        height: width * 1.45,
        child: book.coverPath == null
            ? placeholder
            : Image.file(
                File(book.coverPath!),
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => placeholder,
              ),
      ),
    );
  }
}
