import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:federated_grid_assets/federated_grid_assets.dart';
import 'package:test/test.dart';

ServeCommand _command({ServeProfileFactory? profileFor}) => ServeCommand(
  defaultKind: 'compute',
  configureFlags: (_) {},
  profileFor: profileFor,
  handlerFor: (_, _) =>
      (handler: (payload) async => payload, banner: null, onLeaseEnded: null),
);

ArgResults _parse(ServeCommand command, List<String> args) =>
    command.argParser.parse(args);

void main() {
  test('parses repeated kind and slots pairs in order', () {
    final command = _command();
    final args = _parse(command, [
      '--kind',
      'kind-a',
      '--slots',
      '1',
      '--kind',
      'kind-b',
      '--slots',
      '3',
    ]);
    expect(command.serveOfferings(args), {'kind-a': 1, 'kind-b': 3});
  });

  test('legacy single kind and slots pair is unchanged', () {
    final command = _command();
    expect(
      command.serveOfferings(
        _parse(command, ['--kind', 'compute', '--slots', '2']),
      ),
      {'compute': 2},
    );
  });

  test('defaults retain the domain default kind and one slot', () {
    final command = _command();
    expect(command.serveOfferings(_parse(command, [])), {'compute': 1});
  });

  test('rejects unequal pair counts', () {
    final command = _command();
    expect(
      () => command.serveOfferings(
        _parse(command, ['--kind', 'a', '--kind', 'b', '--slots', '1']),
      ),
      throwsA(isA<UsageException>()),
    );
  });

  test('rejects empty or duplicate kinds', () {
    final command = _command();
    for (final args in [
      ['--kind=', '--slots', '1'],
      ['--kind', 'a', '--slots', '1', '--kind', 'a', '--slots', '2'],
    ]) {
      expect(
        () => command.serveOfferings(_parse(command, args)),
        throwsA(isA<UsageException>()),
      );
    }
  });

  test('rejects non-positive and non-integer slots', () {
    final command = _command();
    for (final slots in ['0', '-1', 'many']) {
      expect(
        () => command.serveOfferings(
          _parse(command, ['--kind', 'a', '--slots', slots]),
        ),
        throwsA(isA<UsageException>()),
      );
    }
  });

  test('profile factory receives parsed domain arguments unchanged', () {
    late ArgResults seen;
    final command = _command(
      profileFor: (args) {
        seen = args;
        return const {
          'targets': [
            {'platform': 'android'},
          ],
        };
      },
    );
    final args = _parse(command, ['--kind', 'compute', '--slots', '2']);
    expect(command.profileFor(args), const {
      'targets': [
        {'platform': 'android'},
      ],
    });
    expect(seen, same(args));
  });
}
