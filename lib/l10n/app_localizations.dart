import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ar.dart';
import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppText
/// returned by `AppText.of(context)`.
///
/// Applications need to include `AppText.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppText.localizationsDelegates,
///   supportedLocales: AppText.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppText.supportedLocales
/// property.
abstract class AppText {
  AppText(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppText of(BuildContext context) {
    return Localizations.of<AppText>(context, AppText)!;
  }

  static const LocalizationsDelegate<AppText> delegate = _AppTextDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ar'),
    Locale('en'),
  ];

  /// The application name, shown as the task title.
  ///
  /// In en, this message translates to:
  /// **'webtrees'**
  String get appTitle;

  /// No description provided for @connectTitle.
  ///
  /// In en, this message translates to:
  /// **'Connect to your family tree'**
  String get connectTitle;

  /// No description provided for @connectSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Enter the address of your webtrees site.'**
  String get connectSubtitle;

  /// No description provided for @siteAddress.
  ///
  /// In en, this message translates to:
  /// **'Site address'**
  String get siteAddress;

  /// No description provided for @siteAddressHint.
  ///
  /// In en, this message translates to:
  /// **'tree.example.com'**
  String get siteAddressHint;

  /// No description provided for @siteAddressRequired.
  ///
  /// In en, this message translates to:
  /// **'An address is needed, for example tree.example.com'**
  String get siteAddressRequired;

  /// No description provided for @connect.
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get connect;

  /// No description provided for @connecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting…'**
  String get connecting;

  /// No description provided for @recentSites.
  ///
  /// In en, this message translates to:
  /// **'Recent'**
  String get recentSites;

  /// No description provided for @signIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get signIn;

  /// No description provided for @signingIn.
  ///
  /// In en, this message translates to:
  /// **'Signing you in…'**
  String get signingIn;

  /// No description provided for @usernameOrEmail.
  ///
  /// In en, this message translates to:
  /// **'Username or email'**
  String get usernameOrEmail;

  /// No description provided for @usernameRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter your username or email address.'**
  String get usernameRequired;

  /// No description provided for @password.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get password;

  /// No description provided for @passwordRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter your password.'**
  String get passwordRequired;

  /// No description provided for @showPassword.
  ///
  /// In en, this message translates to:
  /// **'Show password'**
  String get showPassword;

  /// No description provided for @hidePassword.
  ///
  /// In en, this message translates to:
  /// **'Hide password'**
  String get hidePassword;

  /// No description provided for @staySignedIn.
  ///
  /// In en, this message translates to:
  /// **'Stay signed in'**
  String get staySignedIn;

  /// No description provided for @rememberUnavailable.
  ///
  /// In en, this message translates to:
  /// **'This device has no secure storage, so your password cannot be kept.'**
  String get rememberUnavailable;

  /// No description provided for @rememberUngated.
  ///
  /// In en, this message translates to:
  /// **'Your password is kept in this device’s secure storage. This device cannot ask for a fingerprint or passcode, so anyone who can unlock it can sign in as you.'**
  String get rememberUngated;

  /// No description provided for @rememberGated.
  ///
  /// In en, this message translates to:
  /// **'Your password is kept in this device’s secure storage, and unlocked with your fingerprint, face or passcode.'**
  String get rememberGated;

  /// No description provided for @passwordScopeNote.
  ///
  /// In en, this message translates to:
  /// **'Your password is sent only to this site, over the same sign-in form its website uses.'**
  String get passwordScopeNote;

  /// No description provided for @insecureSiteWarning.
  ///
  /// In en, this message translates to:
  /// **'This site does not use a secure connection. Your password would be sent unencrypted.'**
  String get insecureSiteWarning;

  /// No description provided for @degradedServerWarning.
  ///
  /// In en, this message translates to:
  /// **'This site reports a minor server configuration problem. Signing in should still work.'**
  String get degradedServerWarning;

  /// No description provided for @webtrees.
  ///
  /// In en, this message translates to:
  /// **'webtrees'**
  String get webtrees;

  /// No description provided for @webtreesVersion.
  ///
  /// In en, this message translates to:
  /// **'webtrees {version}'**
  String webtreesVersion(String version);

  /// No description provided for @hostAndVersion.
  ///
  /// In en, this message translates to:
  /// **'{host} · webtrees {version}'**
  String hostAndVersion(String host, String version);

