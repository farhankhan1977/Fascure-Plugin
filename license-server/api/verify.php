<?php

require_once dirname(__DIR__) . '/lib/licenses.php';

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    json_out(405, array('ok' => false, 'message' => 'POST a license key.'));
}

$body = read_json_body();
if ($body === null) {
    json_out(400, array('ok' => false, 'message' => 'Send a JSON body.'));
}

$key = isset($body['license_key']) ? strtoupper(trim((string) $body['license_key'])) : '';
if (!preg_match('/^FSCP-[A-Z2-9]{4}-[A-Z2-9]{4}-[A-Z2-9]{4}-[A-Z2-9]{4}$/', $key)) {
    json_out(400, array('ok' => false, 'status' => 'unknown', 'message' => 'License key is not valid.'));
}

$seen = client_ip();
$row = find_license($key);
if (!$row) {
    record_event(null, null, 'verify_unknown', $seen, $key);
    json_out(404, array(
        'ok' => false,
        'status' => 'unknown',
        'seen_ip' => $seen,
        'message' => 'Unknown license key.',
    ));
}

$result = license_public_row($row, $seen);
record_event($row['id'], null, 'verify_' . $result['status'], $seen, $result['message']);
json_out($result['ok'] ? 200 : 403, $result);
