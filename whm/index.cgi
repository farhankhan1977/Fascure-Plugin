#!/usr/local/cpanel/3rdparty/bin/perl

use strict;
use warnings;

use lib '/usr/local/cpanel';
use lib '/usr/local/nodeapps/lib';

use JSON::PP ();
use NodeApps ();

my $denied = 0;
eval {
    require Whostmgr::ACLS;
    Whostmgr::ACLS::init_acls();
    $denied = !Whostmgr::ACLS::hasroot();
};
if ($@ || $denied) {
    print "Status: 403 Forbidden\r\nContent-type: text/plain; charset=utf-8\r\n\r\nAccess denied.\n";
    exit 1;
}

my %form = parse_form();
my $notice = '';
my $error  = '';

if ( ( $ENV{REQUEST_METHOD} || '' ) eq 'POST' ) {
    my $action = $form{action} || '';
    eval {
        if ( $action eq 'license' ) {
            my $saved = NodeApps::save_license( $form{key} || '' );
            $notice = $saved->{message};
        }
        elsif ( !NodeApps::license_status()->{licensed} ) {
            die NodeApps::license_status()->{message} . "\n";
        }
        elsif ( $action eq 'install' ) {
            my $version = NodeApps::Admin::install_version( $form{spec} || '' );
            $notice = "Installed Node.js $version.";
        }
        elsif ( $action eq 'default' ) {
            my $version = NodeApps::Admin::set_default( $form{version} || '' );
            $notice = "Default Node.js version is $version.";
        }
        elsif ( $action eq 'remove' ) {
            NodeApps::Admin::remove_version( $form{version} || '' );
            $notice = "Removed Node.js $form{version}.";
        }
        elsif ( $action eq 'passenger' ) {
            my $job = NodeApps::Admin::ensure_passenger();
            $notice = "Passenger installation started (pid $job->{pid}). Refresh this page and check the log below.";
        }
        else {
            die "Unknown action.\n";
        }
    };
    if ($@) {
        $error = $@;
        $error =~ s/\s+\z//;
    }
}

my $versions = NodeApps::list_versions();
my $default  = NodeApps::default_version();
my $passenger = passenger_loaded();
my $license = NodeApps::license_status();
my $log = '';
if ( open my $fh, '<', '/var/log/nodeapps-passenger.log' ) {
    my @lines = <$fh>;
    close $fh;
    @lines = @lines[ -40 .. -1 ] if @lines > 40;
    $log = join '', @lines;
}

print "Content-type: text/html; charset=utf-8\r\n\r\n";
eval {
    require Whostmgr::HTMLInterface;
    Whostmgr::HTMLInterface::defheader( 'Fascure Node.js App', '', '/cgi/nodeapps/index.cgi' );
};