  /// No description provided for @yourAccess.
  ///
  /// In en, this message translates to:
  /// **'Your access'**
  String get yourAccess;

  /// No description provided for @checkAgain.
  ///
  /// In en, this message translates to:
  /// **'Check again'**
  String get checkAgain;

  /// No description provided for @signOut.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get signOut;

  /// No description provided for @more.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get more;

  /// No description provided for @forgetThisSite.
  ///
  /// In en, this message translates to:
  /// **'Forget this site'**
  String get forgetThisSite;

  /// No description provided for @accessReadFailed.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong reading your access.'**
  String get accessReadFailed;

  /// No description provided for @tryAgain.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get tryAgain;

  /// No description provided for @familyTrees.
  ///
  /// In en, this message translates to:
  /// **'Family trees'**
  String get familyTrees;

  /// No description provided for @siteAdministrator.
  ///
  /// In en, this message translates to:
  /// **'Site administrator'**
  String get siteAdministrator;

  /// No description provided for @roleAdministrator.
  ///
  /// In en, this message translates to:
  /// **'Administrator'**
  String get roleAdministrator;

  /// No description provided for @roleManager.
  ///
  /// In en, this message translates to:
  /// **'Manager'**
  String get roleManager;

  /// No description provided for @roleModerator.
  ///
  /// In en, this message translates to:
  /// **'Moderator'**
  String get roleModerator;

  /// No description provided for @roleEditor.
  ///
  /// In en, this message translates to:
  /// **'Editor'**
  String get roleEditor;

  /// No description provided for @roleMember.
  ///
  /// In en, this message translates to:
  /// **'Member'**
  String get roleMember;

  /// No description provided for @roleReadOnly.
  ///
  /// In en, this message translates to:
  /// **'Read-only'**
  String get roleReadOnly;

  /// No description provided for @describeAdministrator.
  ///
  /// In en, this message translates to:
  /// **'You administer this site, so you manage every tree in it.'**
  String get describeAdministrator;

  /// No description provided for @describeManager.
  ///
  /// In en, this message translates to:
  /// **'You can change this tree and its settings.'**
  String get describeManager;

  /// No description provided for @describeModerator.
  ///
  /// In en, this message translates to:
  /// **'You can edit records and approve changes other people submit.'**
  String get describeModerator;

  /// No description provided for @describeEditor.
  ///
  /// In en, this message translates to:
  /// **'You can edit records. Your changes wait for a moderator to approve them.'**
  String get describeEditor;

  /// No description provided for @describeMember.
  ///
  /// In en, this message translates to:
  /// **'You can view this tree, including living relatives.'**
  String get describeMember;

  /// No description provided for @describeMemberOrVisitor.
  ///
  /// In en, this message translates to:
  /// **'You can view this tree. It is public, so the app cannot tell whether you are signed in as a member or seeing it as any visitor would.'**
  String get describeMemberOrVisitor;

  /// No description provided for @canEdit.
  ///
  /// In en, this message translates to:
  /// **'Can edit'**
  String get canEdit;

  /// No description provided for @canApproveChanges.
  ///
  /// In en, this message translates to:
  /// **'Can approve changes'**
  String get canApproveChanges;

  /// No description provided for @canManage.
  ///
  /// In en, this message translates to:
  /// **'Can manage'**
  String get canManage;

  /// No description provided for @linkedTo.
  ///
  /// In en, this message translates to:
  /// **'Linked to {xref}'**
  String linkedTo(String xref);

  /// No description provided for @searchForAPerson.
  ///
  /// In en, this message translates to:
  /// **'Search for a person'**
  String get searchForAPerson;

  /// No description provided for @searchHint.
  ///
  /// In en, this message translates to:
  /// **'A name, or a record id such as I42'**
  String get searchHint;

  /// No description provided for @searchPrompt.
  ///
  /// In en, this message translates to:
  /// **'Type a name to search this family tree.'**
  String get searchPrompt;

  /// No description provided for @searching.
  ///
  /// In en, this message translates to:
  /// **'Searching…'**
  String get searching;

  /// No description provided for @noMatches.
  ///
  /// In en, this message translates to:
  /// **'Nobody matched that name. Try a different spelling, or part of the name.'**
  String get noMatches;

