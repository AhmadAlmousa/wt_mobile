import 'package:flutter/widgets.dart';

import '../../core/errors.dart';
import '../../domain/notice.dart';
import '../../l10n/app_localizations.dart';

/// Turns the app's typed failures and caveats into sentences for the reader.
///
/// The data layer deliberately does not word these: it discovers *what*
/// happened, and the wording belongs to whichever locale is on screen. Both
/// switches are exhaustive over sealed types, so a new [WebtreesError] or
/// [Notice] fails to compile until it has been given words.
extension LocalizedError on WebtreesError {
  /// This failure, in the reader's language.
  ///
  /// Where webtrees itself supplied the text — a rejected sign-in names the
  /// reason the site gave, in the site's own language — that text is preferred
  /// over a translation of ours, because it is the site's answer and is often
  /// more specific than "not accepted".
  String localized(AppText text) => switch (this) {
    UnreachableHost(:final address, :final detail) => text.errorUnreachableHost(
      address,
      detail == null ? '' : ' $detail.',
    ),
    NotWebtrees(:final address) => text.errorNotWebtrees(address),
    MaintenanceMode() => text.errorMaintenanceMode,
    ServerUnhealthy() => text.errorServerUnhealthy,
    BlockedAsBot(:final reason) => text.errorBlockedAsBot(reason),
    SignInRejected(:final serverMessage) =>
      serverMessage ?? text.errorSignInRejected,
    StaleSignIn() => text.errorStaleSignIn,
    SessionExpired() => text.errorSessionExpired,
    NotPermitted() => text.errorNotPermitted,
    NotFound() => text.errorNotFound,
    UnexpectedResponse(:final status) => text.errorUnexpectedResponse(status),
    CannotRead(:final what) => text.errorCannotRead(what),
    ParseFailure(:final parser) => text.errorParseFailure(parser),
  };
}

/// A caveat, in the reader's language.
extension LocalizedNotice on Notice {
  String localized(AppText text) => switch (this) {
    SiteRenamedItself(:final canonical) => text.noticeSiteRenamedItself(
      canonical.toString(),
    ),
    BlocklistUnchecked(:final reason) => text.noticeBlocklistUnchecked(reason),
    VersionUnreadable() => text.noticeVersionUnreadable,
    SiteUnidentified() => text.noticeSiteUnidentified,
    NoTreesVisible() => text.noticeNoTreesVisible,
    OnlyOneTreeFound() => text.noticeOnlyOneTreeFound,
    // The sections the app actually asks for get a sentence naming them;
    // anything else a site offers falls back to the module's own name.
    SectionUnavailable(:final module) => switch (module) {
      'personal_facts' => text.noticeFactsUnavailable,
      'relatives' => text.noticeRelativesUnavailable,
      'notes' => text.noticeNotesUnavailable,
      'sources_tab' => text.noticeSourcesUnavailable,
      'media' => text.noticeMediaUnavailable,
      _ => text.noticeSectionUnavailable(module),
    },
  };
}

/// `AppText.of(context)`, shortened at the call site.
AppText textOf(BuildContext context) => AppText.of(context);
