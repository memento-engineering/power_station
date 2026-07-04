// Proof of the ACP-shaped JSON-RPC 2.0 envelope (D-B3): round-trip encode/
// decode for all four shapes (request/notification/result/error), and the
// `dart:convert`-free public seam (encodeAcp/decodeAcp operate on the SAME
// bytes a Broker.publish/subscribe carries).
import 'dart:convert';
import 'dart:typed_data';

import 'package:federated_grid_assets/federated_grid_assets.dart';
import 'package:test/test.dart';

void main() {
  group('AcpMessage.fromJson dispatch', () {
    test('method + id → AcpRequest', () {
      final msg = AcpMessage.fromJson({
        'jsonrpc': '2.0',
        'id': 'abc',
        'method': 'grid/claim/respond',
        'params': {'claimId': 'x'},
      });
      expect(msg, isA<AcpRequest>());
      final req = msg as AcpRequest;
      expect(req.id, 'abc');
      expect(req.method, 'grid/claim/respond');
      expect(req.params, {'claimId': 'x'});
    });

    test('method, no id → AcpNotification', () {
      final msg = AcpMessage.fromJson({
        'jsonrpc': '2.0',
        'method': 'grid/claim/unclaimed',
        'params': {'claimId': 'x'},
      });
      expect(msg, isA<AcpNotification>());
      expect((msg as AcpNotification).method, 'grid/claim/unclaimed');
    });

    test('no method, result → AcpResultResponse', () {
      final msg = AcpMessage.fromJson({
        'jsonrpc': '2.0',
        'id': 'abc',
        'result': {'confirmed': true},
      });
      expect(msg, isA<AcpResultResponse>());
      final res = msg as AcpResultResponse;
      expect(res.id, 'abc');
      expect(res.result, {'confirmed': true});
    });

    test('no method, error → AcpErrorResponse', () {
      final msg = AcpMessage.fromJson({
        'jsonrpc': '2.0',
        'id': 'abc',
        'error': {'code': 1, 'message': 'nope', 'data': {'why': 'late'}},
      });
      expect(msg, isA<AcpErrorResponse>());
      final err = msg as AcpErrorResponse;
      expect(err.code, 1);
      expect(err.message, 'nope');
      expect(err.data, {'why': 'late'});
    });
  });

  group('encodeAcp/decodeAcp byte round-trip', () {
    test('request', () {
      const msg = AcpRequest(
        id: 'r1',
        method: 'grid/claim/respond',
        params: {'claimId': 'x', 'station': 'b'},
      );
      final decoded = decodeAcp(encodeAcp(msg));
      expect(decoded, isA<AcpRequest>());
      expect((decoded as AcpRequest).toJson(), msg.toJson());
    });

    test('notification', () {
      const msg = AcpNotification(
        method: 'grid/claim/unclaimed',
        params: {'claimId': 'x'},
      );
      final decoded = decodeAcp(encodeAcp(msg));
      expect(decoded, isA<AcpNotification>());
      expect((decoded as AcpNotification).toJson(), msg.toJson());
    });

    test('result response', () {
      const msg = AcpResultResponse(id: 'r1', result: {'confirmed': true});
      final decoded = decodeAcp(encodeAcp(msg));
      expect(decoded, isA<AcpResultResponse>());
      expect((decoded as AcpResultResponse).toJson(), msg.toJson());
    });

    test('error response', () {
      const msg = AcpErrorResponse(id: 'r1', code: 2, message: 'denied');
      final decoded = decodeAcp(encodeAcp(msg));
      expect(decoded, isA<AcpErrorResponse>());
      expect((decoded as AcpErrorResponse).toJson(), msg.toJson());
    });

    test('every encoded message stamps jsonrpc 2.0', () {
      const msgs = [
        AcpRequest(id: '1', method: 'grid/claim/respond'),
        AcpNotification(method: 'grid/claim/unclaimed'),
        AcpResultResponse(id: '1'),
        AcpErrorResponse(id: '1', code: 0, message: ''),
      ];
      for (final m in msgs) {
        expect(m.toJson()['jsonrpc'], '2.0');
      }
    });

    test('decodeAcp throws FormatException on invalid JSON', () {
      final bad = Uint8List.fromList(utf8.encode('not json at all'));
      expect(() => decodeAcp(bad), throwsFormatException);
    });
  });
}
