// The SEARCH domain (bead `pow-ovh`) — the lib service under the station's
// `search` Command (the coupled skill+command pattern's deterministic
// substrate). Offline throughout: the per-store read is a fake source, store
// existence a fake probe, roster enumeration a bare offline tree mount
// (Fakes, not mocks).
import 'package:beads_dart/beads_dart.dart'
    show Bead, BdResult, BdRunner, BeadStatus, IssueType;
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_assets/grid_assets.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:grid_sdk/grid_sdk.dart' as sdk;
import 'package:test/test.dart';

/// A station delegate authored the space-6ds way: literal Substation seats in
/// the tree (with a conditional third seat, proving coverage is ROSTER-driven
/// — the tree changes, the search set changes; nothing here is a config list
/// handed to the search).
class _StationDelegate extends sdk.GridDelegate {
  _StationDelegate({this.withGamma = false});

  final bool withGamma;
  var disposed = false;

  @override
  Seed build(TreeContext context, sdk.GridConfiguration configuration) =>
      sdk.RawAssetGrid(
        root: '/grid/home',
        assets: [
          sdk.Station(
            name: 'test-station',
            assets: [
              sdk.Substations(
                substations: [
                  // A GridRoot-relative root, resolved at mount (tg-32r).
                  sdk.Substation('alpha', '../alpha', prefix: 'al'),
                  sdk.Substation('beta', '/work/beta'),
                  if (withGamma) sdk.Substation('gamma', '/work/gamma'),
                ],
              ),
            ],
          ),
        ],
      );

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}

class _ThrowingDelegate extends sdk.GridDelegate {
  var disposed = false;

  @override
  Seed build(TreeContext context, sdk.GridConfiguration configuration) =>
      throw StateError('mount failed');

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}

/// The programmable per-store read (the read-only seam): beads by store root,
/// with per-root failure injection and a read log.
class _FakeBeadSource implements SubstationBeadSource {
  _FakeBeadSource(this.byRoot, {this.failRoots = const {}});

  final Map<String, List<Bead>> byRoot;
  final Set<String> failRoots;
  final List<String> reads = [];

  @override
  Future<List<Bead>> read(sdk.SubstationScope scope) async {
    reads.add(scope.root);
    if (failRoots.contains(scope.root)) {
      throw StateError('bd unavailable for ${scope.root}');
    }
    return byRoot[scope.root] ?? const [];
  }
}

/// Records every argv the default source spawns and answers with canned JSONL
/// — the A37 fence's witness.
class _RecordingBdRunner implements BdRunner {
  _RecordingBdRunner(this.jsonl);

  final String jsonl;
  final List<List<String>> argvs = [];

  @override
  Future<BdResult> run(
    List<String> args, {
    Duration? timeout,
    String? stdin,
  }) async {
    argvs.add(args);
    return BdResult(exitCode: 0, stdout: jsonl, stderr: '');
  }
}

sdk.SubstationScope _scope(String name, String root, [String? prefix]) =>
    sdk.SubstationScope(name: name, root: root, prefix: prefix ?? name);

/// A probe that says every listed store exists.
sdk.DirectoryProbe _probeFor(Set<String> beadsDirs) => beadsDirs.contains;

