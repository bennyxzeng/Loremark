import 'dart:io';

import 'package:flutter/material.dart';

import '../home/book_screen.dart';
import '../settings/settings_screen.dart';
import '../theme/decor.dart';
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
      body: PaperBackground(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 96),
            children: [
              Row(
                children: [
                  const _Wordmark(),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Settings',
                    onPressed: () => SettingsScreen.push(context),
                    icon: const Icon(
                      Icons.settings_outlined,
                      color: LoremarkColors.muted,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _WelcomeBanner(
                lastOpened: repository?.lastOpened,
                onContinue: _open,
              ),
              const SizedBox(height: 30),
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
      ),
    );
  }
}

/// The top of the library: a greeting over the companion illustration, and a
/// way back into the last book.
class _WelcomeBanner extends StatelessWidget {
  const _WelcomeBanner({required this.lastOpened, required this.onContinue});

  final Book? lastOpened;
  final void Function(Book) onContinue;

  static String _greeting(DateTime now) => switch (now.hour) {
    < 5 => 'READING LATE',
    < 12 => 'GOOD MORNING',
    < 18 => 'GOOD AFTERNOON',
    _ => 'GOOD EVENING',
  };

  @override
  Widget build(BuildContext context) {
    final book = lastOpened;
    return Container(
      height: 176,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: LoremarkColors.welcomeBorder),
        gradient: const LinearGradient(
          colors: [LoremarkColors.welcomeStart, LoremarkColors.welcomeEnd],
        ),
        boxShadow: [
          BoxShadow(
            color: LoremarkColors.readerTitle.withValues(alpha: 0.10),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // The illustration fills the right side and fades out to the left,
          // under the text.
          Positioned(
            top: 0,
            bottom: 0,
            right: 0,
            left: 150,
            child: ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (bounds) => const LinearGradient(
                colors: [Colors.transparent, Colors.white],
                stops: [0, 0.4],
              ).createShader(bounds),
              child: Image.asset(
                LoremarkArt.libraryHeader,
                fit: BoxFit.cover,
                alignment: const Alignment(0.15, -0.35),
                excludeFromSemantics: true,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_greeting(DateTime.now()), style: kicker(size: 9)),
                const SizedBox(height: 12),
                if (book != null)
                  _BannerBook(book: book)
                else
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 170),
                    child: Text(
                      'Your shelf is waiting',
                      style: serif(
                        20,
                        height: 1.2,
                        color: LoremarkColors.welcomeTitle,
                      ),
                    ),
                  ),
                const Spacer(),
                if (book != null)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 190),
                    child: Material(
                      color: LoremarkColors.paper.withValues(alpha: 0.92),
                      shape: const StadiumBorder(),
                      child: InkWell(
                        customBorder: const StadiumBorder(),
                        onTap: () => onContinue(book),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 7, 8, 7),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Flexible(
                                child: Text(
                                  'Continue reading',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: LoremarkColors.olive,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 2),
                              const Icon(
                                Icons.chevron_right,
                                size: 18,
                                color: LoremarkColors.olive,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  )
                else
                  const Text(
                    'Import an EPUB to begin.',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.45,
                      color: LoremarkColors.welcomeText,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The book in the banner: a small cover beside its title and author.
class _BannerBook extends StatelessWidget {
  const _BannerBook({required this.book});

  final Book book;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 165),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              boxShadow: [
                BoxShadow(
                  color: LoremarkColors.readerTitle.withValues(alpha: 0.18),
                  blurRadius: 6,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: BookCover(book: book, width: 38),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  book.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: serif(
                    16,
                    height: 1.25,
                    color: LoremarkColors.welcomeTitle,
                  ),
                ),
                if (book.author case final author?) ...[
                  const SizedBox(height: 3),
                  Text(
                    author,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: LoremarkColors.welcomeText,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
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
        const SizedBox(height: 8),
        Image.asset(
          LoremarkArt.chibiReading,
          height: 170,
          excludeFromSemantics: true,
        ),
        const SizedBox(height: 10),
        Text('An empty shelf, for now', style: serif(19)),
        const SizedBox(height: 8),
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
