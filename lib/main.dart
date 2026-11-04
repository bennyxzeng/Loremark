import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'library/book_repository.dart';
import 'library/library_screen.dart';
import 'settings/ai_settings.dart';
import 'settings/api_key_screen.dart';
import 'settings/connection_status.dart';
import 'theme/loremark_theme.dart';

void main() {
  // Both stores below talk to the platform before runApp, which needs the
  // binding first.
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    LoremarkApp(
      repository: BookRepository.open(),
      settings: AiSettings.open(),
      connection: ConnectionStatus.watchPlatform(),
    ),
  );
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
    required this.settings,
    required this.connection,
    this.pickEpub = _pickEpub,
  });

  final Future<BookRepository> repository;
  final Future<AiSettings> settings;
  final ConnectionStatus connection;
  final EpubPicker pickEpub;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AiSettings>(
      future: settings,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Directionality(
            textDirection: TextDirection.ltr,
            child: ColoredBox(
              color: LoremarkColors.paper,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Couldn’t load Loremark’s settings.\n${snapshot.error}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 14,
                      color: LoremarkColors.ink,
                    ),
                  ),
                ),
              ),
            ),
          );
        }
        final loaded = snapshot.data;
        // Settings come from the keychain in a moment; show plain paper
        // rather than flash the library before the first-run screen.
        if (loaded == null) {
          return const ColoredBox(color: LoremarkColors.paper);
        }
        return AiSettingsScope(
          settings: loaded,
          child: ConnectionScope(
            status: connection,
            child: MaterialApp(
              title: 'Loremark',
              debugShowCheckedModeBanner: false,
              theme: buildLoremarkTheme(),
              home: _Home(repository: repository, pickEpub: pickEpub),
            ),
          ),
        );
      },
    );
  }
}

/// The first-run API key screen until it's answered, then the library.
class _Home extends StatelessWidget {
  const _Home({required this.repository, required this.pickEpub});

  final Future<BookRepository> repository;
  final EpubPicker pickEpub;

  @override
  Widget build(BuildContext context) {
    if (!AiSettingsScope.of(context).onboardingSeen) {
      return const ApiKeyScreen(onboarding: true);
    }
    return LibraryScreen(repository: repository, pickEpub: pickEpub);
  }
}
