<?php
require_once '/usr/local/cpanel/php/cpanel.php';

$cpanel = new CPANEL();
print $cpanel->header('Fascure Node.js App');

function h($value)
{
    return htmlspecialchars((string) $value, ENT_QUOTES, 'UTF-8');
}

function call_uapi($cpanel, $func, $params = array())
{
    $raw = $cpanel->uapi('NodeApp', $func, $params);
    $result = array();
    if (isset($raw['cpanelresult']['result'])) {
        $result = $raw['cpanelresult']['result'];
    } elseif (isset($raw['result'])) {
        $result = $raw['result'];
    }
    $status = !empty($result['status']);
    $errors = array();
    if (!empty($result['errors'])) {
        $errors = is_array($result['errors']) ? $result['errors'] : array($result['errors']);
    }
    return array($status, isset($result['data']) ? $result['data'] : null, $errors);
}

function env_from_post($text)
{
    $env = array();
    foreach (preg_split("/\r\n|\n|\r/", (string) $text) as $line) {
        $line = trim($line);
        if ($line === '' || strpos($line, '=') === false) {
            continue;
        }
        list($key, $value) = explode('=', $line, 2);
        $key = trim($key);
        if ($key !== '') {
            $env[$key] = $value;
        }
    }
    $json = json_encode($env, JSON_FORCE_OBJECT);
    return ($json === false || $json === '[]') ? '{}' : $json;
}

function env_to_text($env)
{
    if (!is_array($env)) {
        return '';
    }
    $lines = array();
    foreach ($env as $key => $value) {
        if ($key === 'NODE_ENV' || $key === 'NODEAPPS_STARTUP') {
            continue;
        }
        $lines[] = $key . '=' . $value;
    }
    return implode("\n", $lines);
}

$notice = '';
$error = '';
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $action = isset($_POST['action']) ? $_POST['action'] : '';
    $params = array();
    if ($action === 'create') {
        $params = array(
            'id' => isset($_POST['id']) ? $_POST['id'] : '',
            'type' => isset($_POST['type']) ? $_POST['type'] : 'nodejs',
            'mode' => isset($_POST['mode']) ? $_POST['mode'] : 'production',
            'root' => isset($_POST['root']) ? $_POST['root'] : '',
            'domain' => isset($_POST['domain']) ? $_POST['domain'] : '',
            'uri' => isset($_POST['uri']) ? $_POST['uri'] : '/',
            'startup' => isset($_POST['startup']) ? $_POST['startup'] : '',
            'version' => isset($_POST['version']) ? $_POST['version'] : '',
            'env_json' => env_from_post(isset($_POST['env']) ? $_POST['env'] : ''),
            'scaffold' => empty($_POST['scaffold']) ? 0 : 1,
        );
        list($ok, $data, $errors) = call_uapi($cpanel, 'create_app', $params);
    } elseif ($action === 'update') {
        $params = array(
            'id' => isset($_POST['id']) ? $_POST['id'] : '',
            'mode' => isset($_POST['mode']) ? $_POST['mode'] : '',
            'domain' => isset($_POST['domain']) ? $_POST['domain'] : '',
            'uri' => isset($_POST['uri']) ? $_POST['uri'] : '/',
            'startup' => isset($_POST['startup']) ? $_POST['startup'] : '',
            'version' => isset($_POST['version']) ? $_POST['version'] : '',
            'env_json' => env_from_post(isset($_POST['env']) ? $_POST['env'] : ''),
        );
        list($ok, $data, $errors) = call_uapi($cpanel, 'update_app', $params);
    } elseif ($action === 'npm') {
        list($ok, $data, $errors) = call_uapi($cpanel, 'run_npm_install', array('id' => $_POST['id']));
    } elseif ($action === 'build') {
        list($ok, $data, $errors) = call_uapi($cpanel, 'run_next_build', array('id' => $_POST['id']));
    } elseif ($action === 'script') {
        list($ok, $data, $errors) = call_uapi($cpanel, 'run_script', array(
            'id' => $_POST['id'],
            'script' => isset($_POST['script']) ? $_POST['script'] : '',
        ));
    } elseif ($action === 'restart') {
        list($ok, $data, $errors) = call_uapi($cpanel, 'restart_app', array('id' => $_POST['id']));
    } elseif ($action === 'stop') {
        list($ok, $data, $errors) = call_uapi($cpanel, 'set_enabled', array('id' => $_POST['id'], 'enabled' => 0));
    } elseif ($action === 'start') {
        list($ok, $data, $errors) = call_uapi($cpanel, 'set_enabled', array('id' => $_POST['id'], 'enabled' => 1));
    } elseif ($action === 'delete') {
        list($ok, $data, $errors) = call_uapi($cpanel, 'delete_app', array(
            'id' => $_POST['id'],
            'remove_files' => empty($_POST['remove_files']) ? 0 : 1,
        ));
    } else {
        $ok = false;
        $errors = array('Unknown action.');
    }
    if (!empty($ok)) {
        $notice = 'Saved.';
    } else {
        $error = $errors ? implode(' ', $errors) : 'The request failed.';
    }
}

