import 'package:flutter/material.dart';

import 'empty_state.dart';

/// The Ask tab. Recaps and answers need an open book, so it shows the empty
/// state.
class AskScreen extends StatelessWidget {
  const AskScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const EmptyState(
      label: 'A THREAD BACK INTO THE STORY',
      title: 'Where we left off.',
      icon: Icons.chat_bubble_outline,
      message:
          'Open a book to get a recap and ask about what you’ve read.\n'
          'Answers only use the chapters you’ve reached.',
    );
  }
}
