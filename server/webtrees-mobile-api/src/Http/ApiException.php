<?php

declare(strict_types=1);

namespace WebtreesMobileApi\Http;

use RuntimeException;

/**
 * A failure with a status code and a machine-readable name.
 *
 * Thrown anywhere below a handler; `JsonErrors` turns it into the one error
 * shape every endpoint answers with. Everything else that escapes a handler
 * becomes a 500 with no detail, because an exception message can carry
 * database structure or file paths and this is a public interface.
 */
final class ApiException extends RuntimeException
{
    private function __construct(
        public readonly int $status,
        public readonly string $error,
        string $message,
        public readonly string|null $detail = null,
    ) {
        parent::__construct($message);
    }

    public static function invalidParameter(string $message, string|null $detail = null): self
    {
        return new self(400, 'invalid_parameter', $message, $detail);
    }

    public static function notSignedIn(): self
    {
        return new self(401, 'not_signed_in', 'You are not signed in.');
    }

    public static function forbidden(string $message): self
    {
        return new self(403, 'forbidden', $message);
    }

    public static function notFound(string $message): self
    {
        return new self(404, 'not_found', $message);
    }

    public static function serverError(string $message): self
    {
        return new self(500, 'server_error', $message);
    }
}
