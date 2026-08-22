/// A caveat the app wants to state, without deciding how to word it.
///
/// The data layer discovers these — a site that renames itself, an account
/// with no readable tree, a tab that would not load — but it cannot write them
/// for the reader: the app speaks more than one language, and the wording
/// belongs to whichever locale is on screen. So each case carries only the
/// facts, and the presentation layer turns it into a sentence.
///
/// Sealed, so adding a case forces every renderer to answer for it rather than
/// silently falling through to a blank line.
sealed class Notice {
  const Notice();

  /// A developer-facing description, for logs and the command-line tools.
  ///
  /// Deliberately *not* the sentence a reader sees: that one is translated and
  /// lives in the presentation layer. This one exists because a diagnostic
  /// that prints `Instance of 'OnlyOneTreeFound'` wastes the reader's time.
  String get diagnostic => switch (this) {
    SiteRenamedItself(:final canonical) => 'site calls itself $canonical',
    BlocklistUnchecked(:final reason) => 'blocklist unchecked: $reason',
    VersionUnreadable() => 'site version unreadable',
    SiteUnidentified() => 'site did not identify itself as webtrees',
    NoTreesVisible() => 'no family tree visible to this account',
    OnlyOneTreeFound() => 'only one family tree found',
    SectionUnavailable(:final module) => 'section unavailable: $module',
  };

  @override
  String toString() => diagnostic;
}

/// The site's canonical address differs from the one that was typed.
///
/// Worth saying because the sign-in cookie is issued for the canonical host,
/// so the app follows it rather than the address the user entered.
final class SiteRenamedItself extends Notice {
  const SiteRenamedItself(this.canonical);

  final Uri canonical;
}

/// The blocklist could not be fetched, so the app could not confirm its own
/// user agent is acceptable to this site.
final class BlocklistUnchecked extends Notice {
  const BlocklistUnchecked(this.reason);

  final String reason;
}

/// The version could not be read from the sign-in page.
final class VersionUnreadable extends Notice {
  const VersionUnreadable();
}

/// Something answered, but never identified itself as webtrees.
final class SiteUnidentified extends Notice {
  const SiteUnidentified();
}

/// The account can reach no family tree at all.
final class NoTreesVisible extends Notice {
  const NoTreesVisible();
}

/// Exactly one tree was found, which may be all there is — or may be all the
/// site is willing to name.
final class OnlyOneTreeFound extends Notice {
  const OnlyOneTreeFound();
}

/// A record section could not be loaded, so that part of the page is missing.
final class SectionUnavailable extends Notice {
  const SectionUnavailable(this.module);

  /// The webtrees module name: `personal_facts`, `relatives`, and so on.
  final String module;
}