  /// No description provided for @yourAccount.
  ///
  /// In en, this message translates to:
  /// **'Your account'**
  String get yourAccount;

  /// No description provided for @person.
  ///
  /// In en, this message translates to:
  /// **'Person'**
  String get person;

  /// No description provided for @reload.
  ///
  /// In en, this message translates to:
  /// **'Reload'**
  String get reload;

  /// No description provided for @personOpenFailed.
  ///
  /// In en, this message translates to:
  /// **'This person could not be opened.'**
  String get personOpenFailed;

  /// No description provided for @factsAndEvents.
  ///
  /// In en, this message translates to:
  /// **'Facts and events'**
  String get factsAndEvents;

  /// No description provided for @parents.
  ///
  /// In en, this message translates to:
  /// **'Parents'**
  String get parents;

  /// No description provided for @siblings.
  ///
  /// In en, this message translates to:
  /// **'Brothers and sisters'**
  String get siblings;

  /// No description provided for @spouses.
  ///
  /// In en, this message translates to:
  /// **'Spouses'**
  String get spouses;

  /// No description provided for @children.
  ///
  /// In en, this message translates to:
  /// **'Children'**
  String get children;

  /// No description provided for @photos.
  ///
  /// In en, this message translates to:
  /// **'Photos'**
  String get photos;

  /// No description provided for @notes.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get notes;

  /// No description provided for @sources.
  ///
  /// In en, this message translates to:
  /// **'Sources'**
  String get sources;

  /// No description provided for @showMoreResults.
  ///
  /// In en, this message translates to:
  /// **'Show more'**
  String get showMoreResults;

  /// No description provided for @eventsOfCloseRelatives.
  ///
  /// In en, this message translates to:
  /// **'Events of close relatives'**
  String get eventsOfCloseRelatives;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @appearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get appearance;

  /// No description provided for @themeSystem.
  ///
  /// In en, this message translates to:
  /// **'Follow the device'**
  String get themeSystem;

  /// No description provided for @themeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get themeLight;

  /// No description provided for @themeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get themeDark;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @languageSystem.
  ///
  /// In en, this message translates to:
  /// **'Follow the device'**
  String get languageSystem;

  /// No description provided for @languageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// No description provided for @languageArabic.
  ///
  /// In en, this message translates to:
  /// **'العربية'**
  String get languageArabic;

  /// No description provided for @languageAffectsSite.
  ///
  /// In en, this message translates to:
  /// **'Dates, month names and event labels are written by your webtrees site, so the app asks it for this language too. That also changes the language its website greets you in.'**
  String get languageAffectsSite;

  /// No description provided for @calendar.
  ///
  /// In en, this message translates to:
  /// **'Calendar'**
  String get calendar;

  /// No description provided for @calendarBoth.
  ///
  /// In en, this message translates to:
  /// **'Both'**
  String get calendarBoth;

  /// No description provided for @calendarGregorian.
  ///
  /// In en, this message translates to:
  /// **'Gregorian'**
  String get calendarGregorian;

  /// No description provided for @calendarHijri.
  ///
  /// In en, this message translates to:
  /// **'Hijri'**
  String get calendarHijri;

  /// No description provided for @calendarOnlyWhenOffered.
  ///
  /// In en, this message translates to:
  /// **'A date is only shown in the calendar you choose when the site converts it. Otherwise it appears as the site wrote it.'**
  String get calendarOnlyWhenOffered;

  /// No description provided for @done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// No description provided for @errorUnreachableHost.
  ///
  /// In en, this message translates to:
  /// **'Could not reach {address}.{detail} Check the address and your connection.'**
  String errorUnreachableHost(String address, String detail);

  /// No description provided for @errorNotWebtrees.
  ///
  /// In en, this message translates to:
  /// **'{address} answered, but it does not look like a webtrees site. Check the address — it should point at the page where you normally sign in.'**
  String errorNotWebtrees(String address);

  /// No description provided for @errorMaintenanceMode.
  ///
  /// In en, this message translates to:
  /// **'The site is offline for maintenance. Try again later.'**
  String get errorMaintenanceMode;

  /// No description provided for @errorServerUnhealthy.
  ///
  /// In en, this message translates to:
  /// **'The webtrees site reports a server configuration problem and cannot run. Its administrator needs to look at the control panel.'**
  String get errorServerUnhealthy;

