import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  String? brief;
  await for (final line
      in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
    final frame = jsonDecode(line) as Map<String, Object?>;
    switch (frame['type']) {
      case 'brief':
        brief = frame['brief'] as String;
        if (args.contains('--exit-after-brief')) return;
        if (args.contains('--malformed-after-brief')) {
          stdout.writeln('{not-json');
          await stdout.flush();
          continue;
        }
        stdout.writeln(jsonEncode(<String, Object?>{'type': 'progress'}));
        await stdout.flush();
      case 'steer':
        stdout.writeln(
          jsonEncode(<String, Object?>{
            'type': 'completed',
            'result': <String, String>{
              'observedBrief': brief ?? '',
              'observedSteer': frame['text'] as String,
            },
            'usage': <String, Object?>{
              'tokensIn': 21,
              'tokensOut': 8,
              'numTurns': 2,
              'model': 'probe-model',
            },
          }),
        );
        await stdout.flush();
      default:
        stderr.writeln('unknown frame');
        exitCode = 64;
        return;
    }
  }
}
