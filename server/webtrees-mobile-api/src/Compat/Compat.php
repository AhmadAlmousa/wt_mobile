<?php

declare(strict_types=1);

namespace WebtreesMobileApi\Compat;

use function class_exists;

/**
 * Chooses the adapter for the webtrees this module is running inside.
 *
 * Detection is by feature, not by version string. `Webtrees::VERSION` is a
 * marketing number that a distribution can patch; the presence of the class
 * that replaced the Aura router is the actual fact the adapter turns on.
 */
final class Compat
{
    private static CompatInterface|null $instance = null;

    /**
     * The adapter for this installation.
     */
    public static function current(): CompatInterface
    {
        return self::$instance ??= self::detect();
    }

    /**
     * Override the adapter. For tests only.
     */
    public static function use(CompatInterface|null $compat): void
    {
        self::$instance = $compat;
    }

    private static function detect(): CompatInterface
    {
        if (class_exists('Fisharebest\Webtrees\Http\Routing\RouteCollection')) {
            return new Compat23();
        }

        return new Compat22();
    }
}
