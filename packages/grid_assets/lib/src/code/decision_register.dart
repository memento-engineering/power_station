library;

/// Local decision-register directories, in legacy-first order.
///
/// A substation may expose either directory or both during the migration.
const List<String> kLocalDecisionRegisterDirectories = [
  'docs/adr',
  'docs/decisions',
];

/// The register's WRITE rule — stated to every agent that could RECORD a
/// decision (the specify architect writes one; the spec critic grades it).
///
/// `docs/decisions/` is the write target and an entry BINDS ON WRITE, so there
/// is no advisory tier and no `A<n>` serial for concurrent worktrees to collide
/// on. The vended `decide` skill owns the entry SHAPE; this rule POINTS at that
/// contract rather than restating a second schema beside it.
const String kDecisionWriteRule =
    'A decision the design MAKES — or DEPARTS FROM — is RECORDED as a new '
    'slug entry under `docs/decisions/`, following the vended `decide` '
    'skill\'s contract (`.claude/skills/decide/SKILL.md`: front matter with '
    '`status`, `date`, `decision-makers`, and a `register` block carrying '
    '`spec: 1`, `surfaces`, and its edges). That skill is authoritative for '
    'the entry shape — follow it, never restate it. An entry BINDS ON WRITE: '
    'there is no advisory tier and no `A<n>` serial to collide on. '
    '`docs/adr/ADR-0000-ai-decision-register.md` is READ-ONLY LEGACY — cite '
    'it, NEVER append to it. When `docs/decisions/` does not exist in the '
    'substation, CREATE it with the entry; a missing directory is not a '
    'reason to fall back to ADR-0000.';

String _forEachLocalDecisionRegister(String command) =>
    'for register in ${kLocalDecisionRegisterDirectories.join(' ')}; do '
    '[ ! -d "\$register" ] || $command; done';

/// A missing-safe shell command that lists every local Markdown decision.
///
/// `-not -path '*/views/*'` drops the RENDERED views subtree
/// (`docs/decisions/views/NNNN-*.md`): those are generated projections of the
/// entries, not entries, and surfacing them double-counts every decision. A
/// path predicate rather than `-maxdepth`, because the format allows category
/// subdirectories under `docs/decisions/`.
String localDecisionRegisterListCommand() => _forEachLocalDecisionRegister(
  r'''find "$register" -type f -not -path '*/views/*' -name '*.md' -print''',
);

/// A missing-safe shell command that greps every local Markdown decision.
///
/// [keywordPattern] is the grep alternation rendered into a lens instruction.
/// Excludes the rendered views subtree for the same reason
/// [localDecisionRegisterListCommand] does.
String localDecisionRegisterGrepCommand(String keywordPattern) =>
    _forEachLocalDecisionRegister(
      'find "\$register" -type f -not -path \'*/views/*\' '
      '-name \'*.md\' '
      '-exec grep -li "$keywordPattern" {} +',
    );
