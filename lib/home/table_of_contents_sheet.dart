import 'package:flutter/material.dart';

import '../reader/epub_reader_service.dart';
import '../theme/loremark_theme.dart';

/// Shows [entries] in a bottom sheet and returns the one the reader taps, or
/// null if they dismiss it.
///
/// [current] is highlighted so the reader can see where they are.
Future<TocEntry?> showTableOfContentsSheet(
  BuildContext context, {
  required List<TocEntry> entries,
  required TocEntry? current,
}) {
  return showModalBottomSheet<TocEntry>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * 0.75,
    ),
    builder: (context) =>
        TableOfContentsSheet(entries: entries, current: current),
  );
}

/// The book's chapters, indented by their nesting.
class TableOfContentsSheet extends StatelessWidget {
  const TableOfContentsSheet({
    super.key,
    required this.entries,
    required this.current,
  });

  final List<TocEntry> entries;
  final TocEntry? current;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 0, 22, 8),
          child: Text('CONTENTS', style: kicker()),
        ),
        Flexible(
          child: ListView.builder(
            shrinkWrap: true,
            padding: const EdgeInsets.only(bottom: 16),
            itemCount: entries.length,
            itemBuilder: (context, index) {
              final entry = entries[index];
              return ListTile(
                dense: true,
                selected: identical(entry, current),
                selectedColor: LoremarkColors.olive,
                selectedTileColor: LoremarkColors.panel,
                contentPadding: EdgeInsets.only(
                  left: 22 + entry.depth * 18.0,
                  right: 22,
                ),
                title: Text(
                  entry.title,
                  style: serif(15, height: 1.3),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => Navigator.pop(context, entry),
              );
            },
          ),
        ),
      ],
    );
  }
}
