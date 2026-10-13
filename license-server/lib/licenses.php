<?php

require_once __DIR__ . '/plans.php';
require_once __DIR__ . '/db.php';

function license_public_row($row, $seenIp)
{
    $plan = plan_spec($row['plan']);
    $expired = strtotime($row['expires_at']) < time();
    if ($row['status'] === 'revoked') {
        $status = 'revoked';
    } elseif ($expired) {
        $status = 'expired';
    } elseif ($seenIp !== '' && $seenIp !== $row['ip_address']) {
        $status = 'wrong_ip';
    } else {
        $status = 'active';
    }
    $ok = $status === 'active';
    $messages = array(
        'active' => 'License is valid for ' . $row['ip_address'] . '.',
        'expired' => 'This license expired on ' . $row['expires_at'] . '.',
        'revoked' => 'This license has been revoked.',
        'wrong_ip' => 'This license is assigned to ' . $row['ip_address'] . ', not ' . $seenIp . '.',
    );
    return array(
        'ok' => $ok,
        'status' => $status,
        'plan' => $plan['id'],
        'plan_label' => $plan['label'],
        'tenants' => $plan['tenants'],
        'apps' => $plan['apps'],
        'ip' => $row['ip_address'],
        'seen_ip' => $seenIp,
        'expires_at' => $row['expires_at'],
        'license_key' => $row['license_key'],
        'message' => $messages[$status],
    );
}

function find_license($key)
{
    $stmt = db()->prepare('SELECT * FROM licenses WHERE license_key = ? LIMIT 1');
    $stmt->execute(array($key));
    $row = $stmt->fetch();
    return $row ? $row : null;
}

function create_license($plan, $ip, $expiresAt, $note)
{
    $spec = plan_spec($plan);
    if (!$spec) {
        throw new InvalidArgumentException('Plan must be basic, standard, or enterprise.');
    }
    if (!valid_ip($ip)) {
        throw new InvalidArgumentException('IP address is not valid.');
    }
    $when = strtotime($expiresAt);
    if ($when === false || $when <= time()) {
        throw new InvalidArgumentException('Expiry must be a future date.');
    }
    $expires = gmdate('Y-m-d H:i:s', $when);
    for ($try = 0; $try < 5; $try++) {
        $key = new_license_key();
        try {
            $stmt = db()->prepare(
                'INSERT INTO licenses (license_key, plan, ip_address, expires_at, status, note, created_at, updated_at)
                 VALUES (?, ?, ?, ?, "active", ?, NOW(), NOW())'
            );
            $stmt->execute(array($key, $spec['id'], $ip, $expires, substr($note, 0, 255)));
            return find_license($key);
        } catch (PDOException $e) {
            if ((int) $e->errorInfo[1] !== 1062) {
                throw $e;
            }
        }
    }
    throw new RuntimeException('Could not allocate a license key.');
}

function renew_license($key, $ip, $expiresAt)
{
    $row = find_license($key);
    if (!$row) {
        throw new InvalidArgumentException('Unknown license key.');
    }
    if ($row['status'] === 'revoked') {
        throw new InvalidArgumentException('This license has been revoked.');
    }
    if (!valid_ip($ip)) {
        throw new InvalidArgumentException('IP address is not valid.');
    }
    $when = strtotime($expiresAt);
    if ($when === false || $when <= time()) {
        throw new InvalidArgumentException('Expiry must be a future date.');
    }
    $expires = gmdate('Y-m-d H:i:s', $when);
    $stmt = db()->prepare(
        'UPDATE licenses SET ip_address = ?, expires_at = ?, status = "active", updated_at = NOW() WHERE id = ?'
    );
    $stmt->execute(array($ip, $expires, $row['id']));
    return find_license($key);
}

function bearer_token()
{
    $header = '';
    if (isset($_SERVER['HTTP_AUTHORIZATION'])) {
        $header = $_SERVER['HTTP_AUTHORIZATION'];
    } elseif (isset($_SERVER['REDIRECT_HTTP_AUTHORIZATION'])) {
        $header = $_SERVER['REDIRECT_HTTP_AUTHORIZATION'];
    }
    if (stripos($header, 'Bearer ') !== 0) {
        return '';
    }
    return trim(substr($header, 7));
}

function authenticate_api_token()
{
    $plain = bearer_token();
    if ($plain === '' || strlen($plain) < 20) {
        json_out(401, array('ok' => false, 'message' => 'API token is required.'));
    }
    $hash = hash('sha256', $plain);
    $stmt = db()->prepare('SELECT * FROM api_tokens WHERE token_hash = ? LIMIT 1');
    $stmt->execute(array($hash));
    $token = $stmt->fetch();
    if (!$token || !(int) $token['active']) {
        json_out(401, array('ok' => false, 'message' => 'API token is not valid.'));
    }
    return $token;
}

function assert_token_can_issue($token, $plan)
{
    if (!plan_spec($plan)) {
        throw new InvalidArgumentException('Plan must be basic, standard, or enterprise.');
    }
    $limit = (int) $token[$plan . '_limit'];
    $used = (int) $token[$plan . '_used'];
    if ($limit < 1 || $used >= $limit) {
        throw new InvalidArgumentException('This API token cannot issue more ' . $plan . ' licenses.');
    }
    $cap = (int) $token['generation_limit'];
    if ($cap > 0 && (int) $token['generations_used'] >= $cap) {
        throw new InvalidArgumentException('This API token has reached its generation limit.');
    }
}

function consume_token($token, $plan)
{
    if (!in_array($plan, array('basic', 'standard', 'enterprise'), true)) {
        throw new InvalidArgumentException('Plan must be basic, standard, or enterprise.');
    }
    $stmt = db()->prepare(
        'UPDATE api_tokens
         SET generations_used = generations_used + 1, ' . $plan . '_used = ' . $plan . '_used + 1, last_used_at = NOW()
         WHERE id = ? AND active = 1
           AND ' . $plan . '_used < ' . $plan . '_limit
           AND (generation_limit = 0 OR generations_used < generation_limit)'
    );
    $stmt->execute(array((int) $token['id']));
    if ($stmt->rowCount() !== 1) {
        throw new InvalidArgumentException('This API token has reached its generation limit.');
    }
}
