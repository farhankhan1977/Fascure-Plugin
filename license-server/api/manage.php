<?php

require_once dirname(__DIR__) . '/lib/licenses.php';

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    json_out(405, array('ok' => false, 'message' => 'POST a JSON body.'));
}

$token = authenticate_api_token();
$body = read_json_body();
if ($body === null) {
    json_out(400, array('ok' => false, 'message' => 'Send a JSON body.'));
}

$action = isset($body['action']) ? $body['action'] : '';
$ip = isset($body['ip']) ? trim((string) $body['ip']) : '';
$expires = '';
if (!empty($body['expires_at'])) {
    $expires = trim((string) $body['expires_at']);
} elseif (isset($body['days'])) {
    $days = (int) $body['days'];
    if ($days < 1 || $days > 3650) {
        json_out(400, array('ok' => false, 'message' => 'Days must be between 1 and 3650.'));
    }
    $expires = date('Y-m-d H:i:s', time() + ($days * 86400));
}

try {
    if ($action === 'generate') {
        $plan = isset($body['plan']) ? strtolower(trim((string) $body['plan'])) : '';
        assert_token_can_issue($token, $plan);
        if ($expires === '') {
            throw new InvalidArgumentException('Set expires_at or days.');
        }
        $pdo = db();
        $pdo->beginTransaction();
        consume_token($token, $plan);
        $note = isset($body['note']) ? (string) $body['note'] : '';
        $row = create_license($plan, $ip, $expires, $note);
        record_event($row['id'], $token['id'], 'generate', $ip, $plan);
        $pdo->commit();
        $public = license_public_row($row, $row['ip_address']);
        json_out(201, array(
            'ok' => true,
            'action' => 'generate',
            'license_key' => $row['license_key'],
            'plan' => $public['plan'],
            'plan_label' => $public['plan_label'],
            'tenants' => $public['tenants'],
            'apps' => $public['apps'],
            'ip' => $row['ip_address'],
            'expires_at' => $row['expires_at'],
            'message' => 'License created.',
        ));
    }

    if ($action === 'renew') {
        $key = isset($body['license_key']) ? strtoupper(trim((string) $body['license_key'])) : '';
        $existing = find_license($key);
        if (!$existing) {
            throw new InvalidArgumentException('Unknown license key.');
        }
        $plan = $existing['plan'];
        if ($ip === '') {
            $ip = $existing['ip_address'];
        }
        assert_token_can_issue($token, $plan);
        if ($expires === '') {
            throw new InvalidArgumentException('Set expires_at or days.');
        }
        $pdo = db();
        $pdo->beginTransaction();
        consume_token($token, $plan);
        $row = renew_license($key, $ip, $expires);
        record_event($row['id'], $token['id'], 'renew', $ip, $plan);
        $pdo->commit();
        $public = license_public_row($row, $row['ip_address']);
        json_out(200, array(
            'ok' => true,
            'action' => 'renew',
            'license_key' => $row['license_key'],
            'plan' => $public['plan'],
            'plan_label' => $public['plan_label'],
            'tenants' => $public['tenants'],
            'apps' => $public['apps'],
            'ip' => $row['ip_address'],
            'expires_at' => $row['expires_at'],
            'message' => 'License renewed.',
        ));
    }

    json_out(400, array('ok' => false, 'message' => 'Action must be generate or renew.'));
} catch (InvalidArgumentException $e) {
    if (db()->inTransaction()) {
        db()->rollBack();
    }
    json_out(400, array('ok' => false, 'message' => $e->getMessage()));
} catch (Exception $e) {
    if (db()->inTransaction()) {
        db()->rollBack();
    }
    json_out(500, array('ok' => false, 'message' => 'Could not update the license.'));
}
