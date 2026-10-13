<?php

function app_config()
{
    static $config = null;
    if ($config === null) {
        $path = dirname(__DIR__) . '/config.php';
        if (!is_file($path)) {
            throw new RuntimeException('config.php is missing. Open install.php first.');
        }
        $config = require $path;
    }
    return $config;
}

function db()
{
    static $pdo = null;
    if ($pdo instanceof PDO) {
        return $pdo;
    }
    $c = app_config();
    $dsn = 'mysql:host=' . $c['db_host'] . ';dbname=' . $c['db_name'] . ';charset=utf8mb4';
    $pdo = new PDO($dsn, $c['db_user'], $c['db_pass'], array(
        PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
    ));
    return $pdo;
}

function json_out($code, $payload)
{
    http_response_code($code);
    header('Content-Type: application/json; charset=utf-8');
    echo json_encode($payload);
    exit;
}

function read_json_body()
{
    $raw = file_get_contents('php://input');
    if ($raw === false || trim($raw) === '') {
        return array();
    }
    $data = json_decode($raw, true);
    return is_array($data) ? $data : null;
}

function record_event($licenseId, $tokenId, $action, $ip, $detail)
{
    $stmt = db()->prepare(
        'INSERT INTO license_events (license_id, token_id, action, ip_address, detail, created_at)
         VALUES (?, ?, ?, ?, ?, NOW())'
    );
    $stmt->execute(array(
        $licenseId ? (int) $licenseId : null,
        $tokenId ? (int) $tokenId : null,
        $action,
        substr((string) $ip, 0, 45),
        substr((string) $detail, 0, 255),
    ));
}
