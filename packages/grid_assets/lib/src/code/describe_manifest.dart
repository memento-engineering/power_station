/// The DESCRIBE MANIFEST — the BOUNDED, DETERMINISTIC change facts the one-shot
/// describe pass hands the model IN PLACE OF the raw patch.
///
/// **Why facts and not the patch.** A18(1) routed the PR title/body through
/// inference over `origin/<base>...HEAD` because "a title read off the DIFF
/// says what actually changed". That is still true — and it is the FACTS in the
/// diff that say it, not the hunks. Re-deriving "which files changed, which
/// tests moved, did it pass" from a 60 KB patch is work a `git diff
/// --name-status` already did deterministically, paid for at inference prices
/// and answered with a model's guess. So the range stays exactly A18(1)'s (the
/// three-dot merge-base range `PinDiffCapability` pins the critics to, A9(2)),
/// the inference call stays exactly where A18(2) put it, and only the INPUT
/// changes: the model receives a rendered manifest of git facts, bead intent,
/// deterministic change shape and observer-written circuit receipts, and never
/// a hunk.
///
/// **Bounded by construction.** Every record is clamped before assembly
/// ([kMaxManifestRecordChars]); the assembly stops at a RECORD boundary under
/// [kMaxManifestBytes] of UTF-8; the section headers, the diffstat aggregate,
/// the change shape and the receipt provenance are REQUIRED lines that are
/// reserved before any record is admitted, so a truncated manifest still tells
/// the model (and a reader) exactly how much it is not seeing.
///
/// Pure: `String` in, `String` out. The git reads that feed it live in
/// `pr_describe.dart`; the receipts are read from the ambient `SiblingView` by
/// `DeliverRouteCapability` and threaded in here as VALUES.
library;

import 'dart:convert';

import 'package:path/path.dart' as p;

import 'docs_committee.dart';

/// The manifest's hard ceiling, in UTF-8 BYTES (16 KiB).
const int kMaxManifestBytes = 16 * 1024;

/// The bead's acceptance INTENT the manifest carries, capped in characters.
const int kMaxManifestIntentChars = 1200;

/// ONE manifest record (a commit message, a file line), capped in characters.
const int kMaxManifestRecordChars = 500;

/// How many AREAS (directories) the change-shape section names.
const int kMaxManifestAreas = 8;

/// How many fields ONE circuit receipt contributes to its rendered line.
const int kMaxManifestReceiptFields = 12;

/// The per-field value cap in a rendered receipt line.
const int kMaxManifestReceiptValueChars = 120;

/// Bytes held back from [kMaxManifestBytes] for the omission lines themselves,
/// so a section that truncates can always afford to SAY it truncated.
const int kManifestOmissionReserveBytes = 128;

/// One changed file — `git diff --name-status -z` joined with `--numstat -z`.
class ChangedFile {
  /// Creates the fact.
  const ChangedFile({
    required this.status,
    required this.path,
    this.fromPath,
    this.insertions,
    this.deletions,
  });

  /// The single-letter git status (`A`/`M`/`D`/`R`/`C`/`T`).
  final String status;

  /// The repo-relative path AFTER the change.
  final String path;

  /// The pre-image path of a rename/copy; null otherwise.
  final String? fromPath;

  /// Added lines; null when the file is binary (`-`) or unreported.
  final int? insertions;

  /// Removed lines; null when the file is binary (`-`) or unreported.
  final int? deletions;

  /// Whether this is a TEST file — a `test` path segment, or a `_test.dart`
  /// basename. Deterministic, and the reason the manifest can claim a truthful
  /// test count without a model guessing one.
  bool get isTest =>
      p.posix.split(path).contains('test') ||
      p.posix.basename(path).endsWith('_test.dart');

  /// The directory this file sits in (`(root)` for a top-level file).
  String get area {
    final dir = p.posix.dirname(path);
    return dir == '.' || dir.isEmpty ? '(root)' : dir;
  }
}

/// Parses `git diff --name-status -z` joined with `git diff --numstat -z` into
/// ONE path-sorted list of facts.
///
/// `-z` on both reads is load-bearing: it makes each record NUL-delimited, so a
/// path containing a space or a tab parses unambiguously and a rename arrives
/// as two whole paths rather than git's `{old => new}` display form. A numstat
/// entry with no matching name-status entry contributes nothing; a name-status
/// entry with no numstat entry keeps null counts.
List<ChangedFile> changedFilesFrom({
  required String nameStatus,
  required String numstat,
}) {
  final counts = _numstatCounts(numstat);
  final fields = _records(nameStatus);
  final files = <ChangedFile>[];
  var i = 0;
  while (i < fields.length) {
    final status = fields[i++];
    if (i >= fields.length) break;
    final first = fields[i++];
    final renamed = status.startsWith('R') || status.startsWith('C');
    String? fromPath;
    var path = first;
    if (renamed) {
      if (i >= fields.length) break;
      fromPath = first;
      path = fields[i++];
    }
    final count = counts[path];
    files.add(
      ChangedFile(
        status: status.substring(0, 1),
        path: path,
        fromPath: fromPath,
        insertions: count?.insertions,
        deletions: count?.deletions,
      ),
    );
  }
  files.sort((a, b) => a.path.compareTo(b.path));
  return List.unmodifiable(files);
}

