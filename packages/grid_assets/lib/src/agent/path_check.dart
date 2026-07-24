/// Shell builtins and grammar words that do not require a PATH lookup.
const _shellBuiltins = <String>{
  '!',
  '{',
  '}',
  'break',
  'case',
  'cd',
  'command',
  'continue',
  'do',
  'done',
  'elif',
  'else',
  'esac',
  'eval',
  'exec',
  'exit',
  'export',
  'fi',
  'for',
  'if',
  'in',
  'read',
  'return',
  'set',
  'shift',
  'then',
  'trap',
  'unset',
  'until',
  'wait',
  'while',
};

/// External executables occupying command positions in [plan].
List<String> shellCommandExecutables(String plan) {
  final matches = RegExp(
    r'(?:^|&&|\|\||[;|\n]|[()])\s*'
    r'(?:[A-Za-z_][A-Za-z0-9_]*=[^\s;&|()]+\s+)*'
    r'([^\s;&|()]+)',
  ).allMatches(plan);
  final found = <String>{};
  for (final match in matches) {
    final executable = match.group(1)!;
    if (!_shellBuiltins.contains(executable)) found.add(executable);
  }
  return found.toList(growable: false);
}

/// Advisory PATH candidates after [exitCode] has already been observed.
String? pathCheckDiagnostic(String plan, int exitCode) {
  if (exitCode != 127) return null;
  final candidates = shellCommandExecutables(plan);
  final names = candidates.isEmpty ? 'none identified' : candidates.join(', ');
  return 'exit 127 — candidate missing commands: $names';
}
