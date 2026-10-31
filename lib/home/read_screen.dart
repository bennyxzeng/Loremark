import 'package:flutter/material.dart';

import '../library/book.dart';
import '../library/library_screen.dart';
import '../theme/loremark_theme.dart';

/// The Read tab. The EPUB reader is not built yet, so it shows the book's
/// cover and details.
class ReadScreen extends StatelessWidget {
  const ReadScreen({super.key, required this.book});

  final Book book;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 32, 22, 32),
      children: [
        Center(child: BookCover(book: book, width: 120)),
        const SizedBox(height: 24),
        Text(
          book.title,
          textAlign: TextAlign.center,
          style: serif(26, color: LoremarkColors.readerTitle, height: 1.25),
        ),
        if (book.author case final author?) ...[
          const SizedBox(height: 6),
          Text(
            author,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, color: LoremarkColors.muted),
          ),
        ],
        const SizedBox(height: 28),
        const Text(
          'The reading view is coming soon.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: LoremarkColors.muted),
        ),
      ],
    );
  }
}
