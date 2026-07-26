import 'dart:convert';
import 'dart:io';

import 'package:grid_assets/src/code/code_capabilities.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// tg-v7qq — an ADOPTED worktree's bead store must resolve to the substation
/// root's proxieddb, never to a prior arm's self-hosted dolt store.
///
/// The stranding: `provisionWorkspace` is idempotent on an existing checkout,
/// so a leftover worktree from a previous station arm was reused AS-IS — its
/// `.beads` still carrying an independent `dolt/` + `dolt-server-*` sidecar.
/// Every in-worktree `bd update` (the specify stage's spec write-back) landed
/// in that isolated clone; the station and the critique lanes read the ROOT
/// store; spec-validation hard-blocked structurally perfect spec rounds
/// (live receipt: swift-infer-2cg, 4/4 template markers in the worktree
/// store, 0/4 in root).
void main() {
  late Directory tmp;
  late String workspaceDir;
  late String rootRepoPath;
  late String beadsDir;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('v7qq-repair-');
    workspaceDir = p.join(tmp.path, 'worktree');
    rootRepoPath = p.join(tmp.path, 'root-repo');
    beadsDir = p.join(workspaceDir, '.beads');
    Directory(beadsDir).createSync(recursive: true);
    Directory(p.join(rootRepoPath, '.beads', 'proxieddb'))
        .createSync(recursive: true);
    // The committed scaffold — must survive every repair untouched.
    File(p.join(beadsDir, 'metadata.json'))
        .writeAsStringSync('{"dolt_mode":"proxied-server"}');
    File(p.join(beadsDir, 'config.yaml')).writeAsStringSync('types: {}\n');
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  void seedStrandedStore() {
    Directory(p.join(beadsDir, 'dolt', 'db')).createSync(recursive: true);
    File(p.join(beadsDir, 'dolt', 'db', 'chunk')).writeAsStringSync('x');
    for (final name in const [
      'dolt-server-config.yaml',
      'dolt-server.lock',
      'dolt-server.port',
      'dolt-server.log',
      'last-touched',
    ]) {
      File(p.join(beadsDir, name)).writeAsStringSync(name);
    }
  }

  test('a self-hosted store from a prior arm is stripped; the committed '
      'scaffold survives; a receipt lands', () {
    seedStrandedStore();

    GitSourceControl.repairStrandedWorktreeStore(
      workspaceDir: workspaceDir,
      rootRepoPath: rootRepoPath,
      beadId: 'tg-2cg',
    );

    expect(Directory(p.join(beadsDir, 'dolt')).existsSync(), isFalse);
    expect(File(p.join(beadsDir, 'dolt-server-config.yaml')).existsSync(),
        isFalse);
    expect(File(p.join(beadsDir, 'last-touched')).existsSync(), isFalse);
    // Scaffold untouched.
    expect(File(p.join(beadsDir, 'metadata.json')).existsSync(), isTrue);
    expect(File(p.join(beadsDir, 'config.yaml')).existsSync(), isTrue);
    // The repair is visible in the worktree.
    final receipt = File(p.join(beadsDir, 'store-repair.log'));
    expect(receipt.existsSync(), isTrue);
    expect(receipt.readAsStringSync(), contains('tg-2cg'));
    expect(receipt.readAsStringSync(), contains('proxieddb'));
  });

  test('client info pointing anywhere but the root proxieddb is stranded '
      'and repaired', () {
    File(p.join(beadsDir, 'proxied_server_client_info.json')).writeAsStringSync(
      jsonEncode({'root_path': p.join(tmp.path, 'somewhere-else')}),
    );

    GitSourceControl.repairStrandedWorktreeStore(
      workspaceDir: workspaceDir,
      rootRepoPath: rootRepoPath,
      beadId: 'tg-x',
    );

    expect(
      File(p.join(beadsDir, 'proxied_server_client_info.json')).existsSync(),
      isFalse,
    );
    expect(
      File(p.join(beadsDir, 'store-repair.log')).existsSync(),
      isTrue,
    );
  });

  test('a HEALTHY proxied worktree (client info at the root proxieddb, no '
      'self-hosted artifacts) is left byte-untouched', () {
    final clientInfo = File(
      p.join(beadsDir, 'proxied_server_client_info.json'),
    )..writeAsStringSync(
        jsonEncode({
          'root_path': p.join(rootRepoPath, '.beads', 'proxieddb'),
        }),
      );
    final before = clientInfo.readAsStringSync();

    GitSourceControl.repairStrandedWorktreeStore(
      workspaceDir: workspaceDir,
      rootRepoPath: rootRepoPath,
      beadId: 'tg-y',
    );

    expect(clientInfo.readAsStringSync(), before);
    expect(File(p.join(beadsDir, 'store-repair.log')).existsSync(), isFalse);
  });

  test('a scaffold-only .beads (fresh worktree shape) is a no-op', () {
    GitSourceControl.repairStrandedWorktreeStore(
      workspaceDir: workspaceDir,
      rootRepoPath: rootRepoPath,
      beadId: 'tg-z',
    );

    expect(File(p.join(beadsDir, 'metadata.json')).existsSync(), isTrue);
    expect(File(p.join(beadsDir, 'store-repair.log')).existsSync(), isFalse);
  });

  test('a missing .beads dir is a no-op', () {
    Directory(beadsDir).deleteSync(recursive: true);
    GitSourceControl.repairStrandedWorktreeStore(
      workspaceDir: workspaceDir,
      rootRepoPath: rootRepoPath,
      beadId: 'tg-w',
    );
    expect(Directory(beadsDir).existsSync(), isFalse);
  });
}
