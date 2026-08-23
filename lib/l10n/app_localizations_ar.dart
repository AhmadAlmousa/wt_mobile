// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Arabic (`ar`).
class AppTextAr extends AppText {
  AppTextAr([String locale = 'ar']) : super(locale);

  @override
  String get appTitle => 'webtrees';

  @override
  String get connectTitle => 'اتّصل بشجرة عائلتك';

  @override
  String get connectSubtitle => 'أدخل عنوان موقع webtrees الخاص بك.';

  @override
  String get siteAddress => 'عنوان الموقع';

  @override
  String get siteAddressHint => 'tree.example.com';

  @override
  String get siteAddressRequired =>
      'لا بد من إدخال عنوان، مثل tree.example.com';

  @override
  String get connect => 'اتّصال';

  @override
  String get connecting => 'جارٍ الاتصال…';

  @override
  String get recentSites => 'المواقع الأخيرة';

  @override
  String get signIn => 'تسجيل دخول';

  @override
  String get signingIn => 'جارٍ تسجيل دخولك…';

  @override
  String get usernameOrEmail => 'إسم المستخدم أو عنوان البريد الإلكتروني';

  @override
  String get usernameRequired => 'أدخل اسم المستخدم أو البريد الإلكتروني.';

  @override
  String get password => 'كلمة المرور';

  @override
  String get passwordRequired => 'أدخل كلمة المرور.';

  @override
  String get showPassword => 'إظهار كلمة المرور';

  @override
  String get hidePassword => 'إخفاء كلمة المرور';

  @override
  String get staySignedIn => 'إبقاء الدخول مسجّلاً';

  @override
  String get rememberUnavailable =>
      'لا يوفّر هذا الجهاز تخزيناً آمناً، لذا لا يمكن حفظ كلمة المرور.';

  @override
  String get rememberUngated =>
      'تُحفظ كلمة المرور في التخزين الآمن لهذا الجهاز. لا يستطيع هذا الجهاز طلب بصمة أو رمز مرور، لذا يمكن لأي شخص يفتح الجهاز أن يدخل باسمك.';

  @override
  String get rememberGated =>
      'تُحفظ كلمة المرور في التخزين الآمن لهذا الجهاز، ولا تُفتح إلا ببصمتك أو وجهك أو رمز المرور.';

  @override
  String get passwordScopeNote =>
      'تُرسل كلمة المرور إلى هذا الموقع وحده، عبر نفس نموذج تسجيل الدخول الذي يستخدمه موقعه.';

  @override
  String get insecureSiteWarning =>
      'لا يستخدم هذا الموقع اتصالاً آمناً. ستُرسل كلمة المرور دون تشفير.';

  @override
  String get degradedServerWarning =>
      'يبلّغ هذا الموقع عن مشكلة بسيطة في إعداد الخادم. من المفترض أن يعمل تسجيل الدخول رغم ذلك.';

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
  String get yourAccess => 'صلاحياتك';

  @override
  String get checkAgain => 'تحقّق مرة أخرى';

  @override
  String get signOut => 'تسجيل خروج';

  @override
  String get more => 'المزيد';

  @override
  String get forgetThisSite => 'نسيان هذا الموقع';

  @override
  String get accessReadFailed => 'حدث خطأ أثناء قراءة صلاحياتك.';

  @override
  String get tryAgain => 'أعد المحاولة';

  @override
  String get familyTrees => 'شجرات العائلة';

  @override
  String get siteAdministrator => 'مدير الموقع';

  @override
  String get roleAdministrator => 'مدير';

  @override
  String get roleManager => 'مشرف';

  @override
  String get roleModerator => 'مراقب';

  @override
  String get roleEditor => 'محرر';

  @override
  String get roleMember => 'عضو';

  @override
  String get roleReadOnly => 'قراءة فقط';

  @override
  String get describeAdministrator =>
      'أنت مدير هذا الموقع، لذا تدير كل شجرة فيه.';

