library;

import 'dart:convert';

import 'package:beads_dart/beads_dart.dart' show Bead;
import 'package:crypto/crypto.dart' show sha256;

/// Returns the stable key for every bead value that contributes embeddings.
String embeddingChangeKey(Bead bead) {
  final fields = <String>[
    bead.title,
    bead.description,
    bead.design,
    bead.acceptanceCriteria,
    bead.notes,
    bead.closeReason,
  ];
  final bytes = <int>[];
  for (final value in fields) {
    final encoded = utf8.encode(value);
    bytes
      ..addAll(utf8.encode('${encoded.length}:'))
      ..addAll(encoded);
  }
  return sha256.convert(bytes).toString();
}