class _Counts {
  const _Counts(this.insertions, this.deletions);
  final int? insertions;
  final int? deletions;
}

Map<String, _Counts> _numstatCounts(String output) {
  final counts = <String, _Counts>{};
  final fields = _records(output);
  var i = 0;
  while (i < fields.length) {
    final head = fields[i++].split('\t');
    if (head.length < 2) continue;
    final insertions = int.tryParse(head[0]);
    final deletions = int.tryParse(head[1]);
    String path;
    if (head.length >= 3 && head[2].isNotEmpty) {
      path = head[2];
    } else {
      // A rename/copy: `-z` puts the two paths in their OWN NUL records.
      if (i + 1 >= fields.length) break;
      i++; // the pre-image path; the counts key on the NEW path.
      path = fields[i++];
    }
    counts[path] = _Counts(insertions, deletions);
  }
  return counts;
}

List<String> _records(String output) =>
    output.split('\x00').where((field) => field.isNotEmpty).toList();

/// The FACTS one manifest renders — read by the land step at its run edge and
/// threaded in as VALUES (the renderer stays pure).
class DescribeManifest {
  /// Creates the facts.
  const DescribeManifest({
    required this.beadId,
    required this.beadTitle,
    required this.baseBranch,
    this.intent = '',
    this.commits = const [],
    this.files = const [],
    this.shortstat = '',
    this.shape = ChangeShape.code,
    this.receipts = const [],
  });

  /// The bead id — rendered as intent PROVENANCE, never as prose the model may
  /// echo (the never-write-the-tracker-id rule still rides the prompt).
  final String beadId;

  /// The bead's title.
  final String beadTitle;

  /// The base branch the delta is measured from.
  final String baseBranch;

  /// The bead's acceptance criteria — INTENT, never a claim about the code.
  final String intent;

  /// The branch's own commit messages (subject + body), in git order.
  final List<String> commits;

  /// The changed files, path-sorted ([changedFilesFrom]).
  final List<ChangedFile> files;

  /// `git diff --shortstat`'s aggregate line.
  final String shortstat;

  /// The bead's DECLARED change shape ([changeShapeOf]).
  final ChangeShape shape;

  /// The observer-written circuit receipts, rendered in list order.
  final List<DescribeReceipt> receipts;
}

/// ONE observer-written circuit receipt the manifest cites, with the node path
/// it was READ from — its PROVENANCE. The route that already reads the ambient
/// `SiblingView` supplies these; the manifest never guesses a node path, and a
/// receipt the session does not carry is simply absent.
class DescribeReceipt {
  /// Creates the receipt.
  const DescribeReceipt({
    required this.label,
    required this.nodePath,
    required this.result,
  });

  /// The manifest's name for this receipt (`validation`, `committee`).
  final String label;

  /// The node path the result payload was read from (the provenance).
  final String nodePath;

  /// The observer-written result payload.
  final Map<String, String> result;
}

/// Renders [facts] as the manifest text — the SOLE model input of the describe
/// pass. Stable section order, counts before optional detail, truncation only
/// at a record boundary, at most [kMaxManifestBytes] UTF-8 bytes.
String buildDescribeManifest(DescribeManifest facts) {
  final commitRecords = [
    for (final message in facts.commits) _commitRecord(message),
  ]..removeWhere((record) => record.isEmpty);
  final fileRecords = [for (final file in facts.files) _fileRecord(file)];

  final shortstat = _oneLine(facts.shortstat);
  final commitsBlock = _Block(
    ['## 2. Commits — ${facts.commits.length} total, in git order'],
    records: commitRecords,
    noun: 'commit',
  );
  final filesBlock = _Block(
    [
      '## 3. Files — ${facts.files.length} changed',
      '- diffstat: ${shortstat.isEmpty ? '(none reported)' : shortstat}',
    ],
    records: fileRecords,
    noun: 'file',
  );
  final blocks = <_Block>[
    _Block(_intentLines(facts)),
    commitsBlock,
    filesBlock,
    _Block(_shapeLines(facts)),
    _Block(_receiptLines(facts)),
  ];

  // The record budget: the ceiling, less the omission reserve and every
  // REQUIRED header. Commits get at most HALF, so neither droppable section can
  // starve the other; files then get the rest.
  var budget = kMaxManifestBytes - kManifestOmissionReserveBytes;
  for (final block in blocks) {
    budget -= _bytes(block.header.join('\n'));
  }
  if (budget < 0) budget = 0;
  final spentOnCommits = commitsBlock.fill(budget ~/ 2);
  filesBlock.fill(budget - spentOnCommits);

  final out = <String>[];
  for (final block in blocks) {
    if (out.isNotEmpty) out.add('');
    out.addAll(block.render());
  }
  return _clampBytes(out.join('\n'));
}

