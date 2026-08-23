<?php

/**
 * webtrees-mobile-api: a purpose-built read-only JSON API for webtrees_mobile.
 *
 * Copy or symlink this directory into a webtrees installation's `modules_v4/`
 * and enable it in the control panel.
 */

declare(strict_types=1);

require_once __DIR__ . '/autoload.php';

return new WebtreesMobileApi\WebtreesMobileApi();
