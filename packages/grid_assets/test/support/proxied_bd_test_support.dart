// The shared proxied-bd test harness now lives in the package's public
// testing surface so a sibling package's tests can consume the SAME module
// from the published archive instead of reaching into this test tree by a
// relative path (which only resolves inside the workspace).
export 'package:grid_assets/testing/proxied_bd_test_support.dart';
