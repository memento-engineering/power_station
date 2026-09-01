import 'dart:async';
import 'dart:convert';
import 'dart:io';

late final String _identity;
late final File? _trace;
late final List<String> _models;
late final String _current;
late final String _stopReason;
late final Set<String> _flags;

int _turn = 0;
final Map<Object, Map<String, dynamic>> _permissionPrompts = {};

Future<void> main(List<String> args) async {
  _identity = _arg(args, '--identity=') ?? 'probe';
  final tracePath = Platform.environment['GRID_ACP_PROBE_TRACE'];
  _trace = tracePath == null ? null : File(tracePath);
  _models = (_arg(args, '--models=') ?? 'gpt-5.6-sol[low],gpt-5.6-sol[xhigh]')
      .split(',')
      .where((value) => value.isNotEmpty)
      .toList(growable: false);
  _current = _arg(args, '--current=') ?? 'gpt-5.6-sol[xhigh]';
  _stopReason = _arg(args, '--stop-reason=') ?? 'end_turn';
  _flags = args
      .where((arg) => arg.startsWith('--') && !arg.contains('='))
      .toSet();

  await for (final line
      in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
    final message = jsonDecode(line) as Map<String, dynamic>;
    final method = message['method'] as String?;
    if (method != null) {
      await _record(<String, Object?>{
        'kind': 'method',
        'method': method,
        'params': message['params'],
      });
      await _handleMethod(message, method);
    } else if (message.containsKey('id')) {
      await _handlePermissionResponse(message);
    }
  }
}

String? _arg(List<String> args, String prefix) {
  for (final arg in args) {
    if (arg.startsWith(prefix)) return arg.substring(prefix.length);
  }
  return null;
}

Future<void> _handleMethod(Map<String, dynamic> request, String method) async {
  switch (method) {
    case 'initialize':
      _respond(request, <String, Object?>{
        'protocolVersion': 1,
        'agentCapabilities': <String, Object?>{},
        'agentInfo': <String, Object?>{'name': _identity, 'version': '1'},
      });
    case 'session/new':
      _respond(request, <String, Object?>{
        'sessionId': 'session-$_identity',
        if (!_flags.contains('--no-model-state'))
          'models': <String, Object?>{
            'currentModelId': _current,
            'availableModels': <Map<String, String>>[
              for (final model in _models)
                <String, String>{'modelId': model, 'name': model},
            ],
          },
      });
    case 'session/set_model':
      _respond(request, <String, Object?>{});
    case 'session/prompt':
      await _beginPrompt(request);
    case 'session/cancel':
      return;
    default:
      _error(request, -32601, 'method not found: $method');
  }
}

Future<void> _beginPrompt(Map<String, dynamic> request) async {
  if (_flags.contains('--exit-on-prompt')) {
    exit(23);
  }
  if (_flags.contains('--malformed-on-prompt')) {
    stdout.writeln('{malformed');
    await stdout.flush();
    return;
  }
  if (_flags.contains('--close-output-on-prompt')) {
    await stdout.close();
    return;
  }
  if (_flags.contains('--prompt-error')) {
    _error(request, -32001, 'probe prompt failure');
    return;
  }

  final turn = ++_turn;
  final permissionId = 'permission-$turn';
  _permissionPrompts[permissionId] = request;
  _send(<String, Object?>{
    'jsonrpc': '2.0',
    'id': permissionId,
    'method': 'session/request_permission',
    'params': <String, Object?>{
      'sessionId': 'session-$_identity',
      'toolCall': <String, Object?>{
        'toolCallId': 'tool-$turn',
        'title': 'probe tool $turn',
      },
      'options': <Map<String, String>>[
        <String, String>{
          'optionId': 'reject-always-$turn',
          'name': 'Reject always',
          'kind': 'reject_always',
        },
        <String, String>{
          'optionId': 'allow-once-$turn',
          'name': 'Allow once',
          'kind': 'allow_once',
        },
        <String, String>{
          'optionId': 'allow-always-$turn',
          'name': 'Allow always',
          'kind': 'allow_always',
        },
      ],
    },
  });
}

Future<void> _handlePermissionResponse(Map<String, dynamic> response) async {
  final id = response['id'];
  final prompt = _permissionPrompts.remove(id);
  if (prompt == null) return;
  final result = response['result'] as Map<String, dynamic>?;
  final outcome = result?['outcome'] as Map<String, dynamic>?;
  await _record(<String, Object?>{
    'kind': 'permission',
    'outcome': outcome?['outcome'],
    'optionId': outcome?['optionId'],
  });

  final turn = int.parse((id as String).substring('permission-'.length));
  _notify(<String, Object?>{
    'sessionUpdate': 'agent_thought_chunk',
    'content': <String, Object?>{
      'type': 'text',
      'text': 'thought-$_identity-$turn ',
    },
  });
  _notify(<String, Object?>{
    'sessionUpdate': 'agent_message_chunk',
    'content': <String, Object?>{
      'type': 'text',
      'text': turn == 1
          ? 'READY FOR STEER $_identity '
          : 'FINISHED $_identity ',
    },
  });
  await stdout.flush();

  Timer(const Duration(milliseconds: 150), () {
    _respond(prompt, <String, Object?>{
      'stopReason': _stopReason,
      'usage': <String, Object?>{
        'inputTokens': 11,
        'outputTokens': 7,
        'totalTokens': 18,
      },
    });
  });
}

void _notify(Map<String, Object?> update) {
  _send(<String, Object?>{
    'jsonrpc': '2.0',
    'method': 'session/update',
    'params': <String, Object?>{
      'sessionId': 'session-$_identity',
      'update': update,
    },
  });
}

void _respond(Map<String, dynamic> request, Map<String, Object?> result) {
  _send(<String, Object?>{
    'jsonrpc': '2.0',
    'id': request['id'],
    'result': result,
  });
}

void _error(Map<String, dynamic> request, int code, String message) {
  _send(<String, Object?>{
    'jsonrpc': '2.0',
    'id': request['id'],
    'error': <String, Object?>{'code': code, 'message': message},
  });
}

void _send(Map<String, Object?> frame) {
  stdout.writeln(jsonEncode(frame));
}

Future<void> _record(Map<String, Object?> entry) async {
  final trace = _trace;
  if (trace == null) return;
  await trace.writeAsString(
    '${jsonEncode(entry)}\n',
    mode: FileMode.append,
    flush: true,
  );
}
