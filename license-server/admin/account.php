<?php

require_once dirname(__DIR__) . '/lib/admin.php';

admin_require();
$notice = '';
$error = '';
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    admin_check_csrf();
    $current = isset($_POST['current']) ? (string) $_POST['current'] : '';
    $next = isset($_POST['next']) ? (string) $_POST['next'] : '';
    $stmt = db()->prepare('SELECT * FROM admins WHERE id = ?');
    $stmt->execute(array(admin_user()));
    $admin = $stmt->fetch();
    if (!$admin || !password_verify($current, $admin['password_hash'])) {
        $error = 'Current password is not valid.';
    } elseif (strlen($next) < 10) {
        $error = 'Use at least 10 characters.';
    } else {
        $update = db()->prepare('UPDATE admins SET password_hash = ? WHERE id = ?');
        $update->execute(array(password_hash($next, PASSWORD_DEFAULT), $admin['id']));
        $notice = 'Password updated.';
    }
}
$body = admin_notice($notice, false) . admin_notice($error, true);
$body .= '<div class="card"><form method="post"><input type="hidden" name="csrf" value="' . h(admin_csrf()) . '">';
$body .= '<label>Current password</label><input type="password" name="current" required>';
$body .= '<label>New password</label><input type="password" name="next" required minlength="10">';
$body .= '<p><button type="submit">Update password</button></p></form></div>';
admin_layout('Password', $body);