print <<'HTML';
<style>
.na { font-family: Arial, sans-serif; color: #1f2933; max-width: 860px; }
.na h2 { margin-top: 0; }
.na .card { border: 1px solid #d5dde5; border-radius: 8px; padding: 16px; margin: 12px 0; background: #fff; }
.na .ok { background: #e8f5e9; padding: 10px; border-radius: 6px; }
.na .bad { background: #fdecea; padding: 10px; border-radius: 6px; }
.na button { background: #1b5e20; color: #fff; border: 0; border-radius: 4px; padding: 7px 12px; cursor: pointer; }
.na .danger { background: #b71c1c; }
.na input[type=text] { padding: 6px 8px; }
.na table { border-collapse: collapse; width: 100%; }
.na td, .na th { text-align: left; padding: 6px 8px; border-bottom: 1px solid #e4ebf1; }
.na pre { background: #f4f7f6; padding: 10px; overflow: auto; max-height: 240px; }
</style>
<div class="na">
<h2>Fascure Node.js App</h2>
<p>Install the Node.js versions customers can select in <strong>Fascure Node.js App</strong>. Each application can use a different version. Passenger runs the application as the cPanel user.</p>
HTML

print '<div class="ok">' . esc($notice) . '</div>' if $notice ne '';
print '<div class="bad">' . esc($error) . '</div>' if $error ne '';

print '<div class="card"><h3>License key</h3>';
print '<p>This plugin checks its license once a day at <strong>plugin.fascure-hosting.com</strong>. The license is valid only for the public IP that contacts the license server, and only until its expiry date. Purchase a license at <a href="https://fascure-hosting.com" target="_blank" rel="noopener">https://fascure-hosting.com</a>.</p>';
print $license->{licensed}
    ? '<div class="ok">' . esc( $license->{message} ) . '</div>'
    : '<div class="bad">' . esc( $license->{message} ) . '</div>';
print <<'HTML';
<form method="post">
<input type="hidden" name="action" value="license">
<p><input type="text" name="key" placeholder="FSCP-...." style="width:100%" required></p>
<button type="submit">Save license key</button>
</form>
</div>
HTML

if ( !$license->{licensed} ) {
    print '</div>';
    eval { Whostmgr::HTMLInterface::deffooter(); };
    exit 0;
}

print $passenger
    ? '<div class="ok">Passenger is loaded in Apache.</div>'
    : '<div class="bad">Passenger is not loaded. AlmaLinux 8 needs the EasyApache packages ea-ruby27-mod_passenger and ea-apache24-mod_env.</div>';

print <<'HTML';
<div class="card">
<h3>Passenger</h3>
<form method="post">
<input type="hidden" name="action" value="passenger">
<button type="submit">Install Passenger for Node.js</button>
</form>
HTML
print '<pre>' . esc($log) . '</pre>' if $log ne '';
print '</div>';

print <<'HTML';
<div class="card">
<h3>Install a Node.js version</h3>
<form method="post">
<input type="hidden" name="action" value="install">
<input type="text" name="spec" placeholder="22 or v22.14.0" required>
<button type="submit">Install</button>
</form>
<p>Use a major version such as 20, 22, or 24. The newest matching release is downloaded from nodejs.org.</p>
</div>
<div class="card">
<h3>Installed versions</h3>
<table>
<tr><th>Version</th><th>Default</th><th></th></tr>
HTML

if ( !@{$versions} ) {
    print '<tr><td colspan="3">No Node.js versions are installed.</td></tr>';
}
foreach my $version ( @{$versions} ) {
    my $mark = ( $version eq $default ) ? 'yes' : '';
    print '<tr><td>' . esc($version) . '</td><td>' . esc($mark) . '</td><td>';
    print '<form method="post" style="display:inline">';
    print '<input type="hidden" name="action" value="default">';
    print '<input type="hidden" name="version" value="' . esc($version) . '">';
    print '<button type="submit">Make default</button></form> ';
    print '<form method="post" style="display:inline" onsubmit="return confirm(\'Remove this Node.js version?\')">';
    print '<input type="hidden" name="action" value="remove">';
    print '<input type="hidden" name="version" value="' . esc($version) . '">';
    print '<button class="danger" type="submit">Remove</button></form>';
    print '</td></tr>';
}

print '</table></div></div>';
eval { Whostmgr::HTMLInterface::deffooter(); };

sub esc {
    my ($text) = @_;
    $text = '' unless defined $text;
    $text =~ s/&/&amp;/g;
    $text =~ s/</&lt;/g;
    $text =~ s/>/&gt;/g;
    $text =~ s/"/&quot;/g;
    return $text;
}

sub parse_form {
    my %out;
    return %out unless ( $ENV{REQUEST_METHOD} || '' ) eq 'POST';
    my $len = $ENV{CONTENT_LENGTH} || 0;
    return %out if $len <= 0 || $len > 100000;
    my $body;
    read STDIN, $body, $len;
    foreach my $pair ( split /&/, $body ) {
        my ( $k, $v ) = split /=/, $pair, 2;
        next unless defined $k;
        for ( $k, $v ) {
            next unless defined;
            tr/+/ /;
            s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg;
        }
        $out{$k} = defined $v ? $v : '';
    }
    return %out;
}

sub passenger_loaded {
    return 1 if -e '/etc/apache2/conf.modules.d/passenger.conf';
    my $httpd = -x '/usr/sbin/httpd' ? '/usr/sbin/httpd' : '';
    return 0 unless $httpd;
    my $out = `$httpd -M 2>/dev/null`;
    return $out =~ /passenger_module/ ? 1 : 0;
}
