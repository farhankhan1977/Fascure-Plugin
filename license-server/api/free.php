<?php

require_once dirname(__DIR__) . '/lib/licenses.php';

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    json_out(405, array('ok' => false, 'message' => 'POST to request a free license.'));
}

try {
    $result = issue_free_license(client_ip());
    json_out($result['action'] === 'generate' ? 201 : 200, $result);
} catch (InvalidArgumentException $e) {
    json_out(400, array('ok' => false, 'message' => $e->getMessage()));
} catch (Exception $e) {
    json_out(500, array('ok' => false, 'message' => 'Could not issue a free license.'));
}
