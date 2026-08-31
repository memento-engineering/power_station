library;

/// Local decision-register directories, in legacy-first order.
///
/// A substation may expose either directory or both during the migration.
const List<String> kLocalDecisionRegisterDirectories = [
  'docs/adr',
  'docs/decisions',
];

String _forEachLocalDecisionRegister(String command) =>
    'for register in ${kLocalDecisionRegisterDirectories.join(' ')}; do '
    '[ ! -d "\$register" ] || $command; done';

/// A missing-safe shell command that lists every local Markdown decision.
String localDecisionRegisterListCommand() => _forEachLocalDecisionRegister(
  r'''find "$register" -type f -name '*.md' -print''',
);

/// A missing-safe shell command that greps every local Markdown decision.
///
/// [keywordPattern] is the grep alternation rendered into a lens instruction.
String localDecisionRegisterGrepCommand(String keywordPattern) =>
    _forEachLocalDecisionRegister(
      'find "\$register" -type f -name \'*.md\' '
      '-exec grep -li "$keywordPattern" {} +',
    );
