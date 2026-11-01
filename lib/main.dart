import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'library/book_repository.dart';
import 'library/library_screen.dart';
import 'theme/loremark_theme.dart';

void main() {
  runApp(LoremarkApp(repository: BookRepository.open()));
}

Future<String?> _pickEpub() async {
  final file = await FilePicker.pickFile(
    type: FileType.custom,
    allowedExtensions: ['epub'],
  );
  return file?.path;
}

class LoremarkApp extends StatelessWidget {
  const LoremarkApp({
    super.key,
    required this.repository,
    this.pickEpub = _pickEpub,
  });

  final Future<BookRepository> repository;
  final EpubPicker pickEpub;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Loremark',
      debugShowCheckedModeBanner: false,
      theme: buildLoremarkTheme(),
      home: LibraryScreen(repository: repository, pickEpub: pickEpub),
    );
  }
}
