import 'epub_reader_service.dart';

/// Renders EPUBs with Readium through the `flutter_readium` plugin.
///
/// This is the only file that imports the plugin.
class ReadiumReaderService implements EpubReaderService {
  const ReadiumReaderService();

  @override
  Future<EpubReaderSession> open(String epubPath) => throw UnimplementedError();
}
