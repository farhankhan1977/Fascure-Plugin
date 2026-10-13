<?php

require_once dirname(__DIR__) . '/lib/admin.php';

admin_require();
$notice = '';
$error = '';
$fresh = '';

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    admin_check_csrf();
    $action = isset($_POST['action']) ? $_POST['action'] : '';
    try {
        if ($action === 'create') {
            $name = trim($_POST['name']);
            if ($name === '') {
                throw new InvalidArgumentException('Name the token.');
            }
            $total = max(0, (int) $_POST['generation_limit']);
            $limits = array();
            foreach (array('basic', 'standard', 'enterprise') as $plan) {
                $limits[$plan] = max(0, (int) $_POST[$plan . '_limit']);
            }
            if ($limits['basic'] + $limits['standard'] + $limits['enterprise'] < 1) {
                throw new InvalidArgumentException('Allow at least one plan.');
            }
            $plain = 'fsk_' . bin2hex(random_bytes(24));
            $stmt = db()->prepare(
                'INSERT INTO api_tokens (name, token_hash, token_prefix, active, generation_limit, generations_used, basic_limit, standard_limit, enterprise_limit, basic_used, standard_used, enterprise_used, created_at)
                 VALUES (?, ?, ?, 1, ?, 0, ?, ?, ?, 0, 0, 0, NOW())'
            );
            $stmt->execute(array(
                substr($name, 0, 128),
                hash('sha256', $plain),
                substr($plain, 0, 12),
                $total,
                $limits['basic'],
                $limits['standard'],
                $limits['enterprise'],
            ));
            $fresh = $plain;
            $notice = 'Token created. Copy it now. It is not shown again.';
        } elseif ($action === 'disable') {
            $stmt = db()->prepare('UPDATE api_tokens SET active = 0 WHERE id = ?');
            $stmt->execute(array((int) $_POST['id']));
            $notice = 'Token disabled.';
        }
    } catch (Exception $e) {
        $error = $e->getMessage();
    }
}

$rows = db()->query('SELECT * FROM api_tokens ORDER BY id DESC')->fetchAll();
$csrf = h(admin_csrf());
$body = admin_notice($notice, false) . admin_notice($error, true);
if ($fresh !== '') {
    $body .= '<div class="card"><p>API token</p><p><code>' . h($fresh) . '</code></p></div>';
}
$body .= '<div class="card"><h2>New API token</h2><form method="post"><input type="hidden" name="csrf" value="' . $csrf . '"><input type="hidden" name="action" value="create">';
$body .= '<label>Name</label><input name="name" required placeholder="Store server">';
$body .= '<label>Total generations</label><input name="generation_limit" type="number" min="0" value="100"><p>0 means no total cap. Each plan still has its own cap. 0 on a plan means that plan cannot be issued.</p>';
$body .= '<label>Basic limit</label><input name="basic_limit" type="number" min="0" value="100">';
$body .= '<label>Standard limit</label><input name="standard_limit" type="number" min="0" value="20">';
$body .= '<label>Enterprise limit</label><input name="enterprise_limit" type="number" min="0" value="5">';
$body .= '<p><button type="submit">Create token</button></p></form></div>';
$body .= '<div class="card"><h2>Tokens</h2><table><tr><th>Name</th><th>Prefix</th><th>Active</th><th>Used / total</th><th>Basic</th><th>Standard</th><th>Enterprise</th><th></th></tr>';
if (!$rows) {
    $body .= '<tr><td colspan="8">No tokens yet.</td></tr>';
}
foreach ($rows as $row) {
    $total = (int) $row['generation_limit'] === 0 ? 'no cap' : $row['generation_limit'];
    $body .= '<tr><td>' . h($row['name']) . '</td><td><code>' . h($row['token_prefix']) . '</code></td><td>' . ((int) $row['active'] ? 'yes' : 'no') . '</td>';
    $body .= '<td>' . h($row['generations_used']) . ' / ' . h($total) . '</td>';
    $body .= '<td>' . h($row['basic_used']) . ' / ' . h($row['basic_limit']) . '</td>';
    $body .= '<td>' . h($row['standard_used']) . ' / ' . h($row['standard_limit']) . '</td>';
    $body .= '<td>' . h($row['enterprise_used']) . ' / ' . h($row['enterprise_limit']) . '</td><td>';
    if ((int) $row['active']) {
        $body .= '<form method="post"><input type="hidden" name="csrf" value="' . $csrf . '"><input type="hidden" name="action" value="disable"><input type="hidden" name="id" value="' . h($row['id']) . '"><button class="danger" type="submit">Disable</button></form>';
    }
    $body .= '</td></tr>';
}
$body .= '</table></div>';
admin_layout('API tokens', $body);
