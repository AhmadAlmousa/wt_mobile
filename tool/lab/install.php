<?php

/**
 * Installs a lab webtrees from the command line.
 *
 * The setup wizard is six pages of forms, and driving them with curl to get a
 * throwaway database is a lot of moving parts for something the app itself
 * already knows how to do. This calls the same services the wizard calls —
 * `MigrationService`, `UserService`, `TreeService` — which is also what
 * `tests/TestCase.php` does, and is therefore a supported way in.
 *
 * Everything it creates is disposable and public knowledge: the passwords are
 * in this file on purpose, because the instance is a scratch SQLite database
 * on localhost holding an invented family.
 *
 * Usage:  php tool/lab/install.php <webtrees-root> <gedcom-file> <base-url>
 */

declare(strict_types=1);

use Fisharebest\Webtrees\Auth;
use Fisharebest\Webtrees\Contracts\UserInterface;
use Fisharebest\Webtrees\DB;
use Fisharebest\Webtrees\I18N;
use Fisharebest\Webtrees\Registry;
use Fisharebest\Webtrees\Services\GedcomImportService;
use Fisharebest\Webtrees\Services\MigrationService;
use Fisharebest\Webtrees\Services\TreeService;
use Fisharebest\Webtrees\Services\UserService;
use Fisharebest\Webtrees\Site;
use Fisharebest\Webtrees\Webtrees;
use Nyholm\Psr7\Factory\Psr17Factory;

const LAB_ADMIN_USER  = 'admin';
const LAB_ADMIN_PASS  = 'lab-admin-password';
const LAB_MEMBER_USER = 'mobile';
const LAB_MEMBER_PASS = 'lab-member-password';
const LAB_TREE        = 'main';
const LAB_TREE_TITLE  = 'الموسى الصائغ (lab)';
const LAB_DATABASE    = 'lab';
const LAB_PREFIX      = 'wt_';

[$script, $root, $gedcom_file, $base_url] = $argv + [null, null, null, null];

if ($root === null || $gedcom_file === null || $base_url === null) {
    fwrite(STDERR, "Usage: php install.php <webtrees-root> <gedcom-file> <base-url>\n");
    exit(64);
}

$root = rtrim($root, '/') . '/';

require $root . 'vendor/autoload.php';

(new Webtrees())->bootstrap();

// The web server reads these from data/config.ini.php; this process is not
// going through that, so connect the same way by hand.
DB::connect(
    driver: 'sqlite',
    host: '',
    port: '',
    database: LAB_DATABASE,
    username: '',
    password: '',
    prefix: LAB_PREFIX,
    key: '',
    certificate: '',
    ca: '',
    verify_certificate: false,
);

$migrations = Registry::container()->get(MigrationService::class);
$migrations->updateSchema('\Fisharebest\Webtrees\Schema', 'WT_SCHEMA_VERSION', Webtrees::SCHEMA_VERSION);
$migrations->seedDatabase();

say('schema', 'version ' . Webtrees::SCHEMA_VERSION);

Site::setPreference('base_url', $base_url);
// A fresh install nags about this on every admin page otherwise.
Site::setPreference('WELCOME_TEXT_AUTH_MODE', '0');

// After the migrations, not before: 2.2's `I18N::init()` enumerates the
// language *modules*, which means reading the `module` table.
// `TreeService::create()` then asks it for a tag to seed the tree with.
I18N::init('en-GB');

$users = Registry::container()->get(UserService::class);

$admin = $users->create(LAB_ADMIN_USER, 'Lab Administrator', 'admin@lab.invalid', LAB_ADMIN_PASS);
$admin->setPreference(UserInterface::PREF_IS_ADMINISTRATOR, '1');
$admin->setPreference(UserInterface::PREF_IS_EMAIL_VERIFIED, '1');
$admin->setPreference(UserInterface::PREF_IS_ACCOUNT_APPROVED, '1');
$admin->setPreference(UserInterface::PREF_LANGUAGE, 'en-GB');
say('admin', LAB_ADMIN_USER);

// The account the app signs in as. Read-only member, exactly like the
// development account on the real instance.
$member = $users->create(LAB_MEMBER_USER, 'Mobile Client', 'mobile@lab.invalid', LAB_MEMBER_PASS);
$member->setPreference(UserInterface::PREF_IS_EMAIL_VERIFIED, '1');
$member->setPreference(UserInterface::PREF_IS_ACCOUNT_APPROVED, '1');
// Arabic, so the server renders the dates and labels the app was built to read.
$member->setPreference(UserInterface::PREF_LANGUAGE, 'ar');
say('member', LAB_MEMBER_USER);

