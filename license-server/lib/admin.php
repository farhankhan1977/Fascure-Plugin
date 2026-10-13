<?php

require_once __DIR__ . '/db.php';

function admin_start()
{
    if (session_status() !== PHP_SESSION_ACTIVE) {
        session_set_cookie_params(array(
            'httponly' => true,
            'samesite' => 'Lax',
        ));
        session_start();
    }
}

function admin_csrf()
{
    admin_start();
    if (empty($_SESSION['csrf'])) {
        $_SESSION['csrf'] = bin2hex(random_bytes(16));
    }
    return $_SESSION['csrf'];
}

function admin_check_csrf()
{
    admin_start();
    $sent = isset($_POST['csrf']) ? (string) $_POST['csrf'] : '';
    $have = isset($_SESSION['csrf']) ? (string) $_SESSION['csrf'] : '';
    if ($sent === '' || !hash_equals($have, $sent)) {
        http_response_code(400);
        exit('The form expired. Go back and try again.');
    }
}

function admin_user()
{
    admin_start();
    return isset($_SESSION['admin_id']) ? (int) $_SESSION['admin_id'] : 0;
}

function admin_require()
{
    if (!admin_user()) {
        header('Location: login.php');
        exit;
    }
}

function h($value)
{
    return htmlspecialchars((string) $value, ENT_QUOTES, 'UTF-8');
}

function admin_layout($title, $body)
{
    $csrf = admin_csrf();
    echo '<!DOCTYPE html><html lang="en"><head><meta charset="utf-8">';
    echo '<meta name="viewport" content="width=device-width, initial-scale=1">';
    echo '<title>' . h($title) . ' · Fascure Licenses</title>';
    echo '<link rel="stylesheet" href="../assets/admin.css">';
    echo '</head><body>';
    echo '<header class="top"><strong>Fascure License Server</strong><nav>';
    echo '<a href="index.php">Dashboard</a>';
    echo '<a href="licenses.php">Licenses</a>';
    echo '<a href="tokens.php">API tokens</a>';
    echo '<a href="account.php">Password</a>';
    echo '<a href="logout.php">Sign out</a>';
    echo '</nav></header><main>';
    echo '<h1>' . h($title) . '</h1>';
    echo $body;
    echo '</main></body></html>';
}

function admin_notice($text, $bad)
{
    if ($text === '') {
        return '';
    }
    return '<p class="' . ($bad ? 'bad' : 'ok') . '">' . h($text) . '</p>';
}
