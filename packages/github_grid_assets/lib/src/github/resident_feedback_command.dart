import 'dart:convert';
import 'dart:io';

import 'package:grid_cli/grid_cli.dart'
    show HttpClientFactory, StationLockService;
import 'package:grid_diagnostics_contract/grid_diagnostics_contract.dart';

sealed class FeedbackCommandResult {
  const FeedbackCommandResult();
}

final class FeedbackCommandCompleted extends FeedbackCommandResult {
  const FeedbackCommandCompleted(this.value);
  final Map<String, Object?> value;
}

final class FeedbackCommandRefused extends FeedbackCommandResult {
  const FeedbackCommandRefused(this.code, this.message);
  final String code;
  final String message;
}

abstract interface class FeedbackCommandSender {
  Future<FeedbackCommandResult> rework({
    required String gridRoot,
    required String beadId,
    required String note,
    required String idempotencyKey,
  });
}

/// Sends CI feedback through the already-running station's command endpoint.
final class ResidentFeedbackCommandSender implements FeedbackCommandSender {
  ResidentFeedbackCommandSender({
    HttpClientFactory? httpClientFactory,
    DateTime Function()? clock,
  }) : _httpClientFactory = httpClientFactory ?? HttpClient.new,
       _clock = clock ?? DateTime.now;

  final HttpClientFactory _httpClientFactory;
  final DateTime Function() _clock;

  @override
  Future<FeedbackCommandResult> rework({
    required String gridRoot,
    required String beadId,
    required String note,
    required String idempotencyKey,
  }) async {
    final lockPath = StationLockService.lockPath(gridRoot);
    try {
      final decoded = jsonDecode(await File(lockPath).readAsString());
      if (decoded is! Map) throw const FormatException('lock is not an object');
      final record = StationLockRecord.fromJson(
        decoded.cast<String, Object?>(),
      );
      final controlUrl = record.controlUrl;
      final token = record.token;
      if (controlUrl == null || token == null) {
        throw const FormatException('lock has no control endpoint or bearer');
      }
      final fence = _clock().toUtc().microsecondsSinceEpoch;
      final client = _httpClientFactory()
        ..connectionTimeout = const Duration(seconds: 3);
      try {
        final request = await client.postUrl(
          Uri.parse('${controlUrl.replaceFirst(RegExp(r'/$'), '')}/command'),
        );
        request.headers
          ..set(HttpHeaders.authorizationHeader, 'Bearer $token')
          ..set('X-Grid-Fence', '$fence')
          ..set('Idempotency-Key', idempotencyKey)
          ..contentType = ContentType.json;
        request.write(
          jsonEncode({
            'id': idempotencyKey,
            'method': 'grid/rework',
            'params': {'beadId': beadId, 'note': note, 'beyondCap': false},
          }),
        );
        final response = await request.close();
        final raw = await response.transform(const Utf8Decoder()).join();
        final value = jsonDecode(raw);
        if (value is! Map) {
          throw const FormatException('response is not an object');
        }
        final body = value.cast<String, Object?>();
        if (response.statusCode == HttpStatus.ok &&
            !body.containsKey('error')) {
          final result = body['result'];
          if (result is! Map) {
            throw const FormatException('result is not an object');
          }
          return FeedbackCommandCompleted(result.cast<String, Object?>());
        }
        final error = body['error'];
        if (error is! Map) {
          throw const FormatException('error is not an object');
        }
        final typed = error.cast<String, Object?>();
        final code = typed['code'];
        final message = typed['message'];
        if (code is! String || message is! String) {
          throw const FormatException('error has no code or message');
        }
        return FeedbackCommandRefused(code, message);
      } finally {
        client.close(force: true);
      }
    } on Object catch (error) {
      if (error is StateError) rethrow;
      throw StateError('resident feedback transport unavailable: $error');
    }
  }
}