// Everything below needs a signed-in user: TreeService::create() records the
// contact user, and the import writes change-log rows.
Auth::login($admin);

$tree_service = Registry::container()->get(TreeService::class);
$tree         = $tree_service->create(LAB_TREE, LAB_TREE_TITLE);

// Private, so an anonymous 404 proves membership — the one case where the
// stock transport can distinguish a Member from a Visitor, and therefore the
// case worth reproducing.
//
// Written to the column, not through `setPreference('REQUIRE_AUTHENTICATION')`.
// Schema 45 moved tree privacy out of `gedcom_setting` and into a `private`
// column: 2.2.6 kept a deprecated shim that redirects the write, and 2.3
// removed it — so on 2.3 the preference lands in a table nothing reads and the
// tree stays public. That cost an hour and looked exactly like the module
// leaking a private tree.
DB::table('gedcom')->where('gedcom_id', '=', $tree->id())->update(['private' => 1]);
// Convert to Hijri, so every Gregorian date carries a second calendar and the
// calendar picker has something to pick between.
$tree->setPreference('CALENDAR_FORMAT', 'hijri');
// Blood lines only, as the real instance is set: two people linked by a
// marriage answer "no relationship", which is correct and looks like failure.
$tree->setPreference('RELATIONSHIP_ANCESTORS', '1');
$tree->setPreference('RELATIONSHIP_RECURSION', '3');
$tree->setPreference('SHOW_RELATIVES_EVENTS', 'INDI:BIRT,INDI:DEAT,FAM:MARR');

// 'access' is Role::Member in 2.3 and UserInterface::ROLE_MEMBER in 2.2 — the
// same historic database value in both.
$tree->setUserPreference($member, UserInterface::PREF_TREE_ROLE, 'access');
// The member's own record, which is how relationship privacy and the
// "my page" link both work.
$tree->setUserPreference($member, UserInterface::PREF_TREE_ACCOUNT_XREF, 'X42');
say('tree', LAB_TREE . ' — ' . LAB_TREE_TITLE);

$streams = new Psr17Factory();
$stream  = $streams->createStreamFromFile($gedcom_file, 'rb');

$tree_service->importGedcomFile($tree, $stream, basename($gedcom_file), 'UTF-8');

// `TreeService::importGedcomFile()` only queues the file; the website drains
// the queue from an AJAX loop bounded by a timeout. Here there is no timeout
// and no browser, so drain it in one go — the same `importRecord()` call the
// loop makes.
$importer = Registry::container()->get(GedcomImportService::class);
$records  = 0;
$errors   = [];

while (true) {
    $chunk = DB::table('gedcom_chunk')
        ->where('gedcom_id', '=', $tree->id())
        ->where('imported', '=', '0')
        ->orderBy('gedcom_chunk_id')
        ->select(['gedcom_chunk_id', 'chunk_data'])
        ->first();

    if ($chunk === null) {
        break;
    }

    DB::table('gedcom_chunk')
        ->where('gedcom_chunk_id', '=', $chunk->gedcom_chunk_id)
        ->update(['imported' => 1]);

    foreach (preg_split('/\n+(?=0)/', str_replace("\r", "\n", $chunk->chunk_data)) as $record) {
        try {
            $importer->importRecord($record, $tree, false);
            $records++;
        } catch (Throwable $exception) {
            $errors[] = $exception->getMessage();
        }
    }
}

say('imported', $records . ' record(s)');

foreach ($errors as $error) {
    fwrite(STDERR, '  WARN  ' . strip_tags($error) . "\n");
}

if (!$tree->imported()) {
    fwrite(STDERR, "  FAIL  the tree did not finish importing — no trailer record?\n");
    exit(1);
}

say('counts', sprintf(
    '%d individuals, %d families, %d sources, %d media',
    DB::table('individuals')->where('i_file', '=', $tree->id())->count(),
    DB::table('families')->where('f_file', '=', $tree->id())->count(),
    DB::table('sources')->where('s_file', '=', $tree->id())->count(),
    DB::table('media')->where('m_file', '=', $tree->id())->count(),
));

function say(string $label, string $value): void
{
    printf("  %-10s %s\n", $label, $value);
}
