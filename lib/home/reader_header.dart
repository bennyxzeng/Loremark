import 'package:flutter/material.dart';

import '../library/book.dart';
import '../theme/loremark_theme.dart';

/// The top of every tab: the open book. Tapping it returns to the library.
class ReaderHeader extends StatelessWidget {
  const ReaderHeader({
    super.key,
    required this.book,
    required this.onOpenLibrary,
  });

  final Book book;
  final VoidCallback onOpenLibrary;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: LoremarkColors.header,
      shape: const Border(bottom: BorderSide(color: Color(0xFFEDDFCD))),
      child: Semantics(
        button: true,
        label: 'Library',
        child: InkWell(
          onTap: onOpenLibrary,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Row(
              children: [
                const Icon(Icons.chevron_left, color: LoremarkColors.muted),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'CURRENTLY READING',
                        style: kicker(color: LoremarkColors.muted, size: 9),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        book.title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.local_library_outlined,
                  color: LoremarkColors.muted,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
