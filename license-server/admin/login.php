<?php

require_once dirname(__DIR__) . '/lib/admin.php';

admin_start();
if (admin_user()) {
    header('Location: index.php');
    exit;
}

$error = '';
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    admin_check_csrf();
    $fails = isset($_SESSION['login_fails']) ? (int) $_SESSION['login_fails'] : 0;
    $lockedUntil = isset($_SESSION['login_locked']) ? (int) $_SESSION['login_locked'] : 0;
    if ($lockedUntil > time()) {
        $error = 'Too many sign-in attempts. Wait a few minutes.';
    } else {
        $username = isset($_POST['username']) ? trim($_POST['username']) : '';
        $password = isset($_POST['password']) ? (string) $_POST['password'] : '';
        $stmt = db()->prepare('SELECT * FROM admins WHERE username = ? LIMIT 1');
        $stmt->execute(array($username));
        $admin = $stmt->fetch();
        if ($admin && password_verify($password, $admin['password_hash'])) {
            session_regenerate_id(true);
            $_SESSION['admin_id'] = (int) $admin['id'];
            unset($_SESSION['login_fails'], $_SESSION['login_locked']);
            header('Location: index.php');
            exit;
        }
        $fails++;
        $_SESSION['login_fails'] = $fails;
        if ($fails >= 5) {
            $_SESSION['login_locked'] = time() + 600;
        }
        $error = 'Username or password is not valid.';
    }
}

echo '<!DOCTYPE html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">';
echo '<title>Sign in · Fascure Licenses</title><link rel="stylesheet" href="../assets/admin.css"></head><body>';
echo '<main class="login card"><h1>Fascure Licenses</h1>';
echo admin_notice($error, true);
echo '<form method="post"><input type="hidden" name="csrf" value="' . h(admin_csrf()) . '">';
echo '<label>Username</label><input name="username" required autocomplete="username">';
echo '<label>Password</label><input type="password" name="password" required autocomplete="current-password">';
echo '<p><button type="submit">Sign in</button></p></form></main></body></html>';