  @override
  String get describeManager => 'يمكنك تغيير هذه الشجرة وإعداداتها.';

  @override
  String get describeModerator =>
      'يمكنك تحرير السجلات والموافقة على تعديلات الآخرين.';

  @override
  String get describeEditor =>
      'يمكنك تحرير السجلات. تنتظر تعديلاتك موافقة مراقب.';

  @override
  String get describeMember =>
      'يمكنك عرض هذه الشجرة، بما فيها الأقارب الأحياء.';

  @override
  String get describeMemberOrVisitor =>
      'يمكنك عرض هذه الشجرة. وهي شجرة عامة، لذا لا يستطيع التطبيق تمييز ما إذا كنت داخلاً كعضو أم تراها كما يراها أي زائر.';

  @override
  String get canEdit => 'إمكانية التحرير';

  @override
  String get canApproveChanges => 'إمكانية اعتماد التعديلات';

  @override
  String get canManage => 'إمكانية الإدارة';

  @override
  String linkedTo(String xref) {
    return 'مرتبط بـ $xref';
  }

  @override
  String get searchForAPerson => 'ابحث عن شخص';

  @override
  String get searchHint => 'اسم، أو رقم سجل مثل I42';

  @override
  String get searchPrompt => 'اكتب اسماً للبحث في شجرة العائلة هذه.';

  @override
  String get searching => 'جارٍ البحث…';

  @override
  String get noMatches =>
      'لم يطابق هذا الاسم أحد. جرّب تهجئة أخرى، أو جزءاً من الاسم.';

  @override
  String get yourAccount => 'حسابك';

  @override
  String get person => 'فرد';

  @override
  String get reload => 'إعادة التحميل';

  @override
  String get personOpenFailed => 'تعذّر فتح هذا الشخص.';

  @override
  String get factsAndEvents => 'معلومات وأحداث';

  @override
  String get parents => 'الوالدان';

  @override
  String get siblings => 'إخوة وأخوات';

  @override
  String get spouses => 'أزواج';

  @override
  String get children => 'أولاد';

  @override
  String get photos => 'صور';

  @override
  String get notes => 'ملاحظات';

  @override
  String get sources => 'مصادر';

  @override
  String get charts => 'مخططات';

  @override
  String get statistics => 'تعداد وإحصائيات';

  @override
  String get statisticsEmpty =>
      'لم ينشر هذا الموقع إحصاءات يستطيع التطبيق قراءتها.';

  @override
  String get chartAncestors => 'أسلاف';

  @override
  String get chartDescendants => 'أنسال';

  @override
  String get chartHourglass => 'ساعة رملية';

  @override
  String get chartRelationship => 'قرابة';

  @override
  String get chartTimeline => 'خط زمني';

  @override
  String get timelineEmpty =>
      'لا توجد أحداث مؤرخة لهذا الشخص لعرضها على خط زمني.';

  @override
  String relationshipPick(String name) {
    return 'قرابة من بـ$name؟';
  }

  @override
  String get relationshipNoLink =>
      'لم يُعثر على صلة بين الشخصين في هذه الشجرة.';

  @override
  String get relationshipChoose => 'اختر شخصاً آخر';

  @override
  String get relationshipBloodOnly =>
      'هذا الموقع يبحث في صلات الدم فقط، فلا تظهر صلة بين شخصين تربطهما مصاهرة.';

  @override
  String get relationshipPaths => 'هناك أكثر من صلة قرابة بينهما.';

  @override
  String get relationshipHow => 'طريقة البحث';

  @override
  String get relationshipWith => 'المقارنة مع';

  @override
  String get relationshipClosest => 'الأقرب';

  @override
  String get relationshipFatherSide => 'من جهة الأب';

  @override
  String get relationshipMotherSide => 'من جهة الأم';

  @override
  String get relationshipThroughSpouse => 'عن طريق الزواج';

  @override
  String get relationshipNoneThisWay => 'لا صلة من هذه الجهة.';

  @override
  String get relationshipBloodOnlyToggle => 'الأقارب بالدم فقط';

