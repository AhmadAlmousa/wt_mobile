/// Everything that can go wrong between the app and a webtrees instance.
///
/// Each case carries a [message] written for the person holding the phone:
/// it says what happened and, where there is one, what to do about it.
sealed class WebtreesError implements Exception {
  const WebtreesError();

  /// A complete sentence, safe to show in the interface.
  String get message;

  @override
  String toString() => '$runtimeType: $message';
}

/// The host did not answer: no DNS, no route, TLS failure, or a timeout.
final class UnreachableHost extends WebtreesError {
  const UnreachableHost(this.address, {this.detail});

  final String address;
  final String? detail;

  @override
  String get message =>
      'Could not reach $address.'
      '${detail == null ? '' : ' $detail.'}'
      ' Check the address and your connection.';
}

/// Something answered, but it does not behave like webtrees.
final class NotWebtrees extends WebtreesError {
  const NotWebtrees(this.address);

  final String address;

  @override
  String get message =>
      '$address answered, but it does not look like a webtrees site. '
      'Check the address — it should point at the page where you normally '
      'sign in.';
}

/// The administrator has taken the site offline (`data/offline.txt`).
final class MaintenanceMode extends WebtreesError {
  const MaintenanceMode();

  @override
  String get message => 'The site is offline for maintenance. Try again later.';
}

/// The server is missing a PHP extension or database driver it requires.
final class ServerUnhealthy extends WebtreesError {
  const ServerUnhealthy();

  @override
  String get message =>
      'The webtrees site reports a server configuration problem and cannot '
      'run. Its administrator needs to look at the control panel.';
}

/// webtrees' bad-bot filter rejected the request.
///
/// [reason] is the server's own suffix — `no-ua`, `bad-ua`, `bad-dns`,
/// `bad-asn`, `routing` or `not-wp` — which pinpoints the rule that fired.
final class BlockedAsBot extends WebtreesError {
  const BlockedAsBot(this.reason);

  final String reason;

  @override
  String get message =>
      'The site blocked this app as automated traffic ($reason).';
}

/// The sign-in was rejected.
///
/// webtrees answers a wrong password, an unverified email and an unapproved
/// account with the same redirect, so the app cannot tell them apart. When the
/// server's own explanation could be read it arrives as [serverMessage],
/// already translated into the site's language.
final class SignInRejected extends WebtreesError {
  const SignInRejected({this.serverMessage});

  final String? serverMessage;

  @override
  String get message =>
      serverMessage ?? 'That username or password was not accepted.';
}

/// The session or CSRF token was stale when the sign-in was submitted.
///
/// Recoverable: fetch a fresh token and submit again.
final class StaleSignIn extends WebtreesError {
  const StaleSignIn();

  @override
  String get message => 'The sign-in attempt expired. Try again.';
}

/// The session is no longer valid and could not be renewed.
final class SessionExpired extends WebtreesError {
  const SessionExpired();

  @override
  String get message => 'Your session ended. Sign in again.';
}

/// The account is valid but lacks the rights for what was requested.
final class NotPermitted extends WebtreesError {
  const NotPermitted({this.detail});

  final String? detail;

  @override
  String get message => detail ?? 'Your account does not have access to this.';
}

/// The requested record or tree does not exist, or is hidden from this user.
final class NotFound extends WebtreesError {
  const NotFound({this.detail});

  final String? detail;

  @override
  String get message =>
      detail ?? 'That item does not exist, or is not visible to you.';
}

/// The server answered, but not in a way the app can use.
final class UnexpectedResponse extends WebtreesError {
  const UnexpectedResponse(this.status, {this.detail});

  final int status;
  final String? detail;

  @override
  String get message =>
      'The site responded unexpectedly (HTTP $status).'
      '${detail == null ? '' : ' $detail'}';
}

/// A page or fragment could not be read.
///
/// Stock webtrees has no API, so the app reads its HTML. Themes and versions
/// vary, so this is expected occasionally and names [what] failed, to make the
/// report actionable rather than a blank screen.
final class CannotRead extends WebtreesError {
  const CannotRead(this.what);

  final String what;

  @override
  String get message =>
      'Could not read $what from this webtrees version. '
      'It may use a theme or version this app has not seen yet.';
}
