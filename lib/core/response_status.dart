/// Reads meaning out of an HTTP status, and refuses to guess.
///
/// The app learns what an account may do by asking webtrees' own access
/// middleware, which answers `403` before rendering anything. That makes a
/// denial cheap, but it also makes it tempting to treat every non-`200` as a
/// denial. It is not one: `302` means the session expired, and `5xx` means the
/// server failed. Collapsing those into "the user does not hold this role"
/// turns a transport problem into a false statement about the account.
///
/// So each operation names the statuses it accepts, and anything else becomes
/// a typed failure the interface can report honestly.
library;

import 'errors.dart';
import 'webtrees_client.dart';

/// Whether a probe of a role-guarded route found the role held.
///
/// `200` grants. `403` denies, and so does `404`: webtrees resolves the
/// `{tree}` route parameter against the trees the caller may see, so a tree
/// that is out of reach fails to bind rather than refusing outright. Any other
/// status is a fault, not an answer, and throws.
bool grantsAccess(Reply reply, {required String probe}) {
  if (reply.isOk) return true;
  if (reply.status == 403 || reply.status == 404) return false;
  throw failureFrom(reply, probe: probe);
}

/// The most specific error that fits a response the caller cannot use.
///
/// [probe] names what was being attempted, so an unexpected status reaches the
/// user as something actionable rather than a bare number.
WebtreesError failureFrom(Reply reply, {required String probe}) =>
    failureFor(reply.status, probe: probe);

/// The same judgement, for responses that are not text — media, chiefly.
WebtreesError failureFor(int status, {required String probe}) {
  // Middleware bounces an unauthenticated caller to the sign-in page, so a
  // redirect out of a guarded route means the session is gone.
  if (status >= 300 && status < 400) return const SessionExpired();
  if (status == 403) return NotPermitted(detail: 'Denied while $probe.');
  if (status == 404) return NotFound(detail: 'Not found while $probe.');
  return UnexpectedResponse(status, detail: 'Failed while $probe.');
}

/// What an anonymous request revealed about a tree.
///
/// Membership is only decidable for a private tree, and only when the question
/// was actually answered — hence the third case, which the interface must
/// report as uncertainty rather than resolving on the user's behalf.
enum TreeVisibility {
  /// Hidden from anonymous callers, which proves the signed-in user is a
  /// member rather than a visitor.
  private,

  /// Visible to anyone, so member and visitor look identical.
  public,

  /// The question could not be answered.
  unknown;

  /// Reads an anonymous fetch of a tree page.
  ///
  /// Only `404` proves privacy: webtrees fails to bind `{tree}` when the
  /// caller may not see it. A `403` would mean the tree exists but the page is
  /// barred, which says nothing about visitors, and a `5xx` says nothing at
  /// all.
  factory TreeVisibility.of(Reply reply) => switch (reply.status) {
    200 => TreeVisibility.public,
    404 => TreeVisibility.private,
    _ => TreeVisibility.unknown,
  };
}
