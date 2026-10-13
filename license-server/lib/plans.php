<?php

function plan_spec($id)
{
    $plans = array(
        'basic' => array('id' => 'basic', 'label' => 'Basic', 'tenants' => 1, 'apps' => 1),
        'standard' => array('id' => 'standard', 'label' => 'Standard', 'tenants' => 10, 'apps' => 3),
        'enterprise' => array('id' => 'enterprise', 'label' => 'Enterprise', 'tenants' => 0, 'apps' => 0),
    );
    return isset($plans[$id]) ? $plans[$id] : null;
}

function plan_limit_label($number)
{
    return ((int) $number) === 0 ? 'unlimited' : (string) $number;
}

function new_license_key()
{
    $alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    $max = strlen($alphabet) - 1;
    $groups = array();
    for ($g = 0; $g < 4; $g++) {
        $part = '';
        for ($i = 0; $i < 4; $i++) {
            $part .= $alphabet[random_int(0, $max)];
        }
        $groups[] = $part;
    }
    return 'FSCP-' . implode('-', $groups);
}

function valid_ip($ip)
{
    return filter_var($ip, FILTER_VALIDATE_IP) !== false;
}

function client_ip()
{
    $ip = isset($_SERVER['REMOTE_ADDR']) ? $_SERVER['REMOTE_ADDR'] : '';
    return valid_ip($ip) ? $ip : '';
}