/// One rendered section: REQUIRED [header] lines that always survive, plus
/// droppable [records] admitted while the byte budget allows.
class _Block {
  _Block(this.header, {this.records = const [], this.noun = 'record'});

  final List<String> header;
  final List<String> records;
  final String noun;
  int _kept = 0;

  /// Admits records while they fit in [budget] bytes; returns bytes spent.
  int fill(int budget) {
    var spent = 0;
    for (final record in records) {
      final size = _bytes(record) + 1; // + the joining newline
      if (spent + size > budget) break;
      spent += size;
      _kept++;
    }
    return spent;
  }

  List<String> render() => [
    ...header,
    ...records.take(_kept),
    if (records.length > _kept)
      '- … ${records.length - _kept} of ${records.length} $noun records '
          'omitted (16 KiB manifest cap)',
  ];
}

List<String> _intentLines(DescribeManifest facts) {
  final intent = _clamp(facts.intent.trim(), kMaxManifestIntentChars);
  return [
    '# Change manifest — `origin/${facts.baseBranch}...HEAD`',
    '',
    '## 1. Intent (from the bead — never a claim about the code)',
    '- id: ${facts.beadId}',
    '- title: ${_oneLine(facts.beadTitle)}',
    if (intent.isEmpty)
      '- acceptance: (none recorded)'
    else ...[
      '- acceptance:',
      for (final line in const LineSplitter().convert(intent)) '  $line',
    ],
  ];
}

List<String> _shapeLines(DescribeManifest facts) {
  final areas = <String>{for (final file in facts.files) file.area}.toList()
    ..sort();
  final tests = facts.files.where((file) => file.isTest).length;
  final shown = areas.take(kMaxManifestAreas).join(', ');
  return [
    '## 4. Change shape',
    '- declared (bead `## Touches`): ${facts.shape.name}',
    '- observed (git): ${facts.files.length} changed files ($tests test)',
    '- areas (${areas.length} total): '
        '${shown.isEmpty ? '(none)' : shown}'
        '${areas.length > kMaxManifestAreas ? ', … ${areas.length - kMaxManifestAreas} more' : ''}',
  ];
}

List<String> _receiptLines(DescribeManifest facts) => [
  '## 5. Circuit receipts (observer-written; never the builder\'s account)',
  if (facts.receipts.isEmpty) '- (no receipts available)',
  for (final receipt in facts.receipts)
    '- ${receipt.label}: ${_receipt(receipt.result)} '
        '[from `${receipt.nodePath}`]',
];

String _receipt(Map<String, String> result) {
  if (result.isEmpty) return '(no receipt)';
  final keys = result.keys.toList()..sort();
  return [
    for (final key in keys.take(kMaxManifestReceiptFields))
      '$key=${_oneLine(_clamp(result[key]!, kMaxManifestReceiptValueChars))}',
  ].join(' ');
}

String _commitRecord(String message) {
  final lines = const LineSplitter()
      .convert(message.trim())
      .map((line) => line.trimRight())
      .where((line) => line.isNotEmpty)
      .toList();
  if (lines.isEmpty) return '';
  final b = StringBuffer('- ${lines.first}');
  for (final line in lines.skip(1)) {
    b.write('\n  $line');
  }
  return _clamp(b.toString(), kMaxManifestRecordChars);
}

String _fileRecord(ChangedFile file) {
  final counts = file.insertions == null && file.deletions == null
      ? '(binary)'
      : '+${file.insertions ?? 0} -${file.deletions ?? 0}';
  final path = file.fromPath == null
      ? file.path
      : '${file.fromPath} => ${file.path}';
  return _clamp('- ${file.status} $path $counts', kMaxManifestRecordChars);
}

String _oneLine(String text) => text.replaceAll(RegExp(r'\s+'), ' ').trim();

String _clamp(String text, int max) {
  final trimmed = text.trim();
  return trimmed.length <= max ? trimmed : '${trimmed.substring(0, max)}…';
}

int _bytes(String text) => utf8.encode(text).length;

/// The last belt: if the REQUIRED lines alone still exceed the ceiling (a route
/// that threads an absurd number of receipts), drop trailing LINES — a line IS
/// a record boundary — until the text fits. Never throws: the describe pass is
/// decoration (A18(6)), so it degrades rather than refuses.
String _clampBytes(String text) {
  if (_bytes(text) <= kMaxManifestBytes) return text;
  final lines = const LineSplitter().convert(text);
  while (lines.isNotEmpty && _bytes(lines.join('\n')) > kMaxManifestBytes) {
    lines.removeLast();
  }
  return lines.join('\n');
}
