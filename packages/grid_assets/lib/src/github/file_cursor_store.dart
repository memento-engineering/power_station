import 'dart:convert';
import 'dart:io';

import 'reconciler_cursor.dart';

/// A per-seat file cursor store using atomic sibling-file replacement.
///
/// Resident composition supplies an absolute path such as
/// `<seat-root>/.grid/github-reconciler/cursor.v1.json`. A relocated process
/// substitutes a centralized [GitHubCursorStore] without changing events or
/// projections.
class FileGitHubCursorStore implements GitHubCursorStore {
  /// Creates a file store at the required absolute [cursorPath].
  FileGitHubCursorStore({required this.cursorPath}) {
    if (!File(cursorPath).isAbsolute) {
      throw ArgumentError.value(cursorPath, 'cursorPath', 'must be absolute');
    }
  }

  /// Absolute cursor document path.
  final String cursorPath;

  @override
  Future<GitHubReconcilerCursor> load() async {
    final file = File(cursorPath);
    if (!await file.exists()) return const GitHubReconcilerCursor();
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) throw const FormatException('cursor must be a map');
      return GitHubReconcilerCursor.fromJson(
        Map<String, Object?>.from(decoded),
      );
    } on FormatException {
      rethrow;
    } catch (error) {
      throw FormatException('malformed GitHub cursor', error);
    }
  }

  @override
  Future<void> save(GitHubReconcilerCursor cursor) async {
    final file = File(cursorPath);
    await file.parent.create(recursive: true);
    final temp = File('$cursorPath.tmp');
    final sink = temp.openWrite();
    sink.write(jsonEncode(cursor.toJson()));
    await sink.flush();
    await sink.close();
    await temp.rename(cursorPath);
  }
}