  /// No description provided for @errorBlockedAsBot.
  ///
  /// In en, this message translates to:
  /// **'The site blocked this app as automated traffic ({reason}).'**
  String errorBlockedAsBot(String reason);

  /// No description provided for @errorSignInRejected.
  ///
  /// In en, this message translates to:
  /// **'That username or password was not accepted.'**
  String get errorSignInRejected;

  /// No description provided for @errorStaleSignIn.
  ///
  /// In en, this message translates to:
  /// **'The sign-in attempt expired. Try again.'**
  String get errorStaleSignIn;

  /// No description provided for @errorSessionExpired.
  ///
  /// In en, this message translates to:
  /// **'Your session ended. Sign in again.'**
  String get errorSessionExpired;

  /// No description provided for @errorNotPermitted.
  ///
  /// In en, this message translates to:
  /// **'Your account does not have access to this.'**
  String get errorNotPermitted;

  /// No description provided for @errorNotFound.
  ///
  /// In en, this message translates to:
  /// **'That item does not exist, or is not visible to you.'**
  String get errorNotFound;

  /// No description provided for @errorUnexpectedResponse.
  ///
  /// In en, this message translates to:
  /// **'The site responded unexpectedly (HTTP {status}).'**
  String errorUnexpectedResponse(int status);

  /// No description provided for @errorCannotRead.
  ///
  /// In en, this message translates to:
  /// **'Could not read {what} from this webtrees version. It may use a theme or version this app has not seen yet.'**
  String errorCannotRead(String what);

  /// No description provided for @errorParseFailure.
  ///
  /// In en, this message translates to:
  /// **'Could not read the {parser} on this site. It may use a theme or a webtrees version this app has not seen yet.'**
  String errorParseFailure(String parser);

  /// No description provided for @noticeSiteRenamedItself.
  ///
  /// In en, this message translates to:
  /// **'This site calls itself {canonical}. The app will use that address, because its sign-in cookie is issued for that host.'**
  String noticeSiteRenamedItself(String canonical);

  /// No description provided for @noticeBlocklistUnchecked.
  ///
  /// In en, this message translates to:
  /// **'Could not check the site blocklist: {reason}'**
  String noticeBlocklistUnchecked(String reason);

  /// No description provided for @noticeVersionUnreadable.
  ///
  /// In en, this message translates to:
  /// **'Could not read the site version.'**
  String get noticeVersionUnreadable;

  /// No description provided for @noticeSiteUnidentified.
  ///
  /// In en, this message translates to:
  /// **'This site did not identify itself as webtrees. The app will continue, but some features may not work.'**
  String get noticeSiteUnidentified;

  /// No description provided for @noticeNoTreesVisible.
  ///
  /// In en, this message translates to:
  /// **'This account cannot see any family tree. Its administrator may still need to grant access.'**
  String get noticeNoTreesVisible;

  /// No description provided for @noticeOnlyOneTreeFound.
  ///
  /// In en, this message translates to:
  /// **'Only one family tree was found. If this site has more, its administrator may have turned off switching between trees.'**
  String get noticeOnlyOneTreeFound;

  /// No description provided for @noticeFactsUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Facts and events could not be loaded for this person.'**
  String get noticeFactsUnavailable;

  /// No description provided for @noticeRelativesUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Family members could not be loaded for this person.'**
  String get noticeRelativesUnavailable;

  /// No description provided for @noticeNotesUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Notes could not be loaded for this person.'**
  String get noticeNotesUnavailable;

  /// No description provided for @noticeSourcesUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Sources could not be loaded for this person.'**
  String get noticeSourcesUnavailable;

  /// No description provided for @noticeMediaUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Photos could not be loaded for this person.'**
  String get noticeMediaUnavailable;

  /// No description provided for @noticeSectionUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The {module} section could not be loaded.'**
  String noticeSectionUnavailable(String module);
}

class _AppTextDelegate extends LocalizationsDelegate<AppText> {
  const _AppTextDelegate();

  @override
  Future<AppText> load(Locale locale) {
    return SynchronousFuture<AppText>(lookupAppText(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['ar', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppTextDelegate old) => false;
}

AppText lookupAppText(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar':
      return AppTextAr();
    case 'en':
      return AppTextEn();
  }

  throw FlutterError(
    'AppText.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
