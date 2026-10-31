import 'package:flutter/material.dart';

import 'empty_state.dart';

/// The Notes tab. Notes and theories are not saved yet, so it shows the empty
/// state.
class NotesScreen extends StatelessWidget {
  const NotesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const EmptyState(
      label: 'IN THE MARGINS',
      title: 'Notes & theories',
      icon: Icons.edit_note,
      message:
          'Your notes and theories will appear here.\n'
          'A theory stays unconfirmed until the story settles it.',
    );
  }
}
