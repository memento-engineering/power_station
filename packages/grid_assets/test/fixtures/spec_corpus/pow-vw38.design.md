## Implementation Plan

**The bead's hypothesis is FALSIFIED; the measured root cause is different.** The
specify stage reproduced it in this worktree (power_station `ce4f3c6`, path-dep
linkage into `../the_grid`), and the finding is the brief for every step below:

- There is NO ambient-environment coupling. `grep -rn 'Platform.environment' packages/github_grid_assets/lib`
  returns exactly two hits — `lib/src/credentials.dart:94` (`platformEnvironment()`,
  the DEFAULT `EnvironmentReader`, which the test never uses because `_loader()`
  injects `environment: () => environment`) and `lib/src/intake/github_self_trust.dart:19`
  (reads only `GITHUB_USER`, and is not on the `GitHubAppClientAssets` path).
  `grep -rn 'GRID_GITHUB_APP_KEY' .` over the whole worktree returns NOTHING: no
  code in this repo can observe those two variables.
- The failure is a **wall-clock race**, and it fails with the variables UNSET too.
  Measured with both variables unset: 2 of 5 still fail. Measured with the file run
  alone, variables exported: 5 of 8 runs fail, 3 pass. Measured inside the full pack
  run: 3 of 5 cases fail on a cold cache, 0 on a warm one. The bead's `env -u` A/B
  was a coincidence of cache warmth, not causation.
- **The coupling site is `_FakeRead.call` at `packages/github_grid_assets/test/github_app_client_assets_test.dart:87`**,
  which is `return File(path).readAsString();` — a REAL asynchronous filesystem read
  BELOW a seam named "fake". The call path is:
  `_HostState.build` → `GitHubAppClientAssets.buildWithChild` (`lib/src/assets/github_app_client_assets.dart:65`)
  → `unawaited(_load(...))` → `seed.credentialLoader.resolve(privateKeyVar)`
  (`lib/src/credentials.dart:71`) → `await _read(path)` → `_FakeRead.call` → `dart:io`.
  The test's `_settle` (line 139) waits by pumping the event queue exactly 3 times,
  which advances event-loop TURNS while granting microseconds of wall clock — it
  cannot wait out an OS completion. When the read has not landed, `_client` is still
  null, `setState` has not run, and the assertions at lines 222/310/316 read the
  pre-load tree.
- **Proof:** replacing that one line with an in-memory map lookup turns the file green
  5 runs out of 5 with both variables still exported, and the whole pack green
  3 runs out of 3 (`+129 ~1: All tests passed!`).

