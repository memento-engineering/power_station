import 'dart:convert';
import 'dart:io';

import 'package:github_grid_assets/github_grid_assets.dart';
import 'package:grid_cli/grid_cli.dart';
import 'package:test/test.dart';

void main() {
  test('sends exact fenced keyed resident rework request', () async {
    final root = await Directory.systemTemp.createTemp('feedback-command-');
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async {
      await server.close(force: true);
      await root.delete(recursive: true);
    });
    final lock = File(StationLockService.lockPath(root.path));
    await lock.parent.create(recursive: true);
    await lock.writeAsString(
      jsonEncode(
        StationLockRecord(
          pid: 42,
          pgid: 42,
          startedAt: DateTime.utc(2026),
          controlUrl: 'http://${server.address.address}:${server.port}',
          token: 'secret',
        ).toJson(),
      ),
    );
    late HttpRequest received;
    late Map<String, Object?> body;
    final serve = () async {
      received = await server.first;
      body = (jsonDecode(await utf8.decoder.bind(received).join()) as Map)
          .cast<String, Object?>();
      received.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode({
            'id': body['id'],
            'result': {'round': 1},
          }),
        );
      await received.response.close();
    }();

    final result =
        await ResidentFeedbackCommandSender(
          clock: () => DateTime.utc(2026, 1, 2, 3, 4, 5, 6, 7),
        ).rework(
          gridRoot: root.path,
          beadId: 'tg-1',
          note: 'red',
          idempotencyKey: 'github-ci:tg-1:r0:build:obs',
        );
    await serve;

    expect(result, isA<FeedbackCommandCompleted>());
    expect(received.method, 'POST');
    expect(received.uri.path, '/command');
    expect(
      received.headers.value(HttpHeaders.authorizationHeader),
      'Bearer secret',
    );
    expect(
      received.headers.value('X-Grid-Fence'),
      '${DateTime.utc(2026, 1, 2, 3, 4, 5, 6, 7).microsecondsSinceEpoch}',
    );
    expect(
      received.headers.value('Idempotency-Key'),
      'github-ci:tg-1:r0:build:obs',
    );
    expect(body, {
      'id': 'github-ci:tg-1:r0:build:obs',
      'method': 'grid/rework',
      'params': {'beadId': 'tg-1', 'note': 'red', 'beyondCap': false},
    });
  });

  test('preserves resident refusal code', () async {
    final root = await Directory.systemTemp.createTemp('feedback-refusal-');
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async {
      await server.close(force: true);
      await root.delete(recursive: true);
    });
    final lock = File(StationLockService.lockPath(root.path));
    await lock.parent.create(recursive: true);
    await lock.writeAsString(
      jsonEncode({
        'pid': 42,
        'pgid': 42,
        'startedAt': DateTime.utc(2026).toIso8601String(),
        'controlUrl': 'http://${server.address.address}:${server.port}',
        'token': 'secret',
      }),
    );
    final serve = () async {
      final request = await server.first;
      await utf8.decoder.bind(request).join();
      request.response
        ..statusCode = HttpStatus.conflict
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode({
            'id': 'key',
            'error': {'code': 'rework_round_cap', 'message': 'cap'},
          }),
        );
      await request.response.close();
    }();
    final result = await ResidentFeedbackCommandSender().rework(
      gridRoot: root.path,
      beadId: 'tg-1',
      note: 'red',
      idempotencyKey: 'key',
    );
    await serve;
    expect(
      result,
      isA<FeedbackCommandRefused>().having(
        (value) => value.code,
        'code',
        'rework_round_cap',
      ),
    );
  });

  test('unavailable and malformed transport fail loudly', () async {
    final root = await Directory.systemTemp.createTemp('feedback-missing-');
    addTearDown(() => root.delete(recursive: true));
    await expectLater(
      ResidentFeedbackCommandSender().rework(
        gridRoot: root.path,
        beadId: 'tg-1',
        note: 'red',
        idempotencyKey: 'key',
      ),
      throwsStateError,
    );
  });
}