  @override
  String get relationshipAnyLink => 'أي صلة';

  @override
  String relationshipSteps(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count خطوة',
      many: '$count خطوة',
      few: '$count خطوات',
      two: 'خطوتان',
      one: 'خطوة واحدة',
    );
    return '$_temp0';
  }

  @override
  String get relationshipOtherWays => 'صلات أخرى بينهما';

  @override
  String get chartView => 'طريقة الرسم';

  @override
  String get chartViewTree => 'شجرة';

  @override
  String get chartViewCircle => 'دائرة';

  @override
  String get chartViewCompact => 'مدمجة';

  @override
  String get chartOptions => 'خيارات الرسم';

  @override
  String get chartGenerations => 'الأجيال';

  @override
  String get chartGenerationsSite => 'كما يضبطها الموقع';

  @override
  String get chartShowPhotos => 'الصور';

  @override
  String get chartShowDates => 'التواريخ';

  @override
  String get chartColourBySex => 'التلوين حسب الجنس';

  @override
  String get chartFitToName => 'اتّساع المربّع للاسم';

  @override
  String get chartWhoToShow => 'من يُعرض';

  @override
  String get chartShowEveryone => 'الجميع';

  @override
  String get chartShowMen => 'خط الذكور';

  @override
  String get chartShowWomen => 'خط الإناث';

  @override
  String get chartLineNote =>
      'يُتتبَّع الخط عبر الأشخاص الذين عليه، فإخفاء أحد الجنسين يُخفي كل من يُوصل إليه عن طريقهم.';

  @override
  String get chartShare => 'مشاركة';

  @override
  String get chartShareImage => 'كصورة';

  @override
  String get chartSharePdf => 'كملف PDF';

  @override
  String get chartSharing => 'جارٍ التحضير…';

  @override
  String get chartShareFailed => 'تعذّر حفظ الرسم.';

  @override
  String chartShareSubject(String name, String chart) {
    return '$name — $chart';
  }

  @override
  String get chartTooBigToShare => 'هذا الرسم أكبر من أن يُحفظ في صورة واحدة.';

  @override
  String get openThisPerson => 'فتح صفحة الشخص';

  @override
  String get chartFromHere => 'ارسم المخطط من هنا';

  @override
  String get chartFailed => 'تعذّر رسم هذا المخطط.';

  @override
  String get chartEmpty => 'لا أحد آخر مسجّل هنا بعد.';

  @override
  String get showMoreResults => 'عرض المزيد';

  @override
  String get eventsOfCloseRelatives => 'أحداث الأقارب';

  @override
  String get deceased => 'متوفّى';

  @override
  String childCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ولد',
      many: '$count ولدًا',
      few: '$count أولاد',
      two: 'ولدان',
      one: 'ولد واحد',
      zero: 'لا أولاد',
    );
    return '$_temp0';
  }

  @override
  String get recordId => 'السجل';

  @override
  String get settings => 'الإعدادات';

  @override
  String get appearance => 'المظهر';

  @override
  String get themeSystem => 'حسب الجهاز';

  @override
  String get themeLight => 'فاتح';

  @override
  String get themeDark => 'داكن';

  @override
  String get language => 'اللغة';

  @override
  String get languageSystem => 'حسب الجهاز';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageArabic => 'العربية';

  @override
  String get languageAffectsSite =>
      'التواريخ وأسماء الشهور وعناوين الأحداث يكتبها موقع webtrees الخاص بك، لذا يطلب التطبيق منه هذه اللغة أيضاً. وهذا يغيّر كذلك اللغة التي يستقبلك بها الموقع.';

  @override
  String get calendar => 'التقويم';

  @override
  String get calendarBoth => 'كلاهما';

  @override
  String get calendarGregorian => 'ميلادي';

  @override
  String get calendarHijri => 'هجري';

  @override
  String get calendarOnlyWhenOffered =>
      'لا يظهر التاريخ بالتقويم الذي تختاره إلا إذا حوّله الموقع. وإلا فسيظهر كما كتبه الموقع.';

  @override
  String get done => 'تم';

  @override
  String errorUnreachableHost(String address, String detail) {
    return 'تعذّر الوصول إلى $address.$detail تحقّق من العنوان ومن اتصالك.';
  }

  @override
  String errorNotWebtrees(String address) {
    return 'استجاب $address، لكنه لا يبدو موقع webtrees. تحقّق من العنوان — ينبغي أن يشير إلى الصفحة التي تسجّل الدخول منها عادة.';
  }

  @override
  String get errorMaintenanceMode =>
      'الموقع متوقف للصيانة. أعد المحاولة لاحقاً.';

  @override
  String get errorServerUnhealthy =>
      'يبلّغ موقع webtrees عن مشكلة في إعداد الخادم ولا يمكنه العمل. على مديره مراجعة لوحة التحكم.';

  @override
  String errorBlockedAsBot(String reason) {
    return 'حجب الموقع هذا التطبيق باعتباره حركة آلية ($reason).';
  }

  @override
  String get errorSignInRejected => 'لم يُقبل اسم المستخدم أو كلمة المرور.';

  @override
  String get errorStaleSignIn =>
      'انتهت صلاحية محاولة تسجيل الدخول. أعد المحاولة.';

  @override
  String get errorSessionExpired => 'انتهت جلستك. سجّل الدخول مرة أخرى.';

  @override
  String get errorNotPermitted => 'لا يملك حسابك صلاحية الوصول إلى هذا.';

  @override
  String get errorNotFound => 'هذا العنصر غير موجود، أو غير ظاهر لك.';

  @override
  String errorUnexpectedResponse(int status) {
    return 'استجاب الموقع بشكل غير متوقع (HTTP $status).';
  }

  @override
  String errorCannotRead(String what) {
    return 'تعذّرت قراءة $what من إصدار webtrees هذا. قد يستخدم سمة أو إصداراً لم يره التطبيق من قبل.';
  }

  @override
  String errorParseFailure(String parser) {
    return 'تعذّرت قراءة $parser في هذا الموقع. قد يستخدم سمة أو إصدار webtrees لم يره التطبيق من قبل.';
  }

  @override
  String noticeSiteRenamedItself(String canonical) {
    return 'يسمّي هذا الموقع نفسه $canonical. سيستخدم التطبيق ذلك العنوان، لأن ملف ارتباط تسجيل الدخول صادر لذلك المضيف.';
  }

  @override
  String noticeBlocklistUnchecked(String reason) {
    return 'تعذّر التحقّق من قائمة الحجب في الموقع: $reason';
  }

  @override
  String get noticeVersionUnreadable => 'تعذّرت قراءة إصدار الموقع.';

  @override
  String get noticeSiteUnidentified =>
      'لم يعرّف هذا الموقع نفسه بأنه webtrees. سيتابع التطبيق، لكن بعض الميزات قد لا تعمل.';

  @override
  String get noticeNoTreesVisible =>
      'لا يرى هذا الحساب أي شجرة عائلة. قد يحتاج مدير الموقع إلى منحه صلاحية الوصول.';

  @override
  String get noticeOnlyOneTreeFound =>
      'لم يُعثر إلا على شجرة عائلة واحدة. إن كان في هذا الموقع أكثر من شجرة، فقد يكون مديره قد أوقف التنقّل بينها.';

  @override
  String get noticeFactsUnavailable =>
      'تعذّر تحميل المعلومات والأحداث لهذا الشخص.';

  @override
  String get noticeRelativesUnavailable =>
      'تعذّر تحميل أفراد العائلة لهذا الشخص.';

  @override
  String get noticeNotesUnavailable => 'تعذّر تحميل الملاحظات لهذا الشخص.';

  @override
  String get noticeSourcesUnavailable => 'تعذّر تحميل المصادر لهذا الشخص.';

  @override
  String get noticeMediaUnavailable => 'تعذّر تحميل الصور لهذا الشخص.';

  @override
  String noticeSectionUnavailable(String module) {
    return 'تعذّر تحميل قسم $module.';
  }

  @override
  String get diagnostics => 'التشخيص';

  @override
  String get diagnosticsWhy =>
      'ما يعرفه التطبيق عن هذا الموقع. يفيد إرفاقه ببلاغ عن خلل: فيه عنوان الموقع واسم المستخدم، وليس فيه كلمة السر.';

  @override
  String get diagnosticsSite => 'الموقع';

  @override
  String get diagnosticsAddress => 'العنوان';

  @override
  String get diagnosticsUrlStyle => 'نمط العناوين';

  @override
  String get diagnosticsUrlPretty => 'مسارات مقروءة';

  @override
  String get diagnosticsUrlQuery => 'سلاسل استعلام';

  @override
  String get diagnosticsSiteVersion => 'إصدار webtrees';

  @override
  String get diagnosticsUnreadable => 'تعذّرت قراءته';

  @override
  String get diagnosticsHealth => 'الخادم';

  @override
  String get diagnosticsHealthOk => 'لا يبلّغ عن أي مشكلة';

  @override
  String get diagnosticsHealthDegraded => 'يبلّغ عن نقص إضافات PHP اختيارية';

  @override
  String get diagnosticsNoSite => 'لم يُحدَّد أي موقع بعد.';

  @override
  String get diagnosticsAccount => 'الحساب';

  @override
  String get diagnosticsSignedInAs => 'مسجَّل الدخول باسم';

  @override
  String get diagnosticsConnection => 'الاتصال';

  @override
  String get diagnosticsStageDisconnected => 'لم يُختَر موقع';

  @override
  String get diagnosticsStageConnecting => 'جارٍ التعرّف على الموقع';

  @override
  String get diagnosticsStageSignedOut => 'الموقع معروف، والدخول غير مسجَّل';

  @override
  String get diagnosticsStageSigningIn => 'جارٍ تسجيل الدخول';

  @override
  String get diagnosticsStageSignedIn => 'الدخول مسجَّل';

  @override
  String get diagnosticsModule => 'وحدة واجهة الجوّال';

  @override
  String get diagnosticsModuleAbsent =>
      'غير مثبَّتة. يُقرأ كل شيء من صفحات الموقع نفسها، وهي الحالة المعتادة وتعمل دائمًا.';

  @override
  String get diagnosticsModuleVersion => 'إصدار الوحدة';

  @override
  String get diagnosticsApiVersion => 'إصدار الواجهة';

  @override
  String get diagnosticsModuleSaysWebtrees => 'إصدار webtrees كما تذكره الوحدة';

  @override
  String get diagnosticsLimits => 'الحدود';

  @override
  String diagnosticsLimitsValue(int page, int generations, int image) {
    return '$page في الصفحة · $generations أجيال · صور بعرض $image بكسل';
  }

  @override
  String get diagnosticsLanguages => 'اللغات التي يكتب بها هذا الموقع';

  @override
  String get diagnosticsReading => 'من أين يُقرأ كل جزء';

  @override
  String get diagnosticsReadingWhy =>
      'تُعتمد الوحدة قدرةً قدرةً، فوحدة أقدم تظل تمنح الطريق السريع لما تجيب عنه.';

  @override
  String get diagnosticsFromModule => 'الوحدة';

  @override
  String get diagnosticsFromPages => 'صفحات الموقع';

  @override
  String get diagnosticsSearch => 'البحث';

  @override
  String get diagnosticsFindings => 'الملاحظات';

  @override
  String get diagnosticsApp => 'التطبيق';

  @override
  String get diagnosticsAppVersion => 'إصدار التطبيق';

  @override
  String get diagnosticsUserAgent => 'معرّف العميل';

  @override
  String get diagnosticsCopy => 'نسخ التقرير';

  @override
  String get diagnosticsCopied => 'نُسخ التقرير';
}
