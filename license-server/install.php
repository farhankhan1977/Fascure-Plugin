<?php

$root = __DIR__;
$lock = $root . '/installed.lock';
if (is_file($lock)) {
    http_response_code(403);
    exit('This license server is already installed. Remove install.php from the server.');
}

$error = '';
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $host = trim($_POST['db_host']);
    $name = trim($_POST['db_name']);
    $user = trim($_POST['db_user']);
    $pass = (string) $_POST['db_pass'];
    $admin = trim($_POST['admin_user']);
    $adminPass = (string) $_POST['admin_pass'];
    if (!preg_match('/^[A-Za-z0-9._-]{1,64}$/', $name) || $user === '' || $host === '') {
        $error = 'Database name, user, and host are required.';
    } elseif (!preg_match('/^[A-Za-z0-9._-]{3,64}$/', $admin)) {
        $error = 'Admin username must be 3-64 letters, numbers, dots, or hyphens.';
    } elseif (strlen($adminPass) < 10) {
        $error = 'Admin password must be at least 10 characters.';
    } else {
        try {
            $dsn = 'mysql:host=' . $host . ';dbname=' . $name . ';charset=utf8mb4';
            $pdo = new PDO($dsn, $user, $pass, array(PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION));
            $pdo->exec(
                'CREATE TABLE IF NOT EXISTS admins (
                    id INT AUTO_INCREMENT PRIMARY KEY,
                    username VARCHAR(64) NOT NULL UNIQUE,
                    password_hash VARCHAR(255) NOT NULL,
                    created_at DATETIME NOT NULL
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4'
            );
            $pdo->exec(
                'CREATE TABLE IF NOT EXISTS api_tokens (
                    id INT AUTO_INCREMENT PRIMARY KEY,
                    name VARCHAR(128) NOT NULL,
                    token_hash CHAR(64) NOT NULL UNIQUE,
                    token_prefix VARCHAR(16) NOT NULL,
                    active TINYINT NOT NULL DEFAULT 1,
                    generation_limit INT NOT NULL DEFAULT 0,
                    generations_used INT NOT NULL DEFAULT 0,
                    basic_limit INT NOT NULL DEFAULT 0,
                    standard_limit INT NOT NULL DEFAULT 0,
                    enterprise_limit INT NOT NULL DEFAULT 0,
                    basic_used INT NOT NULL DEFAULT 0,
                    standard_used INT NOT NULL DEFAULT 0,
                    enterprise_used INT NOT NULL DEFAULT 0,
                    created_at DATETIME NOT NULL,
                    last_used_at DATETIME NULL
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4'
            );
            $pdo->exec(
                'CREATE TABLE IF NOT EXISTS licenses (
                    id INT AUTO_INCREMENT PRIMARY KEY,
                    license_key VARCHAR(64) NOT NULL UNIQUE,
                    plan ENUM("basic","standard","enterprise") NOT NULL,
                    ip_address VARCHAR(45) NOT NULL,
                    expires_at DATETIME NOT NULL,
                    status ENUM("active","revoked") NOT NULL DEFAULT "active",
                    note VARCHAR(255) NOT NULL DEFAULT "",
                    created_at DATETIME NOT NULL,
                    updated_at DATETIME NOT NULL
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4'
            );
            $pdo->exec(
                'CREATE TABLE IF NOT EXISTS license_events (
                    id INT AUTO_INCREMENT PRIMARY KEY,
                    license_id INT NULL,
                    token_id INT NULL,
                    action VARCHAR(32) NOT NULL,
                    ip_address VARCHAR(45) NOT NULL DEFAULT "",
                    detail VARCHAR(255) NOT NULL DEFAULT "",
                    created_at DATETIME NOT NULL
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4'
            );
            $exists = $pdo->prepare('SELECT id FROM admins WHERE username = ?');
            $exists->execute(array($admin));
            if (!$exists->fetch()) {
                $insert = $pdo->prepare('INSERT INTO admins (username, password_hash, created_at) VALUES (?, ?, NOW())');
                $insert->execute(array($admin, password_hash($adminPass, PASSWORD_DEFAULT)));
            }
            $config = "<?php\nreturn array(\n"
                . "    'db_host' => " . var_export($host, true) . ",\n"
                . "    'db_name' => " . var_export($name, true) . ",\n"
                . "    'db_user' => " . var_export($user, true) . ",\n"
                . "    'db_pass' => " . var_export($pass, true) . ",\n"
                . ");\n";
            if (file_put_contents($root . '/config.php', $config) === false) {
                throw new RuntimeException('Could not write config.php.');
            }
            chmod($root . '/config.php', 0640);
            file_put_contents($lock, date('c') . "\n");
            echo '<!DOCTYPE html><html><head><meta charset="utf-8"><title>Installed</title></head><body>';
            echo '<h1>License server installed</h1>';
            echo '<p>Sign in at <a href="admin/login.php">admin/login.php</a>.</p>';
            echo '<p>Delete install.php from this server now.</p>';
            echo '</body></html>';
            exit;
        } catch (Exception $e) {
            $error = $e->getMessage();
        }
    }
}

echo '<!DOCTYPE html><html><head><meta charset="utf-8"><title>Install Fascure Licenses</title>';
echo '<link rel="stylesheet" href="assets/admin.css"></head><body><main class="login card">';
echo '<h1>Install license server</h1>';
if ($error !== '') {
    echo '<p class="bad">' . htmlspecialchars($error, ENT_QUOTES, 'UTF-8') . '</p>';
}
echo '<form method="post">';
echo '<label>Database host</label><input name="db_host" value="localhost" required>';
echo '<label>Database name</label><input name="db_name" required>';
echo '<label>Database user</label><input name="db_user" required>';
echo '<label>Database password</label><input type="password" name="db_pass">';
echo '<label>Admin username</label><input name="admin_user" required>';
echo '<label>Admin password</label><input type="password" name="admin_pass" required minlength="10">';
echo '<p><button type="submit">Install</button></p></form></main></body></html>';
