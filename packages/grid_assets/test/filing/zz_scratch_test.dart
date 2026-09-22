import 'dart:io';
import 'package:test/test.dart';

Future<void> dump(String label, Directory store) async {
  final get = await Process.run('bd', ['-C', store.path, 'config', 'get', 'issue_prefix']);
  // ignore: avoid_print
  print('$label get=${get.exitCode} out=${(get.stdout as String).trim()} err=${(get.stderr as String).trim()}');
  final proxy = File('${store.path}/.beads/dolt/proxy.pid');
  // ignore: avoid_print
  print('$label proxy=${proxy.existsSync() ? proxy.readAsStringSync().trim() : 'absent'}');
}

void main() {
  test('scratch variants', () async {
    for (final variant in ['withEnv', 'noEnv', 'shellCd']) {
      final store = Directory.systemTemp.createTempSync('zz-$variant-');
      final ProcessResult init;
      const args = ['init', '--prefix', 'filing', '--skip-agents',
        '--skip-hooks', '--non-interactive', '--proxied-server'];
      if (variant == 'withEnv') {
        init = await Process.run('bd', args, workingDirectory: store.path,
          environment: {...Platform.environment, 'BD_NON_INTERACTIVE': '1'});
      } else if (variant == 'noEnv') {
        init = await Process.run('bd', args, workingDirectory: store.path);
      } else {
        init = await Process.run('/bin/sh', ['-c',
          'cd ${store.path} && BD_NON_INTERACTIVE=1 bd ${args.join(' ')}']);
      }
      // ignore: avoid_print
      print('--- $variant init=${init.exitCode} ${store.path}');
      await dump(variant, store);
      final sql = await Process.run('dolt', [
        '--data-dir=${store.path}/.beads/dolt', '--use-db=filing',
        'sql', '-q', 'select * from config', '-r', 'csv',
      ]);
      // ignore: avoid_print
      print('$variant sql=${sql.exitCode} ${(sql.stdout as String).trim()} ${(sql.stderr as String).trim()}');
      await Process.run('pkill', ['-f', store.path]);
    }
  });
}
