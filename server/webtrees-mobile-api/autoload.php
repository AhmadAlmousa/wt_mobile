<?php

/**
 * PSR-4 autoloader for this module's namespace only.
 *
 * Deliberately hand-written: the module vendors nothing, so there is no
 * composer autoloader to include and nothing here can collide with the
 * classes in webtrees' own vendor tree.
 */

declare(strict_types=1);

spl_autoload_register(static function (string $class): void {
    $prefix = 'WebtreesMobileApi\\';
    $length = strlen($prefix);

    if (strncmp($prefix, $class, $length) !== 0) {
        return;
    }

    $relative = substr($class, $length);
    $file     = __DIR__ . '/src/' . str_replace('\\', '/', $relative) . '.php';

    if (is_file($file)) {
        require $file;
    }
});
