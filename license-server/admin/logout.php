<?php

require_once dirname(__DIR__) . '/lib/admin.php';

admin_start();
$_SESSION = array();
session_destroy();
header('Location: login.php');
exit;
