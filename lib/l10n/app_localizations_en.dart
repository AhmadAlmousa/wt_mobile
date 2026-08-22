// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppTextEn extends AppText {
  AppTextEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'webtrees';

  @override
  String get connectTitle => 'Connect to your family tree';

  @override
  String get connectSubtitle => 'Enter the address of your webtrees site.';

  @override
  String get siteAddress => 'Site address';

  @override
  String get siteAddressHint => 'tree.example.com';

  @override
  String get siteAddressRequired =>
      'An address is needed, for example tree.example.com';

  @override
  String get connect => 'Connect';

  @override
  String get connecting => 'Connecting…';

  @override
  String get recentSites => 'Recent';

  @override
  String get signIn => 'Sign in';

  @override
  String get signingIn => 'Signing you in…';

  @override
  String get usernameOrEmail => 'Username or email';

  @override
  String get usernameRequired => 'Enter your username or email address.';

  @override
  String get password => 'Password';

  @override
  String get passwordRequired => 'Enter your password.';

  @override
  String get showPassword => 'Show password';

  @override
  String get hidePassword => 'Hide password';

  @override
  String get staySignedIn => 'Stay signed in';

  @override
  String get rememberUnavailable =>
      'This device has no secure storage, so your password cannot be kept.';

  @override
  String get rememberUngated =>
      'Your password is kept in this device’s secure storage. This device cannot ask for a fingerprint or passcode, so anyone who can unlock it can sign in as you.';

  @override
  String get rememberGated =>
      'Your password is kept in this device’s secure storage, and unlocked with your fingerprint, face or passcode.';

  @override
  String get passwordScopeNote =>
      'Your password is sent only to this site, over the same sign-in form its website uses.';

  @override
  String get insecureSiteWarning =>
      'This site does not use a secure connection. Your password would be sent unencrypted.';

  @override
  String get degradedServerWarning =>
      'This site reports a minor server configuration problem. Signing in should still work.';

  @override
  String get webtrees => 'webtrees';

  @override
  String webtreesVersion(String version) {
    return 'webtrees $version';
  }

  @override
  String hostAndVersion(String host, String version) {
    return '$host · webtrees $version';
  }

  @override
  String get yourAccess => 'Your access';

  @override
  String get checkAgain => 'Check again';

  @override
  String get signOut => 'Sign out';

  @override
  String get more => 'More';

  @override
  String get forgetThisSite => 'Forget this site';

  @override
  String get accessReadFailed => 'Something went wrong reading your access.';

  @override
  String get tryAgain => 'Try again';

  @override
  String get familyTrees => 'Family trees';

  @override
  String get siteAdministrator => 'Site administrator';

  @override
  String get roleAdministrator => 'Administrator';

  @override
  String get roleManager => 'Manager';

  @override
  String get roleModerator => 'Moderator';

  @override
  String get roleEditor => 'Editor';

  @override
  String get roleMember => 'Member';

  @override
  String get roleReadOnly => 'Read-only';

  @override
  String get describeAdministrator =>
      'You administer this site, so you manage every tree in it.';

  @override
  String get describeManager => 'You can change this tree and its settings.';

  @override
  String get describeModerator =>
      'You can edit records and approve changes other people submit.';

  @override
  String get describeEditor =>
      'You can edit records. Your changes wait for a moderator to approve them.';

  @override
  String get describeMember =>
      'You can view this tree, including living relatives.';

  @override
  String get describeMemberOrVisitor =>
      'You can view this tree. It is public, so the app cannot tell whether you are signed in as a member or seeing it as any visitor would.';

  @override
  String get canEdit => 'Can edit';

  @override
  String get canApproveChanges => 'Can approve changes';

  @override
  String get canManage => 'Can manage';

  @override
  String linkedTo(String xref) {
    return 'Linked to $xref';
  }

  @override
  String get searchForAPerson => 'Search for a person';

  @override
  String get searchHint => 'A name, or a record id such as I42';

  @override
  String get searchPrompt => 'Type a name to search this family tree.';

  @override
  String get searching => 'Searching…';

  @override
  String get noMatches =>
      'Nobody matched that name. Try a different spelling, or part of the name.';

  @override
  String get yourAccount => 'Your account';

  @override
  String get person => 'Person';

  @override
  String get reload => 'Reload';

  @override
  String get personOpenFailed => 'This person could not be opened.';

  @override
  String get factsAndEvents => 'Facts and events';

  @override
  String get parents => 'Parents';

  @override
  String get siblings => 'Brothers and sisters';

  @override
  String get spouses => 'Spouses';

  @override
  String get children => 'Children';

  @override
  String get photos => 'Photos';

  @override
  String get notes => 'Notes';

  @override
  String get sources => 'Sources';

  @override
  String get charts => 'Charts';

  @override
  String get chartAncestors => 'Ancestors';

  @override
  String get chartDescendants => 'Descendants';

  @override
  String get chartHourglass => 'Hourglass';

  @override
  String get chartRelationship => 'Relationship';

  @override
  String relationshipPick(String name) {
    return 'Whose relationship to $name?';
  }

  @override
  String get relationshipNoLink =>
      'No link between these two could be found in this tree.';

  @override
  String get relationshipChoose => 'Choose someone else';

  @override
  String get relationshipBloodOnly =>
      'This site searches blood relations only, so two people linked by a marriage show no link.';

  @override
  String get relationshipPaths => 'Found more than one way they are related.';

  @override
  String get chartView => 'How to draw it';

  @override
  String get chartViewTree => 'Tree';

  @override
  String get chartViewCircle => 'Circle';

  @override
  String get chartViewCompact => 'Compact';

  @override
  String get openThisPerson => 'Open this person';

  @override
  String get chartFromHere => 'Draw the chart from here';

  @override
  String get chartFailed => 'This chart could not be drawn.';

  @override
  String get chartEmpty => 'Nobody else is recorded here yet.';

  @override
  String get showMoreResults => 'Show more';

  @override
  String get eventsOfCloseRelatives => 'Events of close relatives';

  @override
  String get settings => 'Settings';

  @override
  String get appearance => 'Appearance';

  @override
  String get themeSystem => 'Follow the device';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

  @override
  String get language => 'Language';

  @override
  String get languageSystem => 'Follow the device';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageArabic => 'العربية';

  @override
  String get languageAffectsSite =>
      'Dates, month names and event labels are written by your webtrees site, so the app asks it for this language too. That also changes the language its website greets you in.';

  @override
  String get calendar => 'Calendar';

  @override
  String get calendarBoth => 'Both';

  @override
  String get calendarGregorian => 'Gregorian';

  @override
  String get calendarHijri => 'Hijri';

  @override
  String get calendarOnlyWhenOffered =>
      'A date is only shown in the calendar you choose when the site converts it. Otherwise it appears as the site wrote it.';

  @override
  String get done => 'Done';

  @override
  String errorUnreachableHost(String address, String detail) {
    return 'Could not reach $address.$detail Check the address and your connection.';
  }

  @override
  String errorNotWebtrees(String address) {
    return '$address answered, but it does not look like a webtrees site. Check the address — it should point at the page where you normally sign in.';
  }

  @override
  String get errorMaintenanceMode =>
      'The site is offline for maintenance. Try again later.';

  @override
  String get errorServerUnhealthy =>
      'The webtrees site reports a server configuration problem and cannot run. Its administrator needs to look at the control panel.';

  @override
  String errorBlockedAsBot(String reason) {
    return 'The site blocked this app as automated traffic ($reason).';
  }

  @override
  String get errorSignInRejected =>
      'That username or password was not accepted.';

  @override
  String get errorStaleSignIn => 'The sign-in attempt expired. Try again.';

  @override
  String get errorSessionExpired => 'Your session ended. Sign in again.';

  @override
  String get errorNotPermitted => 'Your account does not have access to this.';

  @override
  String get errorNotFound =>
      'That item does not exist, or is not visible to you.';

  @override
  String errorUnexpectedResponse(int status) {
    return 'The site responded unexpectedly (HTTP $status).';
  }

  @override
  String errorCannotRead(String what) {
    return 'Could not read $what from this webtrees version. It may use a theme or version this app has not seen yet.';
  }

  @override
  String errorParseFailure(String parser) {
    return 'Could not read the $parser on this site. It may use a theme or a webtrees version this app has not seen yet.';
  }

  @override
  String noticeSiteRenamedItself(String canonical) {
    return 'This site calls itself $canonical. The app will use that address, because its sign-in cookie is issued for that host.';
  }

  @override
  String noticeBlocklistUnchecked(String reason) {
    return 'Could not check the site blocklist: $reason';
  }

  @override
  String get noticeVersionUnreadable => 'Could not read the site version.';

  @override
  String get noticeSiteUnidentified =>
      'This site did not identify itself as webtrees. The app will continue, but some features may not work.';

  @override
  String get noticeNoTreesVisible =>
      'This account cannot see any family tree. Its administrator may still need to grant access.';

  @override
  String get noticeOnlyOneTreeFound =>
      'Only one family tree was found. If this site has more, its administrator may have turned off switching between trees.';

  @override
  String get noticeFactsUnavailable =>
      'Facts and events could not be loaded for this person.';

  @override
  String get noticeRelativesUnavailable =>
      'Family members could not be loaded for this person.';

  @override
  String get noticeNotesUnavailable =>
      'Notes could not be loaded for this person.';

  @override
  String get noticeSourcesUnavailable =>
      'Sources could not be loaded for this person.';

  @override
  String get noticeMediaUnavailable =>
      'Photos could not be loaded for this person.';

  @override
  String noticeSectionUnavailable(String module) {
    return 'The $module section could not be loaded.';
  }
}