list($versions_ok, $version_data, $version_errors) = call_uapi($cpanel, 'list_versions');
list($domains_ok, $domains, $domain_errors) = call_uapi($cpanel, 'list_domains');
list($apps_ok, $apps, $app_errors) = call_uapi($cpanel, 'list_apps');
list($status_ok, $status, $status_errors) = call_uapi($cpanel, 'system_status');

$versions = (is_array($version_data) && isset($version_data['versions'])) ? $version_data['versions'] : array();
$default_version = (is_array($version_data) && isset($version_data['default_version'])) ? $version_data['default_version'] : '';
if (!is_array($domains)) {
    $domains = array();
}
if (!is_array($apps)) {
    $apps = array();
}
if (!$apps_ok && $error === '' && $app_errors) {
    $error = implode(' ', $app_errors);
}

$licensed = is_array($status) && !empty($status['licensed']);
$apps_used = (is_array($status) && isset($status['apps_used'])) ? (int) $status['apps_used'] : 0;
$app_limit = (is_array($status) && isset($status['apps'])) ? (int) $status['apps'] : 0;
$plan_label = (is_array($status) && !empty($status['plan_label'])) ? $status['plan_label'] : '';
$expires = (is_array($status) && !empty($status['license_expires'])) ? $status['license_expires'] : '';
if ($licensed) {
    if ($app_limit > 0) {
        $license_message = $plan_label . ' plan. This account can create ' . $app_limit . ' application' . ($app_limit === 1 ? '' : 's') . '. Using ' . $apps_used . ' of ' . $app_limit . '.';
    } else {
        $license_message = $plan_label . ' plan. This account can create unlimited applications. Using ' . $apps_used . '.';
    }
    if ($expires !== '') {
        $license_message .= ' Expires ' . $expires . '.';
    }
} else {
    $license_message = (is_array($status) && !empty($status['license_message']))
        ? $status['license_message']
        : 'Fascure Node.js App is limited until a license key is entered in WHM.';
}
$running = false;
foreach ($apps as $app) {
    if (!empty($app['job']['running'])) {
        $running = true;
    }
}
?>
<style>
.nodeapps { font-size: 14px; color: #1f2933; }
.nodeapps h2 { margin: 0 0 12px; font-size: 20px; }
.nodeapps h3 { margin: 0 0 12px; font-size: 16px; }
.nodeapps .banner { padding: 10px 12px; border-radius: 6px; margin-bottom: 12px; }
.nodeapps .ok { background: #e8f5e9; color: #1b5e20; }
.nodeapps .bad { background: #fdecea; color: #8a1f11; }
.nodeapps .card { background: #fff; border: 1px solid #d5dde5; border-radius: 8px; padding: 16px; margin-bottom: 16px; }
.nodeapps label { display: block; font-weight: 600; margin: 10px 0 4px; }
.nodeapps input[type=text], .nodeapps select, .nodeapps textarea { width: 100%; max-width: 520px; box-sizing: border-box; padding: 7px 8px; border: 1px solid #b7c3ce; border-radius: 4px; }
.nodeapps textarea { min-height: 90px; font-family: Consolas, monospace; }
.nodeapps .row { display: flex; gap: 8px; flex-wrap: wrap; align-items: center; margin-top: 8px; }
.nodeapps button, .nodeapps .btn { background: #1b5e20; color: #fff; border: 0; border-radius: 4px; padding: 7px 12px; cursor: pointer; }
.nodeapps .secondary { background: #455a64; }
.nodeapps .danger { background: #b71c1c; }
.nodeapps .muted { color: #52606d; font-size: 13px; }
.nodeapps code, .nodeapps pre { background: #f4f7f6; border-radius: 4px; padding: 2px 4px; }
.nodeapps pre { padding: 10px; overflow: auto; max-height: 220px; }
.nodeapps table { width: 100%; border-collapse: collapse; }
.nodeapps td { padding: 4px 0; vertical-align: top; }
</style>
<div class="nodeapps">
<?php if ($running) { ?>
<meta http-equiv="refresh" content="8">
<?php } ?>
<h2>Fascure Node.js App</h2>
<p class="muted">Create a Node.js or Next.js application, choose the Node.js version, and run it with Passenger. The application must listen on <code>process.env.PORT</code>.</p>
<?php if ($notice !== '') { ?><div class="banner ok"><?php print h($notice); ?></div><?php } ?>
<?php if ($error !== '') { ?><div class="banner bad"><?php print h($error); ?></div><?php } ?>
<?php if (!$licensed) { ?>
<div class="banner bad"><?php print h($license_message); ?> Application changes stay turned off until the server administrator saves a valid key. Purchase a license at <a href="https://fascure-hosting.com" target="_blank" rel="noopener">https://fascure-hosting.com</a>.</div>
<?php } else { ?>
<div class="banner ok"><?php print h($license_message); ?> Purchase or renew at <a href="https://fascure-hosting.com" target="_blank" rel="noopener">https://fascure-hosting.com</a>.</div>
<?php } ?>
<?php if ($licensed && empty($status['passenger'])) { ?>
<div class="banner bad">Passenger is not installed yet. Install it from WHM under Fascure Node.js App before applications can answer web requests.</div>
<?php } ?>
<?php if ($licensed && !$versions) { ?>
<div class="banner bad">No Node.js versions are installed. Add one from WHM under Fascure Node.js App.</div>
<?php } ?>

<?php if ($licensed) { ?>
<div class="card">
<h3>Create Application</h3>
<form method="post">
<input type="hidden" name="action" value="create">
<label>Application name</label>
<input type="text" name="id" placeholder="my-app" required pattern="[a-z0-9][a-z0-9-]{0,31}">
<label>Application type</label>
<select name="type">
<option value="nodejs">Node.js</option>
<option value="nextjs">Next.js</option>
</select>
<label>Node.js version</label>
<select name="version">
<?php foreach ($versions as $version) { ?>
<option value="<?php print h($version); ?>"<?php if ($version === $default_version) { print ' selected'; } ?>><?php print h($version); ?></option>
<?php } ?>
</select>
<label>Application mode</label>
<select name="mode">
<option value="production">Production</option>
<option value="development">Development</option>
</select>
<label>Application root</label>
<input type="text" name="root" placeholder="apps/my-app" required>
<p class="muted">Folder inside your home directory. A starter application is created when the folder is empty.</p>
<label>Application URL</label>
<div class="row">
<select name="domain" required>
<?php foreach ($domains as $domain) { ?>
<option value="<?php print h($domain['domain']); ?>"><?php print h($domain['domain']); ?></option>
<?php } ?>
</select>
<input type="text" name="uri" value="/" placeholder="/">
</div>
<label>Application startup file</label>
<input type="text" name="startup" placeholder="app.js or server.js">
<label>Environment variables</label>
<textarea name="env" placeholder="API_URL=https://example.com"></textarea>
<p class="muted">Optional. One NAME=value on each line. Leave this empty for the test application.</p>
<label><input type="checkbox" name="scaffold" value="1" checked> Create starter files if they are missing</label>
<div class="row"><button type="submit">Create</button></div>
</form>
</div>
<?php } ?>

<?php foreach ($apps as $app) {
    $log = '';
    if (!empty($app['job']['log'])) {
        list($log_ok, $log_data, $log_errors) = call_uapi($cpanel, 'read_log', array('id' => $app['id'], 'which' => preg_replace('/\.log$/', '', $app['job']['log'])));
        if ($log_ok && is_array($log_data) && isset($log_data['log'])) {
            $log = $log_data['log'];
        }
    }
    $scheme = 'https';
    foreach ($domains as $domain) {
        if ($domain['domain'] === $app['domain'] && empty($domain['ssl'])) {
            $scheme = 'http';
        }
    }
    $href = $scheme . '://' . $app['domain'] . ($app['uri'] === '/' ? '/' : $app['uri']);
?>
<div class="card">
<h3><?php print h($app['id']); ?> <span class="muted"><?php print h($app['type']); ?> · <?php print !empty($app['enabled']) ? 'running' : 'stopped'; ?></span></h3>
<p><a href="<?php print h($href); ?>" target="_blank"><?php print h($href); ?></a></p>
<?php if (!empty($app['stopped_reason']) && $app['stopped_reason'] === 'license') { ?>
<p class="muted">This application was stopped because the server license is expired or no longer valid for this IP.</p>
<?php } ?>
<?php if (!$licensed) { ?>
<p class="muted">Node.js <?php print h($app['version']); ?> · <?php print h($app['root']); ?>. Changes are unavailable until WHM has a license key.</p>
</div>
<?php continue; } ?>
<form method="post">
<input type="hidden" name="action" value="update">
<input type="hidden" name="id" value="<?php print h($app['id']); ?>">
<table>
<tr><td style="width:220px"><label>Node.js version</label></td><td>
<select name="version">
<?php foreach ($versions as $version) { ?>
<option value="<?php print h($version); ?>"<?php if ($version === $app['version']) { print ' selected'; } ?>><?php print h($version); ?></option>
<?php } ?>
</select>
</td></tr>
<tr><td><label>Application mode</label></td><td>
<select name="mode">
<option value="production"<?php if ($app['mode'] === 'production') { print ' selected'; } ?>>Production</option>
<option value="development"<?php if ($app['mode'] === 'development') { print ' selected'; } ?>>Development</option>
</select>
</td></tr>
<tr><td><label>Application root</label></td><td><input type="text" value="<?php print h($app['root']); ?>" disabled></td></tr>
<tr><td><label>Application URL</label></td><td>
<div class="row">
<select name="domain">
<?php foreach ($domains as $domain) { ?>
<option value="<?php print h($domain['domain']); ?>"<?php if ($domain['domain'] === $app['domain']) { print ' selected'; } ?>><?php print h($domain['domain']); ?></option>
<?php } ?>
</select>
<input type="text" name="uri" value="<?php print h($app['uri']); ?>">
</div>
</td></tr>
<tr><td><label>Application startup file</label></td><td><input type="text" name="startup" value="<?php print h($app['startup']); ?>"></td></tr>
<tr><td><label>Environment variables</label></td><td><textarea name="env"><?php print h(env_to_text(isset($app['env']) ? $app['env'] : array())); ?></textarea></td></tr>
</table>
<div class="row"><button type="submit">Save</button></div>
</form>
<p class="muted">Enter the virtual environment with:</p>
<pre><?php print h($app['activate']); ?></pre>
<div class="row">
<form method="post"><input type="hidden" name="action" value="npm"><input type="hidden" name="id" value="<?php print h($app['id']); ?>"><button class="secondary" type="submit">Run NPM Install</button></form>
<?php if ($app['type'] === 'nextjs') { ?>
<form method="post"><input type="hidden" name="action" value="build"><input type="hidden" name="id" value="<?php print h($app['id']); ?>"><button class="secondary" type="submit">Run next build</button></form>
<?php } ?>
<form method="post"><input type="hidden" name="action" value="restart"><input type="hidden" name="id" value="<?php print h($app['id']); ?>"><button class="secondary" type="submit">Restart</button></form>
<?php if (!empty($app['enabled'])) { ?>
<form method="post"><input type="hidden" name="action" value="stop"><input type="hidden" name="id" value="<?php print h($app['id']); ?>"><button class="secondary" type="submit">Stop App</button></form>
<?php } else { ?>
<form method="post"><input type="hidden" name="action" value="start"><input type="hidden" name="id" value="<?php print h($app['id']); ?>"><button type="submit">Start App</button></form>
<?php } ?>
</div>
<form method="post" class="row">
<input type="hidden" name="action" value="script">
<input type="hidden" name="id" value="<?php print h($app['id']); ?>">
<input type="text" name="script" placeholder="build" style="max-width:180px">
<button class="secondary" type="submit">Run JS script</button>
</form>
<form method="post" class="row" onsubmit="return confirm('Delete this application?');">
<input type="hidden" name="action" value="delete">
<input type="hidden" name="id" value="<?php print h($app['id']); ?>">
<label style="margin:0"><input type="checkbox" name="remove_files" value="1"> Also delete application files</label>
<button class="danger" type="submit">Delete</button>
</form>
<?php if (!empty($app['job']['action'])) { ?>
<p class="muted">Last task: <?php print h($app['job']['action']); ?><?php print !empty($app['job']['running']) ? ' (running)' : (isset($app['job']['exit']) ? ' (exit ' . h($app['job']['exit']) . ')' : ''); ?></p>
<?php } ?>
<?php if ($log !== '') { ?><pre><?php print h($log); ?></pre><?php } ?>
</div>
<?php } ?>
</div>
<?php
print $cpanel->footer();
$cpanel->end();
