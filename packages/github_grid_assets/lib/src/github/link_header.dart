/// Parsing for GitHub's `Link` pagination header.
///
/// GitHub returns at most one page per response and advertises the rest in a
/// `Link` header. This is the one home for that parse; the poll re-sends the
/// returned target through its own authenticated client seam.
library;

/// Returns the `rel="next"` target advertised by [linkHeader], or `null` when
/// the header is absent, empty, or advertises no next page.
///
/// The header is a comma-separated list of `<uri>; rel="name"` entries. Only
/// the URI is returned: callers rebuild the request through their own client
/// so it keeps its base host, authentication and API-version headers. GitHub's
/// own pagination targets never embed a comma, which is what makes the comma
/// split safe here.
Uri? nextGitHubPageUri(String? linkHeader) {
  if (linkHeader == null) return null;
  for (final entry in linkHeader.split(',')) {
    final match = _entryPattern.firstMatch(entry);
    if (match == null) continue;
    final target = match.group(1);
    final parameters = match.group(2);
    if (target == null || parameters == null) continue;
    if (!_relNextPattern.hasMatch(parameters)) continue;
    return Uri.parse(target);
  }
  return null;
}

final RegExp _entryPattern = RegExp(r'^\s*<([^>]+)>\s*;\s*(.+)$');
final RegExp _relNextPattern = RegExp(r'rel\s*=\s*"?next"?\s*(;|$)');
