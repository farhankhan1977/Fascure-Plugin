<?php

require_once dirname(__DIR__) . '/lib/admin.php';
require_once dirname(__DIR__) . '/lib/licenses.php';

admin_require();
$notice = '';
$error = '';

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    admin_check_csrf();
    $action = isset($_POST['action']) ? $_POST['action'] : '';
    try {
        if ($action === 'create') {
            $expires = trim($_POST['expires_at'] . ' 23:59:59');
            $row = create_license($_POST['plan'], trim($_POST['ip']), $expires, isset($_POST['note']) ? $_POST['note'] : '');
            record_event($row['id'], null, 'admin_create', $row['ip_address'], $row['plan']);
            $notice = 'Created ' . $row['license_key'];
        } elseif ($action === 'renew') {
            $ip = trim($_POST['ip']);
            $expires = trim($_POST['expires_at'] . ' 23:59:59');
            $row = renew_license(strtoupper(trim($_POST['license_key'])), $ip, $expires);
            record_event($row['id'], null, 'admin_renew', $row['ip_address'], $row['plan']);
            $notice = 'Renewed ' . $row['license_key'];
        } elseif ($action === 'revoke') {
            $stmt = db()->prepare('UPDATE licenses SET status = "revoked", updated_at = NOW() WHERE license_key = ? AND status <> "revoked"');
            $stmt->execute(array(strtoupper(trim($_POST['license_key']))));
            $notice = 'Revoked ' . strtoupper(trim($_POST['license_key']));
        }
    } catch (Exception $e) {
        $error = $e->getMessage();
    }
}

$rows = db()->query('SELECT * FROM licenses ORDER BY id DESC')->fetchAll();
$csrf = h(admin_csrf());
$body = admin_notice($notice, false) . admin_notice($error, true);
$body .= '<div class="card"><h2>New license</h2><form method="post">';
$body .= '<input type="hidden" name="csrf" value="' . $csrf . '"><input type="hidden" name="action" value="create">';
$body .= '<label>Plan</label><select name="plan"><option value="basic">Basic · 1 account · 1 app</option><option value="standard">Standard · 10 accounts · 3 apps each</option><option value="enterprise">Enterprise · unlimited</option></select>';
$body .= '<label>Server IP</label><input name="ip" required placeholder="46.151.210.123">';
$body .= '<label>Expires</label><input type="date" name="expires_at" required>';
$body .= '<label>Note</label><input name="note">';
$body .= '<p><button type="submit">Create license</button></p></form></div>';
$body .= '<div class="card"><h2>Issued licenses</h2><table><tr><th>Key</th><th>Plan</th><th>IP</th><th>Expires</th><th>Status</th><th></th></tr>';
if (!$rows) {
    $body .= '<tr><td colspan="6">No licenses yet.</td></tr>';
}
foreach ($rows as $row) {
    $state = $row['status'] === 'revoked' ? 'revoked' : (strtotime($row['expires_at']) < time() ? 'expired' : 'active');
    $planLabel = $row['plan'] . ($row['note'] === 'free' ? ' (free)' : '');
    $body .= '<tr><td><code>' . h($row['license_key']) . '</code></td><td>' . h($planLabel) . '</td><td>' . h($row['ip_address']) . '</td><td>' . h($row['expires_at']) . '</td><td>' . h($state) . '</td><td>';
    if ($state !== 'revoked') {
        $body .= '<form method="post"><input type="hidden" name="csrf" value="' . $csrf . '"><input type="hidden" name="action" value="renew"><input type="hidden" name="license_key" value="' . h($row['license_key']) . '">';
        $body .= '<input name="ip" value="' . h($row['ip_address']) . '" style="max-width:150px"> ';
        $body .= '<input type="date" name="expires_at" required style="max-width:150px"> ';
        $body .= '<button type="submit">Renew</button></form>';
        $body .= '<form method="post" onsubmit="return confirm(\'Revoke this license?\')"><input type="hidden" name="csrf" value="' . $csrf . '"><input type="hidden" name="action" value="revoke"><input type="hidden" name="license_key" value="' . h($row['license_key']) . '"><button class="danger" type="submit">Revoke</button></form>';
    }
    $body .= '</td></tr>';
}
$body .= '</table></div>';
admin_layout('Licenses', $body);
