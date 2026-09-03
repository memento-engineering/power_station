import 'package:github_grid_assets/github_grid_assets.dart';
import 'package:test/test.dart';

void main() {
  test('the next target is read past prev, first and last', () {
    const header =
        '<https://api.github.test/repos/o/r/issues?page=1>; rel="prev", '
        '<https://api.github.test/repos/o/r/issues?page=3>; rel="next", '
        '<https://api.github.test/repos/o/r/issues?page=9>; rel="last"';
    expect(
      nextGitHubPageUri(header),
      Uri.parse('https://api.github.test/repos/o/r/issues?page=3'),
    );
  });

  test('an absent, empty or next-less header yields null', () {
    expect(nextGitHubPageUri(null), isNull);
    expect(nextGitHubPageUri(''), isNull);
    expect(
      nextGitHubPageUri('<https://api.github.test/x?page=9>; rel="last"'),
      isNull,
    );
    expect(
      nextGitHubPageUri('<https://api.github.test/x?page=9>; rel="nextish"'),
      isNull,
    );
  });
}
