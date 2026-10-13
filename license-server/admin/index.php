<?php

require_once dirname(__DIR__) . '/lib/admin.php';
require_once dirname(__DIR__) . '/lib/licenses.php';

admin_require();

$counts = db()->query(
    'SELECT
        SUM(status = "active" AND expires_at >= NOW()) AS active_count,
        SUM(status = "active" AND expires_at < NOW()) AS expired_count,
        SUM(status = "revoked") AS revoked_count
     FROM licenses'
)->fetch();
$tokens = (int) db()->query('SELECT COUNT(*) FROM api_tokens WHERE active = 1')->fetchColumn();
$events = db()->query('SELECT action, ip_address, detail, created_at FROM license_events ORDER BY id DESC LIMIT 12')->fetchAll();

$body = '<div class="card"><p><strong>' . h($counts['active_count'] ?: 0) . '</strong> active licenses, ';
$body .= '<strong>' . h($counts['expired_count'] ?: 0) . '</strong> expired, ';
$body .= '<strong>' . h($counts['revoked_count'] ?: 0) . '</strong> revoked, ';
$body .= '<strong>' . h($tokens) . '</strong> active API tokens.</p>';
$body .= '<p>Plugin servers call <code>/api/verify.php</code> once a day. The calling IP must match the license IP.</p></div>';
$body .= '<div class="card"><h2>Recent checks</h2><table><tr><th>When</th><th>Action</th><th>IP</th><th>Detail</th></tr>';
if (!$events) {
    $body .= '<tr><td colspan="4">No activity yet.</td></tr>';
}
foreach ($events as $event) {
    $body .= '<tr><td>' . h($event['created_at']) . '</td><td>' . h($event['action']) . '</td><td>' . h($event['ip_address']) . '</td><td>' . h($event['detail']) . '</td></tr>';
}
$body .= '</table></div>';
admin_layout('Dashboard', $body);