void main() {
  group('mountedRosterOf — the roster from the resident-station context', () {
    test('enumerates the mounted Substation seats in tree order, roots '
        'resolved against the grid home, prefixes carried', () {
      final delegate = _StationDelegate();
      addTearDown(delegate.dispose);
      final roster = mountedRosterOf(delegate);
      expect(roster.map((s) => s.name), ['alpha', 'beta']);
      expect(
        {for (final s in roster) s.name: s.root},
        {'alpha': '/grid/alpha', 'beta': '/work/beta'},
      );
      expect(
        {for (final s in roster) s.name: s.prefix},
        {'alpha': 'al', 'beta': 'beta'},
      );
    });

    test('a seat added to the tree appears in the roster — coverage follows '
        'the authored tree, never a hardcoded list', () {
      final delegate = _StationDelegate(withGamma: true);
      addTearDown(delegate.dispose);
      expect(mountedRosterOf(delegate).map((s) => s.name), [
        'alpha',
        'beta',
        'gamma',
      ]);
    });

    test('codedRosterOf constructs, enumerates, and disposes its delegate', () {
      late _StationDelegate delegate;

      final roster = codedRosterOf(() => delegate = _StationDelegate());

      expect(roster.map((scope) => scope.name), ['alpha', 'beta']);
      expect(delegate.disposed, isTrue);
    });

    test(
      'codedRosterOf disposes its delegate when the offline mount throws',
      () {
        late _ThrowingDelegate delegate;

        expect(
          () => codedRosterOf(() => delegate = _ThrowingDelegate()),
          throwsStateError,
        );
        expect(delegate.disposed, isTrue);
      },
    );
  });

  group('StationSearchService.search', () {
    final alphaBeads = [
      const Bead(
        id: 'al-2',
        title: 'Wire the flux capacitor',
        description: 'The capacitor needs wiring into the time circuits.',
        status: BeadStatus.open,
      ),
      const Bead(
        id: 'al-1',
        title: 'Decide the wiring standard',
        closeReason: 'ratified: soldered flux joints',
        status: BeadStatus.closed,
        issueType: IssueType.decision,
      ),
      // Lifecycle noise a discovery search must not surface.
      const Bead(
        id: 'al-9',
        title: 'flux session lifecycle bead',
        issueType: GridIssueTypes.session,
      ),
    ];
    final betaBeads = [
      const Bead(
        id: 'beta-1',
        title: 'Unrelated chore',
        notes: 'mentions FLUX once, in notes',
        issueType: IssueType.chore,
      ),
    ];

    StationSearchService service(
      _FakeBeadSource source, {
      Set<String>? existing,
    }) => StationSearchService(
      source: source,
      dirExists: _probeFor(
        existing ?? {'/roots/alpha/.beads', '/roots/beta/.beads'},
      ),
    );

    final roster = [
      _scope('alpha', '/roots/alpha', 'al'),
      _scope('beta', '/roots/beta'),
    ];

    test('returns structured hits across ALL roster stores, in roster order, '
        'with store/status/type/field/snippet on every hit', () async {
      final source = _FakeBeadSource({
        '/roots/alpha': alphaBeads,
        '/roots/beta': betaBeads,
      });
      final report = await service(
        source,
      ).search(query: 'flux', roster: roster, gridHome: '/grid/home');

      expect(source.reads, ['/roots/alpha', '/roots/beta']);
      expect(report.stores.map((s) => s.store.name), ['alpha', 'beta']);

      final alpha = report.stores.first as StoreSearched;
      // Deterministic: bead-id order within the store; the session-typed bead
      // is excluded (core types only), so 2 searchable beads, both hits.
      expect(alpha.beadsSearched, 2);
      expect(alpha.hits.map((h) => h.beadId), ['al-1', 'al-2']);

      final decision = alpha.hits.first;
      expect(decision.store, 'alpha');
      expect(decision.status, 'closed');
      expect(decision.issueType, 'decision');
      expect(decision.field, 'close_reason');
      expect(decision.snippet, contains('soldered flux joints'));

      final beta = report.stores.last as StoreSearched;
      expect(beta.hits.single.field, 'notes');
      expect(report.hits.map((h) => h.beadId), ['al-1', 'al-2', 'beta-1']);
    });

    test('matching is case-insensitive and field precedence names the FIRST '
        'matching field (title before notes)', () async {
      final source = _FakeBeadSource({
        '/roots/alpha': const [
          Bead(id: 'al-3', title: 'Flux everywhere', notes: 'flux here too'),
        ],
        '/roots/beta': const [],
      });
      final report = await service(
        source,
      ).search(query: 'FLUX', roster: roster, gridHome: '/grid/home');
      final hit = report.hits.single;
      expect(hit.field, 'title');
      expect(hit.snippet, 'Flux everywhere');
    });

    test('multi-word queries OR case-insensitive substring terms across fields '
        'without requiring the literal phrase', () async {
      final source = _FakeBeadSource({
        '/roots/alpha': const [
          Bead(
            id: 'al-6',
            title: 'Telemetry pipeline',
            description: 'observability is also discussed here',
          ),
          Bead(id: 'al-4', title: 'Instrument the service with OTel'),
          Bead(
            id: 'al-5',
            title: 'Exporter work',
            notes:
                'telemetry marker padding padding padding padding padding '
                'padding padding padding padding padding padding padding '
                'padding padding padding padding padding padding padding '
                'padding padding padding padding padding observability marker',
          ),
          Bead(id: 'al-7', title: 'Unrelated backlog work'),
          Bead(
            id: 'al-8',
            title: 'Observability session',
            issueType: GridIssueTypes.session,
          ),
        ],
        '/roots/beta': const [],
      });

      final report = await service(source).search(
        query: '  OBSERVABILITY   telemetry otel  ',
        roster: roster,
        gridHome: '/grid/home',
      );

      expect(report.hits.map((hit) => hit.beadId), ['al-4', 'al-5', 'al-6']);
      expect(report.hits.map((hit) => hit.field), ['title', 'notes', 'title']);
      expect(report.hits[1].snippet, contains('telemetry marker'));
      expect(report.hits[1].snippet, isNot(contains('observability marker')));
      expect(report.hits[2].snippet, 'Telemetry pipeline');
      expect((report.stores.first as StoreSearched).beadsSearched, 4);
    });

    test('closed beads are searchable (decisions live closed) — status rides '
        'the hit so consumers filter', () async {
      final source = _FakeBeadSource({
        '/roots/alpha': alphaBeads,
        '/roots/beta': const [],
      });
      final report = await service(
        source,
      ).search(query: 'standard', roster: roster, gridHome: '/grid/home');
      expect(report.hits.single.status, 'closed');
    });

    test('a long matched line is windowed around the match with ellipses; a '
        'multi-line field snips the matching LINE', () async {
      final longTail = List.filled(60, 'padding').join(' ');
      final source = _FakeBeadSource({
        '/roots/alpha': [
          Bead(
            id: 'al-4',
            title: 'windowing',
            description: 'first line\n$longTail NEEDLE $longTail\nlast line',
          ),
        ],
        '/roots/beta': const [],
      });
      final report = await service(
        source,
      ).search(query: 'needle', roster: roster, gridHome: '/grid/home');
      final snippet = report.hits.single.snippet;
      expect(snippet, contains('NEEDLE'));
      expect(snippet, startsWith('…'));
      expect(snippet, endsWith('…'));
      expect(snippet, isNot(contains('\n')));
      expect(snippet.length, lessThanOrEqualTo(170));
    });

    test('an absent store is a loud StoreAbsent IN the report — the rest of '
        'the roster is still searched (skip-loud, mirroring arming)', () async {
      final source = _FakeBeadSource({'/roots/beta': betaBeads});
      final report = await service(
        source,
        existing: {'/roots/beta/.beads'}, // alpha's .beads/ missing
      ).search(query: 'flux', roster: roster, gridHome: '/grid/home');

      final alpha = report.stores.first;
      expect(alpha, isA<StoreAbsent>());
      expect((alpha as StoreAbsent).reason, contains('/roots/alpha/.beads'));
      // alpha was never read (no store, no spawn), beta still searched.
      expect(source.reads, ['/roots/beta']);
      expect(report.stores.last, isA<StoreSearched>());
      expect(report.searchedAnyStore, isTrue);
    });

    test('a failing store read is a StoreFailed IN the report — per-store '
        'isolation, never masking the other seats', () async {
      final source = _FakeBeadSource(
        {'/roots/beta': betaBeads},
        failRoots: {'/roots/alpha'},
      );
      final report = await service(
        source,
      ).search(query: 'flux', roster: roster, gridHome: '/grid/home');
      final alpha = report.stores.first;
      expect(alpha, isA<StoreFailed>());
      expect((alpha as StoreFailed).reason, contains('bd unavailable'));
      expect(report.stores.last, isA<StoreSearched>());
    });

    test('an empty query is a LOUD ArgumentError (a search has a query — '
        'never an everything-matches scan)', () {
      final source = _FakeBeadSource(const {});
      expect(
        () => service(
          source,
        ).search(query: '   ', roster: roster, gridHome: '/grid/home'),
        throwsArgumentError,
      );
    });

    test('the report JSON carries the documented contract: query, per-store '
        'outcome envelopes, hitCount', () async {
      final source = _FakeBeadSource(
        {'/roots/beta': betaBeads},
        failRoots: {'/roots/alpha'},
      );
      final json = (await service(
        source,
      ).search(query: 'flux', roster: roster, gridHome: '/grid/home')).toJson();

      expect(json['query'], 'flux');
      expect(json['hitCount'], 1);
      final stores = json['stores'] as List;
      expect(stores, hasLength(2));
      expect(
        (stores.first as Map)['outcome'],
        'failed',
        reason: 'alpha failed',
      );
      final beta = stores.last as Map;
      expect(beta['substation'], 'beta');
      expect(beta['prefix'], 'beta');
      expect(beta['root'], '/roots/beta');
      expect(beta['outcome'], 'searched');
      expect(beta['beadsSearched'], 1);
      final hit = (beta['hits'] as List).single as Map;
      expect(hit['id'], 'beta-1');
      expect(hit['store'], 'beta');
      expect(hit['status'], 'open');
      expect(hit['type'], 'chore');
      expect(hit['field'], 'notes');
      expect(hit['snippet'], contains('FLUX'));
    });

    test('end-to-end offline: the roster FROM the delegate drives the search '
        '— a seat in the tree is a store in the report', () async {
      final delegate = _StationDelegate(withGamma: true);
      addTearDown(delegate.dispose);
      final roster = mountedRosterOf(delegate);
      final source = _FakeBeadSource({
        '/grid/alpha': const [Bead(id: 'al-7', title: 'roster driven')],
      });
      final report = await StationSearchService(
        source: source,
        dirExists: _probeFor({'/grid/alpha/.beads'}),
      ).search(query: 'roster', roster: roster, gridHome: '/grid/home');

      expect(report.stores.map((s) => s.store.name), [
        'alpha',
        'beta',
        'gamma',
      ]);
      expect(report.hits.single.beadId, 'al-7');
      // The seats without a checkout are absent — reported, not dropped.
      expect(report.stores.whereType<StoreAbsent>(), hasLength(2));
    });
  });

  group('BdExportBeadSource — the A37 read-only fence (at the spawn seam)', () {
    // tg-w478 retired `bd export` (JSONL) in favour of `bd query --json`,
    // which returns a schema-versioned envelope rather than a JSONL stream.
    const jsonl =
        '{"schema_version":1,"data":['
        '{"id":"al-1","title":"hello flux","status":"open",'
        '"issue_type":"task"}'
        ']}';

    test(
      'the ONLY argv the default source ever issues is one all-status '
      '`query` — one spawn per store, a pure read (never show/ready/mutation)',
      () async {
        final runners = <String, _RecordingBdRunner>{};
        final source = BdExportBeadSource(
          runnerFor: (root) => runners[root] = _RecordingBdRunner(jsonl),
        );

        final beads = await source.read(_scope('alpha', '/roots/alpha', 'al'));

        expect(beads.single.id, 'al-1');
        final runner = runners['/roots/alpha']!;
        // The one all-status query core...
        const core = [
          'query',
          'status=open OR status=in_progress OR status=blocked OR '
              'status=deferred OR status=closed',
          '--all',
          '--json',
        ];
        // ...optionally suffixed by the uncapped-read `--limit 0`
        // (`BdCliService.queryArgs` since tg-vyis / the_grid #166, so the
        // store's default 50-row cap never truncates a search corpus; the
        // published beads_dart 0.2.0-rc.2 predates it). EXACTLY one of the
        // two shapes — any other argv still fails the fence, and either way
        // it is one spawn, one pure read.
        expect(runner.argvs, hasLength(1));
        expect(
          runner.argvs.single,
          anyOf(equals(core), equals([...core, '--limit', '0'])),
        );
      },
    );

    test('each store is read through its OWN root-bound runner (the spawn '
        'runs IN the store root, never a shared cwd)', () async {
      final roots = <String>[];
      final source = BdExportBeadSource(
        runnerFor: (root) {
          roots.add(root);
          return _RecordingBdRunner(jsonl);
        },
      );
      await source.read(_scope('alpha', '/roots/alpha'));
      await source.read(_scope('beta', '/roots/beta'));
      expect(roots, ['/roots/alpha', '/roots/beta']);
    });
  });
}