This is exactly the class recorded in `power_station#a28-bead-pow-d26-the-acceptance-suite-flake-is-the-molecule`;
see `## ADR Alignment`. The plan removes the IO (root cause) AND targets the waits
at observables (A28's recorded primitive), then delivers the hermeticity hardening
the bead asked for on its own terms.

### Step 1 — Reproduce, and confirm the named site

From the repo root, with both key variables exported (the resident's environment):

```sh
cd packages/github_grid_assets
grep -rn 'Platform.environment' lib          # exactly 2 hits, both named above
grep -rn 'GRID_GITHUB_APP_KEY' ../.. | grep -v '^\.\./\.\./\.git/'   # NO hits
for i in $(seq 1 8); do dart test test/github_app_client_assets_test.dart 2>&1 | tail -1; done
```

Expected: the two greps confirm the finding above, and the loop mixes
`All tests passed!` with `Some tests failed.` — a flake, not a deterministic
environment coupling. Do not proceed to Step 2 until a mixed result is observed;
if all 8 runs pass, run the whole pack (`dart test`) instead, which loads the
machine enough to surface it.

No code changes in this step. Commit: none.

### Step 2 — Make `_FakeRead` a real Fake: no filesystem IO below the seam

In `packages/github_grid_assets/test/github_app_client_assets_test.dart`, hoist the
two fixture PEMs to a library-load synchronous read and serve them from memory.
Both fakes also start recording the paths they were asked for (Step 5 asserts on
them); `calls` becomes a derived getter so every existing `stat.calls`/`read.calls`
assertion keeps compiling unchanged.

Replace the `_FakeStat`/`_FakeRead` block (currently lines 72-89):

```dart
class _FakeStat {
  _FakeStat(this.values);
  final Map<String, GitHubKeyFileStat> values;

  /// Every path this fake was asked to stat, in order.
  final paths = <String>[];
  int get calls => paths.length;
  Future<GitHubKeyFileStat> call(String path) async {
    paths.add(path);
    return values[path] ??
        const GitHubKeyFileStat(type: FileSystemEntityType.notFound, mode: 0);
  }
}

/// The fixture PEMs, read ONCE at library load — never inside a settle window.
///
/// `_FakeRead` used to `await File(path).readAsString()`, putting a REAL
/// asynchronous filesystem hop BELOW the fake seam. A pump-only wait advances
/// event-loop turns and cannot wait out an OS completion, so the asset's
/// `_load` had frequently not landed when the assertions ran (bead `pow-vw38`).
final _pems = <String, String>{
  _onePath: File(_onePath).readAsStringSync(),
  _twoPath: File(_twoPath).readAsStringSync(),
};

class _FakeRead {
  /// Every path this fake was asked to read, in order.
  final paths = <String>[];
  int get calls => paths.length;
  Future<String> call(String path) async {
    paths.add(path);
    return _pems[path] ?? (throw StateError('no fixture PEM for $path'));
  }
}
```

The unknown-path branch throws rather than returning a sentinel — a guard is LOUD
or GONE, and a fake asked for a path the test never staged is a test bug.

Test: `cd packages/github_grid_assets && dart test test/github_app_client_assets_test.dart` → expect
`All tests passed!` (5 of 5, with the key variables still exported).
Commit: `fix(test): serve the fixture PEMs from memory, not the filesystem (pow-vw38)`

### Step 3 — Wait through the shared bounded `settle`, not a fixed 3-pump loop

`packages/github_grid_assets/test/support/asset_fakes.dart:539` already vends this
pack's bounded wait — the primitive A28 introduced, which grants a REAL 1ms slice
per unsatisfied round. Consume it instead of keeping a fourth private pump loop.

Add the import to `packages/github_grid_assets/test/github_app_client_assets_test.dart`,
after the `package:test/test.dart` line:

```dart
import 'support/asset_fakes.dart';
```

Replace the private `_settle` (currently lines 139-144):

```dart
/// Drives [owner] until [reached] holds, or the shared bounded budget is spent.
///
/// Delegates to `settle` (`test/support/asset_fakes.dart`) so every round both
/// drains the event queue AND yields a real wall-clock slice. Omit [reached] for
/// the RETENTION cases, which have no arrival to target and want the full quiet
/// window instead.
Future<void> _settle(TreeOwner owner, [bool Function()? reached]) =>
    settle(() {
      owner.flush();
      return reached?.call() ?? false;
    });
```

`owner.flush()` runs inside the condition because the tree only reconciles a
`setState` on a flush; putting it there means every round both advances the tree
and re-reads the observable, exactly once per round.

`pumpEventQueue` stays imported and used by the `missing file and wrong mode` case
(line 255), which deliberately does not settle — it asserts `owner.flush` throws.

Test: `cd packages/github_grid_assets && dart test test/github_app_client_assets_test.dart` → expect
`All tests passed!` (5 of 5).
Commit: `refactor(test): wait through the shared bounded settle (pow-vw38)`

### Step 4 — Target every positive wait at its observable

Still in `packages/github_grid_assets/test/github_app_client_assets_test.dart`,
give each `_settle` call the thing it is waiting for. Five edits, all one-liners:

```dart
// '0600 PEM provides a client…' (was line 221)
await _settle(owner, () => observed != null);

// 'config or resolved path change replaces…' (was lines 305, 314, 320)
await _settle(owner, () => observations.last != null);
await _settle(owner, () => factories == 2);
await _settle(owner, () => factories == 3);

// 'sibling variable names load distinct keys…' (was line 371)
await _settle(owner, () => one != null && two != null);
```

The two remaining bare `_settle(owner)` calls stay bare on purpose: line 188
(`unset and blank variables provide no client`) and the mid-test retention wait at
line 309 (`host.swap` to the SAME identity) both assert that nothing arrives, so
there is no observable to target and the full budget is the wait.

Test: `cd packages/github_grid_assets && for i in $(seq 1 20); do dart test test/github_app_client_assets_test.dart 2>&1 | tail -1; done`
→ expect 20 lines of `+5: All tests passed!`.
Commit: `test(github-app): target each wait at the observable it awaits (pow-vw38)`

### Step 5 — Pin the hostile-ambient case

Append a sixth case inside the `GitHubAppClientAssets` group in
`packages/github_grid_assets/test/github_app_client_assets_test.dart`. It injects an
environment that ALSO carries both real operator variable names pointing at paths
that do not exist, and proves the resolved identity comes from the fixture variable
alone — the stat and read fakes are asked for `_onePath` and nothing else:

```dart
    test(
      'a hostile ambient GRID_GITHUB_APP_KEY_* entry never reaches the '
      'resolved identity — only the injected fixture variables do',
      () async {
        final stat = _FakeStat(const {
          _onePath: GitHubKeyFileStat(
            type: FileSystemEntityType.file,
            mode: 0x180,
          ),
        });
        final read = _FakeRead();
        final transport = _FakeTransport();
        GitHubAppClient? observed;
        final owner = TreeOwner();
        addTearDown(owner.dispose);
        owner.mountRoot(
          sdk.ProviderScope(
            child: _assets(
              config: _config('one'),
              privateKeyVar: _oneVar,
              loader: _loader(const {
                _oneVar: _onePath,
                'GRID_GITHUB_APP_KEY_MEMENTO': '/hostile/memento.pem',
                'GRID_GITHUB_APP_KEY_NICHOLAS': '/hostile/nicholas.pem',
              }, stat, read),
              transportFactory: () => transport,
              observe: (value) => observed = value,
            ),
          ),
        );
        owner.flush();
        await _settle(owner, () => observed != null);
        expect(stat.paths, [_onePath]);
        expect(read.paths, [_onePath]);
        await _send(observed!);
        _verify(transport, _onePublicKey);
      },
    );
```

Test: `cd packages/github_grid_assets && dart test test/github_app_client_assets_test.dart` → expect
`All tests passed!` (6 of 6).
Commit: `test(github-app): pin fixture-only identity against a hostile ambient key (pow-vw38)`

### Step 6 — Route `GitHubSelfTrust.fromEnvironment` through `EnvironmentReader`

`lib/src/intake/github_self_trust.dart:19` is the pack's one remaining
`?? Platform.environment` silent fallback. Make it the same injectable seam
`GitHubAppCredentialLoader` already uses, so `lib/src/credentials.dart` becomes the
single sanctioned site the Step 7 fence pins. Rewrite the head of
`packages/github_grid_assets/lib/src/intake/github_self_trust.dart` — the `dart:io`
import is replaced by the credentials import, since `Platform` is the only thing it
was there for:

```dart
import 'package:grid_engine/grid_engine.dart';

import '../credentials.dart';
```

and the factory:

```dart
  /// Creates trust from `GITHUB_USER`; absence is refused loudly.
  ///
  /// [environment] is the injectable [EnvironmentReader] seam — it defaults to
  /// [platformEnvironment] so production reads the process environment, and a
  /// test injects its own map instead of depending on what the operator
  /// exported.
  factory GitHubSelfTrust.fromEnvironment({
    EnvironmentReader environment = platformEnvironment,
  }) {
    final value = environment()['GITHUB_USER'];
    if (value == null) {
      throw StateError('GITHUB_USER is required for GitHub intake');
    }
    return GitHubSelfTrust(githubUser: value);
  }
```

`EnvironmentReader` and `platformEnvironment` are already public (the barrel
`lib/github_grid_assets.dart` exports `src/credentials.dart`), so no export changes.
`grep -rn 'fromEnvironment' packages --include='*.dart'` shows the only call sites
are the three in `packages/github_grid_assets/test/intake/github_self_trust_test.dart`
(lines 31, 39, 44) — migrate each to pass a closure:

```dart
      final fromEnvironment = GitHubSelfTrust.fromEnvironment(
        environment: () => const {'GITHUB_USER': 'nico'},
      );
```

```dart
      expect(
        () => GitHubSelfTrust.fromEnvironment(environment: () => const {}),
        throwsStateError,
      );
      for (final value in ['', '  ']) {
        expect(
          () => GitHubSelfTrust.fromEnvironment(
            environment: () => {'GITHUB_USER': value},
          ),
          throwsArgumentError,
        );
      }
```

Test: `cd packages/github_grid_assets && dart test test/intake/github_self_trust_test.dart` → expect
`All tests passed!` (3 of 3).
Commit: `refactor(intake)!: GitHubSelfTrust.fromEnvironment takes an EnvironmentReader (pow-vw38)`

### Step 7 — Fence the process environment behind the one sanctioned read

Create `packages/github_grid_assets/test/environment_fence_test.dart`. It extends the
pack-family's existing source-fence idiom (`packages/grid_assets/test/readiness_test.dart:184-200`
greps its own `lib/` the same way for a forbidden symbol) rather than inventing a
second style:

```dart
import 'dart:io';

import 'package:test/test.dart';

/// The ONE file allowed to touch the process environment directly: it defines
/// `platformEnvironment()`, the default `EnvironmentReader` every other
/// production read is injected with.
const _sanctioned = 'lib/src/credentials.dart';

void main() {
  test(
    'exactly one lib file reads Platform.environment — every other production '
    'read takes an injectable EnvironmentReader (bead pow-vw38)',
    () {
      final offenders = <String>[];
      var sanctionedHits = 0;
      for (final file in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        final hits = 'Platform.environment'
            .allMatches(file.readAsStringSync())
            .length;
        if (hits == 0) continue;
        if (file.path == _sanctioned) {
          sanctionedHits = hits;
        } else {
          offenders.add(file.path);
        }
      }
      expect(
        offenders,
        isEmpty,
        reason:
            'take an EnvironmentReader (lib/src/credentials.dart) and default '
            'it to platformEnvironment() instead of reading the process '
            'environment here',
      );
      expect(
        sanctionedHits,
        1,
        reason: '$_sanctioned defines platformEnvironment() exactly once',
      );
    },
  );
}
```

Then prove the fence is LOUD rather than decorative:

```sh
cd packages/github_grid_assets
cp lib/src/http_transport.dart /tmp/ht.bak
printf "\n// ignore: unused_element\nString _probe() => Platform.environment['X'] ?? '';\n" >> lib/src/http_transport.dart
dart test test/environment_fence_test.dart   # expect: Some tests failed.
cp /tmp/ht.bak lib/src/http_transport.dart && rm /tmp/ht.bak
dart test test/environment_fence_test.dart   # expect: All tests passed!
```

Test: `cd packages/github_grid_assets && dart test test/environment_fence_test.dart` → expect
`All tests passed!` (1 of 1), and the injected-violation run above expects
`Some tests failed.`.
Commit: `test(env): fence Platform.environment behind the one sanctioned read (pow-vw38)`

### Step 8 — Record the root-cause correction as a decision entry

The bead's stated cause (an ambient-environment coupling) is falsified and the fix
lands somewhere else, so the call is RECORDED — per the vended `decide` skill
(`/Users/nico/development/engineering.memento/decisions/skills/decide/SKILL.md`,
also vendored at `~/.pub-cache/git/decisions-*/skills/decide/SKILL.md`), which is
authoritative for the entry shape. Reserve the slug first, from the repo root:

```sh
decision_slug='github-app-assets-flake-is-real-io-below-the-fake-read'
decision_date="$(date +%F)"
decision_file="docs/decisions/${decision_date}-${decision_slug}.md"
test -d docs/decisions
grep -rn --include='*.md' "^[[:space:]]*slug:[[:space:]]*${decision_slug}[[:space:]]*$" docs/decisions; test -e "$decision_file" && exit 1
```

Expect no slug hit and no existing file. Then create that file with this content
(`bead: pow-vw38` follows the register's house practice of naming the WORK bead —
see `docs/decisions/2026-09-02-captured-process-output-escalates-tail-first.md`;
`obsoletes`/`updates` stay empty because A28 is CITED and remains in force
unamended, and the `decide` skill forbids inventing an edge):

```markdown
---
status: accepted
date: <the decision_date computed above>
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: github-app-assets-flake-is-real-io-below-the-fake-read
  surfaces:
    - "packages/github_grid_assets/test/github_app_client_assets_test.dart"
    - "packages/github_grid_assets/test/environment_fence_test.dart"
    - "packages/github_grid_assets/lib/src/intake/github_self_trust.dart"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: pow-vw38
  legacy-id: null
---

# The github_grid_assets asset-test flake is REAL filesystem IO below the `_FakeRead` seam, not an ambient-environment coupling

## Context and Problem Statement

`github_app_client_assets_test.dart` failed intermittently on the operator's box
and green on CI, and bead `pow-vw38` recorded the cause as a coupling to the
exported `GRID_GITHUB_APP_KEY_*` variables. That is falsified: no file in this
repository reads those names, the pack's whole `lib/` touched
`Platform.environment` in only two places (neither on the asset's path), and the
same file failed 2 of 5 with both variables UNSET. The real defect is that
`_FakeRead.call` awaited `File(path).readAsString()` — a real OS completion below
a seam named "fake" — while the test's private `_settle` waited by pumping the
event queue three times.

## Decision Outcome

A FAKE performs no IO. `_FakeRead` serves the fixture PEMs from a map read
synchronously at library load, and every wait in the file goes through the shared
bounded `settle` (`test/support/asset_fakes.dart`), targeted at the observable it
awaits. The hermeticity hardening the bead asked for is kept on its own merits
rather than as the cure: `GitHubSelfTrust.fromEnvironment` takes the same
injectable `EnvironmentReader` the credential loader has, leaving
`lib/src/credentials.dart` as the ONE sanctioned process-environment read, and
`test/environment_fence_test.dart` fails loudly on any new one.

This is the same failure class as
`power_station#a28-bead-pow-d26-the-acceptance-suite-flake-is-the-molecule`, which
remains in force unamended: there, real IO sat below a fake `BdRunner` in a
PRODUCTION write path and the wait was fixed; here the IO is in the TEST DOUBLE
itself, so the IO is removed as well as the wait repaired.

### Consequences

* Good, because the pack is green under any ambient environment and any cache
  warmth, so a `github_grid_assets` bead no longer needs a governor hand-harvest.
* Good, because the fence turns a silent regression (a new
  `?? Platform.environment` fallback) into a failing test.
* Bad, because the fixture PEMs are now read eagerly at library load even for the
  cases that never resolve a key — a few microseconds paid by every run of the file.

### Confirmation

`cd packages/github_grid_assets && dart test` is green with
`GRID_GITHUB_APP_KEY_MEMENTO` and `GRID_GITHUB_APP_KEY_NICHOLAS` exported, over 20
consecutive runs of the file and 3 of the whole pack.
```

Test: `test -f "docs/decisions/$(date +%F)-github-app-assets-flake-is-real-io-below-the-fake-read.md" && echo OK` → expect `OK`.
Commit: `docs(decisions): record the fake-seam root cause for the asset-test flake (pow-vw38)`

### Step 9 — Run the house gate in the armed environment

```sh
cd packages/github_grid_assets && dart pub get && dart analyze && dart test
```

Expected: `No issues found!` from analyze and `All tests passed!` from test
(129 passing, 1 skipped) — run WITHOUT unsetting anything, so the armed
environment is itself the proof.
Commit: none (gate only).

## Touches

- `packages/github_grid_assets/test/github_app_client_assets_test.dart` — modified;
  adds the `import 'support/asset_fakes.dart';`, the library-private `_pems` fixture
  map, `_FakeStat.paths`/`_FakeRead.paths` (with `calls` demoted to a derived
  getter), the optional-condition `_settle(TreeOwner, [bool Function()?])`, and the
  sixth `hostile ambient` case. `_FakeRead.call` no longer touches `dart:io`
  asynchronously. All identifiers here are file-private — no public symbol added.
- `packages/github_grid_assets/test/environment_fence_test.dart` — CREATED; one test,
  no exported symbol (`_sanctioned` is file-private).
- `packages/github_grid_assets/lib/src/intake/github_self_trust.dart` — modified;
  `lib/src/intake/github_self_trust.dart:GitHubSelfTrust.fromEnvironment` CHANGES
  SIGNATURE from `{Map<String, String>? environment}` to
  `{EnvironmentReader environment = platformEnvironment}`; the `dart:io` import is
  replaced by `import '../credentials.dart';`. `GitHubSelfTrust`, its unnamed
  constructor, `.githubUser` and `.levelOf` are byte-unchanged.
- `packages/github_grid_assets/test/intake/github_self_trust_test.dart` — modified;
  the three `fromEnvironment` call sites (lines 31, 39, 44) pass a closure.
- `docs/decisions/<YYYY-MM-DD>-github-app-assets-flake-is-real-io-below-the-fake-read.md`
  — CREATED (Step 8).
- Consumed, NOT modified: `packages/github_grid_assets/test/support/asset_fakes.dart:settle`
  (the shared bounded wait, reused rather than re-expressed) and
  `packages/github_grid_assets/lib/src/credentials.dart:EnvironmentReader` /
  `:platformEnvironment` (the existing injectable seam, extended to a second
  consumer rather than duplicated).

Re-validated against the live tree at `ce4f3c6`: the whole plan was prototyped in
this worktree and reverted — the file goes 5/8-flaky to 20/20 green and the pack to
`+129 ~1: All tests passed!` three runs running with both key variables exported,
`dart analyze` clean; `grep -rn 'GitHubSelfTrust' packages --include='*.dart'` shows
`fromEnvironment`'s only callers are the three migrated test lines (the four other
hits construct `GitHubSelfTrust(githubUser: …)` directly and are untouched);
`grep -rn 'settle' packages/github_grid_assets/test` shows the shared helper's other
consumers pass their own conditions and are unaffected; `bd dep list pow-vw38`
reports no dependencies, and the nearest neighbours found by `bd search github_grid_assets`
(`pow-1rn` epic, `pow-oe97`, `pow-1rn.6`) touch only `lib/src/github/**` and the
intake stores — no overlap with any file above, so no dependency edge is needed.

## ADR Alignment

Verified via grep on `settle`, `pumpEventQueue`, `hermetic`, `Platform.environment`,
`EnvironmentReader`, `flake`, `fake`, `filesystem` over both registers
(`docs/adr/` and `docs/decisions/`).

- **`power_station#a28-bead-pow-d26-the-acceptance-suite-flake-is-the-molecule`**
  (`docs/decisions/2026-07-21-a28-bead-pow-d26-the-acceptance-suite-flake-is-the-molecule.md`,
  `status: accepted`, legacy id `A28`, surfaces `packages/**` — so it governs this
  file). LOAD-BEARING. It rules: *"`pumpEventQueue` advances event-loop TURNS while
  granting microseconds of wall clock — it cannot wait out an OS completion, and to a
  plateau-based fixed-point wrapper an in-flight filesystem call is indistinguishable
  from quiescence. That is why raising `maxPumps` 20→1000 and `stableRounds` 50→250
  never moved the rate."* The plan IMPLEMENTS it: Step 3 deletes the 3-round pump-only
  `_settle` and routes the file through the very helper A28 introduced
  (`test/support/asset_fakes.dart:539`), and Step 4 makes every positive wait
  observable-targeted, which is A28's own restatement of A27(7)(b) (*"all three waits
  made observable-targeted"*). The plan also EXTENDS A28 by name, in a direction A28
  did not rule on: A28 held that *"real filesystem IO in a production write path is
  legitimate; what was wrong is the harness's model of what a WAIT is"* — that
  legitimacy does not reach a TEST DOUBLE, so Step 2 additionally REMOVES the IO from
  `_FakeRead`. Step 8 records that extension as its own entry rather than amending
  A28, which remains in force.
- **`docs/adr/ADR-0002-agent-environment-layer.md` D3.** Cited and DISTINGUISHED. Its
  load-bearing clause is *"An environment whose machine fact is UNBOUND on this box
  REFUSES AT BOOT — loud, never a silent default."* Its literal subject is the named
  INFERENCE environments (harness/target/model) and their machine-local site binding,
  not POSIX process variables, so it does not govern `EnvironmentReader`. Its posture
  is nevertheless honoured rather than contradicted: Steps 6 and 7 remove the pack's
  one `?? Platform.environment` silent fallback and make a new one fail loudly.
- **`docs/adr/ADR-0006-typed-environment-lookup-selects-by-value.md`.** Grepped
  (matches on the word "environment") and NOT applicable: it governs typed
  `AgentEnvironment` lookup through `TreeContext`, and this bead adds no tree lookup
  and changes no capability's environment resolution.
- **House set (`CLAUDE.md` Conventions).** *"**Fakes, not mocks**; pure logic tested
  before IO is wired"* — Step 2 is the direct application: a fake that performs real
  IO is not a fake. *"Guards LOUD or GONE"* (ADR-0008 doctrine as restated in
  `CLAUDE.md`) — the unknown-path branch in `_FakeRead` throws, and the Step 7 fence
  is proven to fail on an injected violation rather than being trusted.
- The D-H `genesis_tree` doctrine is untouched: no production seed, `build`, or
  `StateNotifier` changes. `GitHubAppClientAssets` already watches its deps in
  `buildWithChild` and takes its `credentialLoader` by DI, which is why the injected
  reader was never the problem.
- `docs/adr/ADR-0000-ai-decision-register.md` is READ-ONLY legacy and is NOT appended
  to; the new decision goes to `docs/decisions/` per Step 8.

## Validation Plan

- [ ] With both key variables exported to arbitrary 0600 files, the whole pack suite is green → `M=$(mktemp) N=$(mktemp); chmod 600 $M $N; cd packages/github_grid_assets && GRID_GITHUB_APP_KEY_MEMENTO=$M GRID_GITHUB_APP_KEY_NICHOLAS=$N dart test` → `All tests passed!` (129 passing, 1 skipped)
- [ ] The flake is GONE under repetition → `cd packages/github_grid_assets && for i in $(seq 1 20); do dart test test/github_app_client_assets_test.dart 2>&1 | tail -1; done` → 20 lines of `+6: All tests passed!`
- [ ] No awaited filesystem read survives below the fake seam → `cd packages/github_grid_assets && grep -n 'readAsString()' test/github_app_client_assets_test.dart` → no output (exit 1)
- [ ] The fixed 3-round pump wait is gone and the file waits through the shared helper → `cd packages/github_grid_assets && grep -c 'for (var i = 0; i < 3; i++)' test/github_app_client_assets_test.dart && grep -c "import 'support/asset_fakes.dart';" test/github_app_client_assets_test.dart` → `0` then `1`
- [ ] A hostile ambient `GRID_GITHUB_APP_KEY_*` entry never reaches the resolved identity → `cd packages/github_grid_assets && dart test test/github_app_client_assets_test.dart -N 'hostile ambient'` → `All tests passed!` (1 of 1 selected)
- [ ] `lib/` reads `Platform.environment` in exactly one file → `cd packages/github_grid_assets && dart test test/environment_fence_test.dart && grep -rn 'Platform.environment' lib` → `All tests passed!`, then one hit at `lib/src/credentials.dart:94`
- [ ] The fence is LOUD, not decorative → `cd packages/github_grid_assets && cp lib/src/http_transport.dart /tmp/ht.bak && printf "\nString _probe() => Platform.environment['X'] ?? '';\n" >> lib/src/http_transport.dart && dart test test/environment_fence_test.dart; cp /tmp/ht.bak lib/src/http_transport.dart` → `Some tests failed.` on the injected run, `All tests passed!` after the restore
- [ ] `GitHubSelfTrust.fromEnvironment` takes an injectable `EnvironmentReader` with its three call sites migrated → `cd packages/github_grid_assets && dart test test/intake/github_self_trust_test.dart` → `All tests passed!` (3 of 3)
- [ ] The root-cause correction is RECORDED as a decision entry → `test -f "docs/decisions/$(date +%F)-github-app-assets-flake-is-real-io-below-the-fake-read.md" && echo OK` → `OK`
- [ ] House gate green → `cd packages/github_grid_assets && dart pub get && dart analyze && dart test` → `No issues found!` and `All tests passed!`, exit 0