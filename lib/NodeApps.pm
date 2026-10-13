package NodeApps;

use strict;
use warnings;

use Cwd            ();
use Fcntl          qw(:flock);
use File::Basename qw(basename);
use File::Path     qw(make_path remove_tree);
use File::Spec     ();
use File::Temp     qw(tempdir);
use JSON::PP       ();
use POSIX          qw(setsid);

our $VERSION = '1.0.0';
our $PREFIX  = $ENV{NODEAPPS_PREFIX} || '/opt/nodeapps';

sub new {
    my ( $class, %args ) = @_;
    my $user = _untaint_user( $args{user} ) or die "Invalid account user.\n";
    my $home = _account_home($user);
    if ( defined $args{homedir} && $args{homedir} ne '' && $args{homedir} ne $home ) {
        die "Home directory does not match this account.\n";
    }
    return bless { user => $user, home => $home }, $class;
}

sub user { $_[0]->{user} }
sub home { $_[0]->{home} }

sub prefix     { $PREFIX }
sub versiondir { File::Spec->catdir( $PREFIX, 'versions' ) }
sub default_file { File::Spec->catfile( $PREFIX, 'default' ) }

sub state_dir { File::Spec->catdir( $_[0]->{home}, '.nodeapps' ) }
sub apps_file { File::Spec->catfile( $_[0]->state_dir, 'apps.json' ) }

sub ensure_state {
    my ($self) = @_;
    my $dir = $self->state_dir;
    make_path( $dir, { mode => 0700 } ) unless -d $dir;
    chmod 0700, $dir;
    return $dir;
}

sub list_versions {
    my $dir = versiondir();
    return [] unless -d $dir;
    opendir my $dh, $dir or return [];
    my @versions;
    foreach my $name ( sort readdir $dh ) {
        next if $name =~ /^\./;
        my $untainted = _untaint_version($name) or next;
        my $bin = File::Spec->catfile( $dir, $untainted, 'bin', 'node' );
        next unless -x $bin;
        push @versions, $untainted;
    }
    closedir $dh;
    return \@versions;
}

sub default_version {
    my $versions = list_versions();
    my $file     = default_file();
    if ( open my $fh, '<', $file ) {
        my $line = <$fh> // '';
        close $fh;
        chomp $line;
        my $wanted = _untaint_version($line);
        if ( $wanted && grep { $_ eq $wanted } @{$versions} ) {
            return $wanted;
        }
    }
    return $versions->[-1] || '';
}

sub system_status {
    my ($self) = @_;
    my $passenger = 0;
    my $detail    = 'Passenger module was not found.';
    foreach my $candidate (
        '/etc/apache2/conf.modules.d/passenger.conf',
        '/etc/apache2/conf.modules.d/90-passenger.conf',
        )
    {
        if ( -r $candidate ) {
            $passenger = 1;
            $detail    = $candidate;
            last;
        }
    }
    if ( !$passenger ) {
        my $glob_dir = '/etc/apache2/conf.modules.d';
        if ( opendir my $dh, $glob_dir ) {
            foreach my $name ( readdir $dh ) {
                next unless $name =~ /passenger/i;
                $passenger = 1;
                $detail    = "$glob_dir/$name";
                last;
            }
            closedir $dh;
        }
    }
    my $license = license_status();
    if ( $> != 0 ) {
        my ( $rc, $text ) = _run_quota(1);
        if ( $rc == 0 && $text =~ /"tenants_used":(\d+)/ ) {
            $license->{tenants_used} = $1;
        }
    }
    return {
        passenger => $passenger,
        passenger_detail => $detail,
        versions  => list_versions(),
        default_version => default_version(),
        user      => $self->{user},
        home      => $self->{home},
        licensed  => $license->{licensed},
        license_host => $license->{host},
        license_message => $license->{message},
        plan      => $license->{plan} || '',
        plan_label => $license->{plan_label} || '',
        tenants   => $license->{tenants} || 0,
        apps      => $license->{apps} || 0,
        tenants_used => $license->{tenants_used} || 0,
        apps_used => $self->_local_app_count,
    };
}

sub license_file { '/var/cpanel/nodeapps/license.key' }
sub license_cache_file { '/var/cpanel/nodeapps/license-cache.json' }
sub license_server_url {
    return $ENV{NODEAPPS_LICENSE_URL} || 'https://plugin.fascure-hosting.com/api/verify.php';
}

sub license_hostname {
    my $host = '';
    if ( open my $fh, '<', '/etc/hostname' ) {
        $host = <$fh> // '';
        close $fh;
        chomp $host;
    }
    $host =~ s/\A\s+|\s+\z//g;
    return $host eq '' ? 'localhost' : $host;
}

sub license_status {
    my $host = license_hostname();
    my $token = _read_license_key();
    if ( $token eq '' ) {
        return {
            licensed => 0,
            host     => $host,
            message  => 'Fascure Node.js App is limited until a license key is entered in WHM.',
        };
    }
    my $info = _license_checked($token);
    my $tenants_used = 0;
    if ( $> == 0 ) {
        my $inv = eval { license_inventory() };
        $tenants_used = $inv->{tenants_used} || 0 if $inv;
    }
    if ( !$info->{ok} ) {
        return {
            licensed => 0,
            host     => $host,
            ip       => $info->{ip} || '',
            message  => $info->{message} || 'The license server rejected this key.',
            tenants_used => $tenants_used,
        };
    }
    my $account_label = $info->{tenants} ? $info->{tenants} : 'unlimited';
    my $app_label     = $info->{apps}     ? $info->{apps}     : 'unlimited';
    return {
        licensed   => 1,
        host       => $host,
        ip         => $info->{ip} || '',
        plan       => $info->{plan},
        plan_label => $info->{plan_label},
        tenants    => $info->{tenants},
        apps       => $info->{apps},
        tenants_used => $tenants_used,
        expires    => $info->{expires_at} || '',
        message    => "Licensed for $info->{ip}. $info->{plan_label} plan: $account_label accounts, $app_label applications on each account. Expires $info->{expires_at}.",
    };
}

sub license_refresh {
    my $token = _read_license_key();
    return { ok => 0, message => 'No license key is saved.' } if $token eq '';
    return _license_remote( $token, 1 );
}

sub require_license {
    my $status = license_status();
    die $status->{message} . "\n" unless $status->{licensed};
    return 1;
}

sub save_license {
    my ($token) = @_;
    die "Only the server administrator can save a license key.\n" if $> != 0;
    $token = _normalize_license_key($token);
    die "Enter a license key.\n" if $token eq '';
    my $info = _license_remote( $token, 1 );
    die ( $info->{message} || "The license server rejected this key.\n" ) unless $info->{ok};
    my $dir = '/var/cpanel/nodeapps';
    make_path( $dir, { mode => 0755 } );
    my $file = license_file();
    open my $fh, '>', $file or die "Could not save the license key.\n";
    print {$fh} $token, "\n";
    close $fh;
    chmod 0644, $file;
    return license_status();
}

sub _read_license_key {
    my $file = license_file();
    return '' unless -s $file;
    open my $fh, '<', $file or return '';
    my $token = <$fh> // '';
    close $fh;
    return _normalize_license_key($token);
}

sub _normalize_license_key {
    my ($token) = @_;
    $token = '' unless defined $token;
    $token =~ s/\s+//g;
    return uc $token;
}

sub _license_checked {
    my ($token) = @_;
    my $cache = _read_license_cache();
    my $fresh = $cache
        && ( $cache->{license_key} || '' ) eq $token
        && ( $cache->{checked_at} || 0 ) > time - 86400;
    if ($fresh) {
        return $cache;
    }
    return _license_remote( $token, $> == 0 );
}

sub _license_remote {
    my ( $token, $write_cache ) = @_;
    my $url = license_server_url();
    my $body = JSON::PP->new->encode( { license_key => $token } );
    my $http = HTTP::Tiny->new( timeout => 20, verify_SSL => 1 );
    my $res = $http->request(
        'POST', $url,
        {
            headers => { 'Content-Type' => 'application/json', 'Accept' => 'application/json' },
            content => $body,
        }
    );
    my $data = eval { JSON::PP->new->utf8->decode( $res->{content} || '' ) };
    if ( !$res->{success} && !( ref $data eq 'HASH' && exists $data->{ok} ) ) {
        my $cache = _read_license_cache();
        if (   $cache
            && ( $cache->{license_key} || '' ) eq $token
            && $cache->{ok}
            && ( $cache->{checked_at} || 0 ) > time - 172800 )
        {
            $cache->{message} = 'Using the license verified ' . localtime( $cache->{checked_at} ) . ' because the license server did not answer.';
            return $cache;
        }
        return { ok => 0, message => 'The license server did not answer. The plugin stays limited until it can be checked.' };
    }
    return { ok => 0, message => 'The license server returned an unexpected response.' } unless ref $data eq 'HASH';
    my $plan = _plan_spec( $data->{plan} || '' );
    my $info = {
        ok           => $data->{ok} ? 1 : 0,
        license_key  => $token,
        checked_at   => time,
        plan         => $plan ? $plan->{id} : '',
        plan_label   => $plan ? $plan->{label} : '',
        tenants      => $plan ? $plan->{tenants} : 0,
        apps         => $plan ? $plan->{apps} : 0,
        ip           => $data->{ip} || '',
        expires_at   => $data->{expires_at} || '',
        message      => $data->{message} || ( $data->{ok} ? 'License is valid.' : 'The license server rejected this key.' ),
    };
    if ( $info->{ok} && !$plan ) {
        $info->{ok} = 0;
        $info->{message} = 'The license server returned an unknown plan.';
    }
    _write_license_cache($info) if $write_cache;
    return $info;
}

sub _read_license_cache {
    my $file = license_cache_file();
    return unless -s $file;
    my $data = _read_json($file);
    return unless ref $data eq 'HASH';
    return $data;
}

sub _write_license_cache {
    my ($info) = @_;
    my $dir = '/var/cpanel/nodeapps';
    make_path( $dir, { mode => 0755 } );
    _write_json( license_cache_file(), $info );
    chmod 0644, license_cache_file();
    return 1;
}

sub _plan_spec {
    my ($id) = @_;
    my %plans = (
        basic => { id => 'basic', label => 'Basic', tenants => 1, apps => 1 },
        standard => { id => 'standard', label => 'Standard', tenants => 10, apps => 3 },
        enterprise => { id => 'enterprise', label => 'Enterprise', tenants => 0, apps => 0 },
    );
    return $plans{$id} if defined $id && $plans{$id};
    return;
}

sub license_inventory {
    die "License inventory requires root.\n" if $> != 0;
    my %by_user;
    my $tenants = 0;
    my $dir = '/var/cpanel/users';
    opendir my $dh, $dir or return { tenants_used => 0, by_user => {} };
    foreach my $name ( readdir $dh ) {
        next if $name =~ /^\./ || $name eq 'system';
        my $user = _untaint_user($name) or next;
        my $home = eval { _account_home($user) } or next;
        my $file = File::Spec->catfile( $home, '.nodeapps', 'apps.json' );
        next unless -f $file;
        my $data = _read_json($file) || next;
        my $count = scalar @{ $data->{apps} || [] };
        next if $count < 1;
        $by_user{$user} = $count;
        $tenants++;
    }
    closedir $dh;
    return { tenants_used => $tenants, by_user => \%by_user };
}

sub assert_can_create {
    my ($user) = @_;
    die "License limits can only be checked as root.\n" if $> != 0;
    $user = _untaint_user($user) or die "Invalid account.\n";
    my $status = license_status();
    die $status->{message} . "\n" unless $status->{licensed};
    my $inv  = license_inventory();
    my $mine = $inv->{by_user}{$user} || 0;
    if ( $status->{apps} > 0 && $mine >= $status->{apps} ) {
        die "The $status->{plan_label} license allows $status->{apps} application(s) on each account.\n";
    }
    if ( $status->{tenants} > 0 && $mine == 0 && $inv->{tenants_used} >= $status->{tenants} ) {
        die "The $status->{plan_label} license allows Node.js on $status->{tenants} account(s).\n";
    }
    return 1;
}

sub _local_app_count {
    my ($self) = @_;
    my $data = eval { $self->_load };
    return 0 unless $data && ref $data->{apps} eq 'ARRAY';
    return scalar @{ $data->{apps} };
}

sub _enforce_plan {
    my ($self) = @_;
    if ( $> == 0 ) {
        assert_can_create( $self->{user} );
        return 1;
    }
    my ( $rc, $text ) = _run_quota();
    return 1 if $rc == 0;
    $text =~ s/\s+\z//;
    die( $text ne '' ? "$text\n" : "The license limit was reached.\n" );
}

sub _run_quota {
    my ($usage) = @_;
    my @cmd = ( '/usr/bin/sudo', '-n', '/usr/local/nodeapps/bin/nodeapps-quota' );
    push @cmd, '--usage' if $usage;
    my $dir = tempdir( 'nodeapps-quota-XXXX', DIR => '/tmp', CLEANUP => 1 );
    local $ENV{PATH} = '/usr/bin:/bin';
    my $pid = fork();
    die "Could not check the license limit.\n" unless defined $pid;
    if ( $pid == 0 ) {
        open STDOUT, '>', "$dir/out" or exit 127;
        open STDERR, '>&', \*STDOUT or exit 127;
        exec { $cmd[0] } @cmd;
        exit 127;
    }
    waitpid $pid, 0;
    my $rc = $? >> 8;
    my $text = '';
    if ( open my $fh, '<', "$dir/out" ) {
        local $/;
        $text = <$fh> // '';
        close $fh;
    }
    return ( $rc, $text );
}

sub list_domains {
    my ($self) = @_;
    my $user = $self->{user};
    my $base = "/var/cpanel/userdata/$user";
    my @domains;
    if ( -d $base && opendir my $dh, $base ) {
        foreach my $name ( sort readdir $dh ) {
            next if $name =~ /^\./;
            next if $name eq 'main' || $name eq 'cache';
            my $path = "$base/$name";
            next if -d $path;
            my $info = _read_userdata($path) or next;
            my $domain = $info->{servername} || $name;
            $domain =~ s/_SSL\z//;
            next if $domain !~ /\A[A-Za-z0-9.-]+\z/;
            my $docroot = $info->{documentroot} || '';
            next unless _path_under( $docroot, $self->{home} );
            my $ssl = ( $info->{ssl} && $info->{ssl} ne '0' ) ? 1 : 0;
            $ssl = 1 if $name =~ /_SSL\z/;
            push @domains, {
                domain       => $domain,
                documentroot => $docroot,
                ssl          => $ssl,
            };
        }
        closedir $dh;
    }
    my %seen;
    my @unique;
    foreach my $row ( sort { $a->{domain} cmp $b->{domain} } @domains ) {
        if ( $seen{ $row->{domain} } ) {
            $seen{ $row->{domain} }{ssl} = 1 if $row->{ssl};
            next;
        }
        $seen{ $row->{domain} } = $row;
        push @unique, $row;
    }
    return \@unique;
}

sub list_apps {
    my ($self) = @_;
    my $data = $self->_load;
    my @out;
    foreach my $app ( @{ $data->{apps} } ) {
        push @out, $self->_public_app($app);
    }
    return \@out;
}

sub create_app {
    my ( $self, %in ) = @_;
    require_license();
    my $id = _untaint_app_id( $in{id} ) or die "Use an application name of 1-32 letters, numbers, or hyphens.\n";
    my $type = ( $in{type} // '' ) eq 'nextjs' ? 'nextjs' : 'nodejs';
    my $mode = ( $in{mode} // '' ) eq 'development' ? 'development' : 'production';
    my $rel  = _untaint_relative( $in{root} ) or die "Application root must be a folder inside your home directory.\n";
    my $version = $self->_resolve_version( $in{version} );
    my $startup = _untaint_startup( $in{startup} || ( $type eq 'nextjs' ? 'server.js' : 'app.js' ) )
        or die "Startup file must be a .js, .cjs, or .mjs file inside the application.\n";
    my $uri    = _normalize_uri( $in{uri} );
    my $domain = _untaint_domain( $in{domain} ) or die "Choose a domain that belongs to this account.\n";
    my $env    = _clean_env( $in{env} || {} );
    my $docroot = $self->_docroot_for($domain) or die "That domain is not on this account.\n";
    my $abs = File::Spec->catdir( $self->{home}, split m{/}, $rel );
    die "Application root must stay inside your home directory.\n" unless _strict_under( $abs, $self->{home} );

    my $lock = $self->_lock;
    my $data = $self->_load;
    die "An application named $id already exists.\n" if $self->_find( $data, $id );
    $self->_enforce_plan;
    foreach my $other ( @{ $data->{apps} } ) {
        if ( $other->{domain} eq $domain && $other->{uri} eq $uri ) {
            die "Another application already uses $domain$uri.\n";
        }
    }

    make_path( $abs, { mode => 0755 } );
    my $real = Cwd::realpath($abs) or die "Could not create the application directory.\n";
    $real = _untaint_abs($real) or die "Application path is not allowed.\n";
    die "Application root must stay inside your home directory.\n" unless _strict_under( $real, $self->{home} );

    my $app = {
        id       => $id,
        type     => $type,
        mode     => $mode,
        root     => $rel,
        domain   => $domain,
        uri      => $uri,
        startup  => $startup,
        version  => $version,
        env      => $env,
        enabled  => 1,
        created  => time,
    };

    my $scaffold = !defined $in{scaffold} || $in{scaffold};
    $self->_scaffold( $real, $app ) if $scaffold;
    $self->_write_runtime($app);
    $self->_prepare_uri_dir($app);
    push @{ $data->{apps} }, $app;
    $self->_save($data);
    $self->_apply_server;
    return $self->_public_app($app);
}

sub update_app {
    my ( $self, %in ) = @_;
    require_license();
    my $id = _untaint_app_id( $in{id} ) or die "Unknown application.\n";
    my $lock = $self->_lock;
    my $data = $self->_load;
    my $app  = $self->_find( $data, $id ) or die "Unknown application.\n";
    my $previous = { %{$app}, env => { %{ $app->{env} || {} } } };

    if ( exists $in{version} && defined $in{version} && $in{version} ne '' ) {
        $app->{version} = $self->_resolve_version( $in{version} );
    }
    if ( exists $in{mode} && defined $in{mode} && $in{mode} ne '' ) {
        $app->{mode} = $in{mode} eq 'development' ? 'development' : 'production';
    }
    if ( exists $in{startup} && defined $in{startup} && $in{startup} ne '' ) {
        $app->{startup} = _untaint_startup( $in{startup} ) or die "Startup file must be a .js, .cjs, or .mjs file inside the application.\n";
    }
    if ( exists $in{env} ) {
        $app->{env} = _clean_env( $in{env} || {} );
    }
    if ( exists $in{domain} && defined $in{domain} && $in{domain} ne '' ) {
        my $domain = _untaint_domain( $in{domain} ) or die "Choose a domain that belongs to this account.\n";
        $self->_docroot_for($domain) or die "That domain is not on this account.\n";
        $app->{domain} = $domain;
    }
    if ( exists $in{uri} ) {
        $app->{uri} = _normalize_uri( $in{uri} );
    }
    foreach my $other ( @{ $data->{apps} } ) {
        next if $other->{id} eq $id;
        if ( $other->{domain} eq $app->{domain} && $other->{uri} eq $app->{uri} ) {
            die "Another application already uses $app->{domain}$app->{uri}.\n";
        }
    }

    if ( $previous->{domain} ne $app->{domain} || $previous->{uri} ne $app->{uri} ) {
        $self->_strip_htaccess($previous);
    }
    $self->_write_runtime($app);
    $self->_prepare_uri_dir($app) if $app->{enabled};
    $self->_save($data);
    $self->_apply_server;
    return $self->_public_app($app);
}

sub set_enabled {
    my ( $self, $id, $enabled ) = @_;
    require_license();
    $id = _untaint_app_id($id) or die "Unknown application.\n";
    my $lock = $self->_lock;
    my $data = $self->_load;
    my $app  = $self->_find( $data, $id ) or die "Unknown application.\n";
    $app->{enabled} = $enabled ? 1 : 0;
    if ( $app->{enabled} ) {
        $self->_write_runtime($app);
        $self->_prepare_uri_dir($app);
    }
    else {
        $self->_strip_htaccess($app);
        $self->_touch_restart($app);
    }
    $self->_save($data);
    $self->_apply_server;
    return $self->_public_app($app);
}

sub delete_app {
    my ( $self, $id, $remove_files ) = @_;
    require_license();
    $id = _untaint_app_id($id) or die "Unknown application.\n";
    my $lock = $self->_lock;
    my $data = $self->_load;
    my $app  = $self->_find( $data, $id ) or die "Unknown application.\n";
    $self->_strip_htaccess($app);
    my $venv = $self->_venv_dir($app);
    remove_tree($venv) if -d $venv;
    if ($remove_files) {
        my $abs = $self->_abs_root($app);
        remove_tree($abs) if _strict_under( $abs, $self->{home} );
    }
    $data->{apps} = [ grep { $_->{id} ne $id } @{ $data->{apps} } ];
    $self->_save($data);
    $self->_apply_server;
    return { id => $id, removed => 1 };
}

sub restart_app {
    require_license();
    my ( $self, $id ) = @_;
    $id = _untaint_app_id($id) or die "Unknown application.\n";
    my $data = $self->_load;
    my $app  = $self->_find( $data, $id ) or die "Unknown application.\n";
    die "Start the application before restarting it.\n" unless $app->{enabled};
    $self->_touch_restart($app);
    return { id => $id, restarted => 1 };
}

sub run_npm_install {
    require_license();
    my ( $self, $id ) = @_;
    my $app = $self->_require_app($id);
    my $bin = $self->_node_bin( $app->{version} );
    my $npm = File::Spec->catfile( $bin, 'npm' );
    die "npm is missing for $app->{version}.\n" unless -x $npm;
    return $self->_spawn(
        $app, 'npm-install',
        [ $npm, 'install', '--no-audit', '--no-fund' ],
    );
}

sub run_next_build {
    require_license();
    my ( $self, $id ) = @_;
    my $app = $self->_require_app($id);
    die "next build is for Next.js applications.\n" unless $app->{type} eq 'nextjs';
    my $abs  = $self->_abs_root($app);
    my $next = File::Spec->catfile( $abs, 'node_modules', '.bin', 'next' );
    die "Run NPM Install before next build.\n" unless -x $next;
    return $self->_spawn( $app, 'next-build', [ $next, 'build' ], { NODE_ENV => 'production' } );
}

sub run_script {
    require_license();
    my ( $self, $id, $script ) = @_;
    $script = _untaint_script($script) or die "Script name is not allowed.\n";
    my $app = $self->_require_app($id);
    my $bin = $self->_node_bin( $app->{version} );
    my $npm = File::Spec->catfile( $bin, 'npm' );
    die "npm is missing for $app->{version}.\n" unless -x $npm;
    return $self->_spawn( $app, 'npm-script', [ $npm, 'run', $script ] );
}

sub job_status {
    my ( $self, $id ) = @_;
    $id = _untaint_app_id($id) or die "Unknown application.\n";
    my $file = $self->_job_file($id);
    return { running => 0 } unless -f $file;
    my $job = _read_json($file) || { running => 0 };
    if ( $job->{pid} && $job->{running} ) {
        if ( !kill 0, $job->{pid} ) {
            $job->{running}  = 0;
            $job->{finished} = time;
            my $exitfile = $file . '.exit';
            if ( open my $ef, '<', $exitfile ) {
                my $code = <$ef>;
                close $ef;
                $job->{exit} = defined $code ? int($code) : -1;
            }
            else {
                $job->{exit} = -1;
            }
            _write_json( $file, $job );
        }
    }
    return $job;
}

sub read_log {
    my ( $self, $id, $which ) = @_;
    my $app = $self->_require_app($id);
    $which = ( $which && $which =~ /\A([a-z0-9.-]{1,40})\z/ ) ? $1 : 'npm-install';
    my $abs = $self->_abs_root($app);
    my $log = File::Spec->catfile( $abs, '.nodeapps-logs', $which . '.log' );
    return '' unless -f $log && _strict_under( $log, $abs );
    open my $fh, '<', $log or return '';
    my @lines = <$fh>;
    close $fh;
    my $keep = 120;
    @lines = @lines[ -$keep .. -1 ] if @lines > $keep;
    return join '', @lines;
}

sub _require_app {
    my ( $self, $id ) = @_;
    $id = _untaint_app_id($id) or die "Unknown application.\n";
    my $data = $self->_load;
    my $app  = $self->_find( $data, $id ) or die "Unknown application.\n";
    return $app;
}

sub _resolve_version {
    my ( $self, $requested ) = @_;
    my $versions = list_versions();
    die "No Node.js versions are installed yet. Install one in WHM first.\n" unless @{$versions};
    if ( !defined $requested || $requested eq '' || $requested eq 'default' ) {
        my $default = default_version();
        die "No default Node.js version is configured.\n" unless $default;
        return $default;
    }
    my $version = _untaint_version($requested) or die "Unknown Node.js version.\n";
    die "Node.js $version is not installed on this server.\n" unless grep { $_ eq $version } @{$versions};
    return $version;
}

sub _node_bin {
    my ( $self, $version ) = @_;
    $version = _untaint_version($version) or die "Unknown Node.js version.\n";
    my $bin = File::Spec->catdir( versiondir(), $version, 'bin' );
    my $node = File::Spec->catfile( $bin, 'node' );
    die "Node.js $version is not installed.\n" unless -x $node;
    return $bin;
}

sub _abs_root {
    my ( $self, $app ) = @_;
    my $rel = _untaint_relative( $app->{root} ) or die "Stored application path is invalid.\n";
    my $abs = File::Spec->catdir( $self->{home}, split m{/}, $rel );
    my $real = Cwd::realpath($abs);
    $real = $real ? _untaint_abs($real) : undef;
    die "Application directory is missing.\n" unless $real && _strict_under( $real, $self->{home} );
    return $real;
}

sub _docroot_for {
    my ( $self, $domain ) = @_;
    foreach my $row ( @{ $self->list_domains } ) {
        return _untaint_abs( $row->{documentroot} ) if $row->{domain} eq $domain;
    }
    return;
}

sub _public_app {
    my ( $self, $app ) = @_;
    my $copy = {
        id       => $app->{id},
        type     => $app->{type},
        mode     => $app->{mode},
        root     => $app->{root},
        domain   => $app->{domain},
        uri      => $app->{uri},
        startup  => $app->{startup},
        version  => $app->{version},
        env      => $app->{env} || {},
        enabled  => $app->{enabled} ? 1 : 0,
        created  => $app->{created} || 0,
        activate => 'source ' . $self->_venv_dir($app) . '/bin/activate',
        url_path => $app->{domain} . ( $app->{uri} eq '/' ? '/' : $app->{uri} ),
    };
    my $job = eval { $self->job_status( $app->{id} ) } || {};
    $copy->{job} = $job;
    return $copy;
}

sub _venv_dir {
    my ( $self, $app ) = @_;
    return File::Spec->catdir( $self->{home}, 'nodevenv', $app->{id}, $app->{version} );
}

sub _write_runtime {
    my ( $self, $app ) = @_;
    my $abs = $self->_abs_root($app);
    my $env = { %{ $app->{env} || {} } };
    $env->{NODE_ENV} = $app->{mode} eq 'development' ? 'development' : 'production';
    $env->{NODEAPPS_STARTUP} = $app->{startup};
    _write_json( File::Spec->catfile( $abs, '.nodeapps-env.json' ), $env );
    chmod 0644, File::Spec->catfile( $abs, '.nodeapps-env.json' );

    my $wrapper = File::Spec->catfile( $abs, '.nodeapps-passenger.cjs' );
    open my $fh, '>', $wrapper or die "Could not write the Passenger startup file: $!\n";
    print {$fh} _wrapper_source();
    close $fh;
    chmod 0644, $wrapper;

    my $venv = $self->_venv_dir($app);
    my $bin  = File::Spec->catdir( $venv, 'bin' );
    make_path( $bin, { mode => 0755 } );
    my $nodebin = $self->_node_bin( $app->{version} );
    foreach my $tool (qw(node npm npx)) {
        my $target = File::Spec->catfile( $nodebin, $tool );
        my $link   = File::Spec->catfile( $bin, $tool );
        unlink $link if -l $link || -e $link;
        symlink $target, $link or die "Could not link $tool: $!\n";
    }
    my $activate = File::Spec->catfile( $bin, 'activate' );
    open my $af, '>', $activate or die "Could not write the activate script: $!\n";
    print {$af} "export PATH=\"$bin:\$PATH\"\nexport NODEAPPS_APP=\"$app->{id}\"\n";
    close $af;
    chmod 0755, $activate;
    return 1;
}

sub _wrapper_source {
    return <<'JS';
'use strict';
const fs = require('fs');
const path = require('path');
const { pathToFileURL } = require('url');
const root = __dirname;
try {
  const raw = fs.readFileSync(path.join(root, '.nodeapps-env.json'), 'utf8');
  const env = JSON.parse(raw);
  for (const [key, value] of Object.entries(env)) {
    if (process.env[key] == null || process.env[key] === '') process.env[key] = String(value);
  }
} catch (err) {
  process.stderr.write('nodeapps env: ' + err.message + '\n');
}
const startup = process.env.NODEAPPS_STARTUP || 'app.js';
const target = path.resolve(root, startup);
const rel = path.relative(root, target);
if (rel === '' || rel.startsWith('..') || path.isAbsolute(rel)) {
  throw new Error('startup file must stay inside the application');
}
let moduleType = '';
try {
  moduleType = JSON.parse(fs.readFileSync(path.join(root, 'package.json'), 'utf8')).type || '';
} catch (err) {}
if (moduleType === 'module' || target.endsWith('.mjs')) {
  import(pathToFileURL(target).href).catch((err) => {
    process.stderr.write(String(err && err.stack || err) + '\n');
    process.exit(1);
  });
} else {
  require(target);
}
JS
}

sub _scaffold {
    my ( $self, $abs, $app ) = @_;
    if ( $app->{type} eq 'nextjs' ) {
        _write_if_missing( File::Spec->catfile( $abs, 'package.json' ), <<'JSON' );
{
  "name": "next-app",
  "private": true,
  "scripts": {
    "build": "next build",
    "start": "node server.js"
  },
  "dependencies": {
    "next": "^15.5.0",
    "react": "^19.0.0",
    "react-dom": "^19.0.0"
  }
}
JSON
        _write_if_missing( File::Spec->catfile( $abs, 'next.config.js' ), <<'JS' );
/** @type {import('next').NextConfig} */
const nextConfig = { reactStrictMode: true };
module.exports = nextConfig;
JS
        _write_if_missing( File::Spec->catfile( $abs, 'server.js' ), <<'JS' );
const { createServer } = require('http');
const { parse } = require('url');
const next = require('next');

const port = parseInt(process.env.PORT, 10) || 3000;
const dev = process.env.NODE_ENV !== 'production';
const app = next({ dev, hostname: '127.0.0.1', port });
const handle = app.getRequestHandler();

app.prepare().then(() => {
  createServer((req, res) => {
    handle(req, res, parse(req.url, true));
  }).listen(port, '127.0.0.1');
});
JS
        my $pages = File::Spec->catdir( $abs, 'pages' );
        make_path($pages) unless -d $pages;
        _write_if_missing( File::Spec->catfile( $pages, 'index.js' ), <<'JS' );
export default function Home() {
  return <h1>Next.js application</h1>;
}
JS
    }
    else {
        _write_if_missing( File::Spec->catfile( $abs, 'package.json' ), <<'JSON' );
{
  "name": "node-app",
  "private": true,
  "scripts": {
    "start": "node app.js"
  }
}
JSON
        _write_if_missing( File::Spec->catfile( $abs, 'app.js' ), <<'JS' );
const http = require('http');
const port = process.env.PORT || 3000;
const server = http.createServer((req, res) => {
  res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
  res.end('<h1>Node.js application</h1><p>Replace app.js with your application. It must listen on process.env.PORT.</p>');
});
server.listen(port, '127.0.0.1');
JS
    }
    return 1;
}

sub _htaccess_file {
    my ( $self, $app ) = @_;
    my $docroot = $self->_docroot_for( $app->{domain} ) or die "That domain is not on this account.\n";
    my $uri = $app->{uri};
    my $dir = $docroot;
    if ( $uri ne '/' ) {
        my $extra = $uri;
        $extra =~ s{^/}{};
        $dir = File::Spec->catdir( $docroot, split m{/}, $extra );
    }
    make_path( $dir, { mode => 0755 } ) unless -d $dir;
    my $real = Cwd::realpath($dir);
    $real = $real ? _untaint_abs($real) : undef;
    die "Application URL directory is outside this account.\n" unless $real && _strict_under( $real, $self->{home} );
    return File::Spec->catfile( $real, '.htaccess' );
}

sub _prepare_uri_dir {
    my ( $self, $app ) = @_;
    $self->_htaccess_file($app);
    $self->_strip_htaccess($app);
    return 1;
}

# PassengerAppRoot is rejected inside .htaccess on EasyApache's Passenger.
# The root helper writes a Directory block into the domain's userdata include.
sub _apply_server {
    my ($self) = @_;
    my $bin = '/usr/local/nodeapps/bin/nodeapps-apply';
    die "The web server helper is not installed.\n" unless -x $bin;
    local $ENV{PATH} = '/usr/local/cpanel/bin:/usr/bin:/bin';
    my $rc;
    if ( $> == 0 ) {
        $rc = system( $bin, '--user=' . $self->{user} );
    }
    else {
        $rc = system( '/usr/bin/sudo', '-n', $bin );
    }
    die "Could not update the web server configuration.\n" if $rc != 0;
    return 1;
}

sub apache_userdata {
    my ($self) = @_;
    my %domains = map { $_->{domain} => $_ } @{ $self->list_domains };
    my %by_domain;
    my $data = $self->_load;
    foreach my $app ( @{ $data->{apps} } ) {
        next unless $app->{enabled};
        next unless $domains{ $app->{domain} };
        my $dir  = $self->_uri_dir($app);
        my $abs  = $self->_abs_root($app);
        my $node = File::Spec->catfile( $self->_node_bin( $app->{version} ), 'node' );
        foreach my $path ( $dir, $abs, $node ) {
            die "Application path is not allowed.\n" if $path =~ /["\r\n]/;
        }
        my $mode = $app->{mode} eq 'development' ? 'development' : 'production';
        $by_domain{ $app->{domain} } .= join "\n",
            '# nodeapps ' . $app->{id},
            '<Directory "' . $dir . '">',
            '    PassengerEnabled on',
            '    PassengerAppRoot "' . $abs . '"',
            '    PassengerBaseURI "' . $app->{uri} . '"',
            '    PassengerAppType node',
            '    PassengerStartupFile .nodeapps-passenger.cjs',
            '    PassengerNodejs "' . $node . '"',
            '    PassengerAppEnv ' . $mode,
            '</Directory>',
            '';
    }
    return \%by_domain;
}

sub _uri_dir {
    my ( $self, $app ) = @_;
    my $file = $self->_htaccess_file($app);
    my ( $vol, $dir ) = File::Spec->splitpath($file);
    return File::Spec->catpath( $vol, $dir, '' );
}

sub _strip_htaccess {
    my ( $self, $app ) = @_;
    my $file = eval { $self->_htaccess_file($app) } or return;
    return unless -f $file;
    open my $fh, '<', $file or return;
    local $/;
    my $existing = <$fh> // '';
    close $fh;
    my $updated = _strip_block( $existing, $app->{id} );
    return 1 if $updated eq $existing;
    open my $out, '>', $file or die "Could not update .htaccess: $!\n";
    print {$out} $updated;
    close $out;
    return 1;
}

sub _strip_block {
    my ( $text, $id ) = @_;
    $text =~ s/[ \t]*# BEGIN nodeapps \Q$id\E\n.*?# END nodeapps \Q$id\E\n?//s;
    return $text;
}

sub _touch_restart {
    my ( $self, $app ) = @_;
    my $abs = eval { $self->_abs_root($app) } or return;
    my $tmp = File::Spec->catdir( $abs, 'tmp' );
    make_path($tmp) unless -d $tmp;
    my $file = File::Spec->catfile( $tmp, 'restart.txt' );
    open my $fh, '>>', $file or return;
    close $fh;
    utime( undef, undef, $file );
    return 1;
}

sub _spawn {
    my ( $self, $app, $action, $cmd, $extra_env ) = @_;
    $action =~ /\A([a-z0-9-]+)\z/ or die "Unknown action.\n";
    $action = $1;
    my $existing = $self->job_status( $app->{id} );
    die "A task is already running for this application.\n" if $existing->{running};

    my $abs = $self->_abs_root($app);
    my $logdir = File::Spec->catdir( $abs, '.nodeapps-logs' );
    make_path($logdir) unless -d $logdir;
    my $log = File::Spec->catfile( $logdir, "$action.log" );
    $log = _untaint_abs($log) or die "Log path is not allowed.\n";
    open my $truncate, '>', $log or die "Could not open the log: $!\n";
    close $truncate;

    my @cmd = @{$cmd};
    my %allowed_flag = map { $_ => 1 } qw(--no-audit --no-fund);
    for my $i ( 0 .. $#cmd ) {
        my $part = $cmd[$i];
        die "Command is not allowed.\n" unless defined $part && $part =~ /\A([^\0]+)\z/;
        $part = $1;
        if ( $i == 0 ) {
            $part = _untaint_abs($part) or die "Command is not allowed.\n";
        }
        elsif ( $part =~ /^-/ ) {
            die "Command is not allowed.\n" unless $allowed_flag{$part};
        }
        else {
            die "Command is not allowed.\n" unless $part =~ /\A([A-Za-z0-9._+:-]{1,64})\z/;
            $part = $1;
        }
        $cmd[$i] = $part;
    }

    my $jobfile = $self->_job_file( $app->{id} );
    my $exitfile = $jobfile . '.exit';
    unlink $exitfile if -e $exitfile;
    my $pid = fork();
    die "Could not start the task.\n" unless defined $pid;
    if ( $pid == 0 ) {
        setsid();
        open STDIN,  '<',  '/dev/null';
        open STDOUT, '>>', $log;
        open STDERR, '>>', $log;
        $| = 1;
        my $nodebin = $self->_node_bin( $app->{version} );
        $ENV{PATH}     = "$nodebin:/usr/bin:/bin";
        $ENV{HOME}     = $self->{home};
        $ENV{NODE_ENV} = $app->{mode} eq 'development' ? 'development' : 'production';
        if ($extra_env) {
            foreach my $key ( keys %{$extra_env} ) {
                next unless $key =~ /\A([A-Za-z_][A-Za-z0-9_]*)\z/;
                $ENV{$1} = $extra_env->{$key};
            }
        }
        chdir $abs or do { print "chdir failed\n"; exit 1; };
        my $rc = system { $cmd[0] } @cmd;
        my $exit = $rc < 0 ? 127 : ( $rc >> 8 );
        if ( open my $ef, '>', $exitfile ) {
            print {$ef} "$exit\n";
            close $ef;
        }
        exit $exit;
    }

    _write_json( $jobfile, {
        app      => $app->{id},
        action   => $action,
        pid      => $pid,
        log      => "$action.log",
        running  => 1,
        started  => time,
        finished => undef,
        exit     => undef,
    } );
    return { id => $app->{id}, action => $action, pid => $pid, log => "$action.log" };
}

sub _job_file {
    my ( $self, $id ) = @_;
    $self->ensure_state;
    return File::Spec->catfile( $self->state_dir, "job-$id.json" );
}

sub _load {
    my ($self) = @_;
    $self->ensure_state;
    my $file = $self->apps_file;
    return { apps => [] } unless -f $file;
    my $data = _read_json($file) || { apps => [] };
    $data->{apps} = [] unless ref $data->{apps} eq 'ARRAY';
    return $data;
}

sub _save {
    my ( $self, $data ) = @_;
    $self->ensure_state;
    _write_json( $self->apps_file, $data );
    chmod 0600, $self->apps_file;
    return 1;
}

sub _find {
    my ( $self, $data, $id ) = @_;
    foreach my $app ( @{ $data->{apps} } ) {
        return $app if $app->{id} eq $id;
    }
    return;
}

sub _lock {
    my ($self) = @_;
    $self->ensure_state;
    my $path = File::Spec->catfile( $self->state_dir, 'lock' );
    open my $fh, '>>', $path or die "Could not lock application data: $!\n";
    flock( $fh, LOCK_EX ) or die "Could not lock application data: $!\n";
    return $fh;
}

sub _read_userdata {
    my ($path) = @_;
    open my $fh, '<', $path or return;
    my %info;
    while ( my $line = <$fh> ) {
        chomp $line;
        next unless $line =~ /\A([A-Za-z0-9_]+):\s*(.*)\z/;
        $info{$1} = $2;
    }
    close $fh;
    return \%info;
}

sub _read_json {
    my ($file) = @_;
    open my $fh, '<', $file or return;
    local $/;
    my $text = <$fh>;
    close $fh;
    return eval { JSON::PP->new->utf8->decode( $text // '' ) };
}

sub _write_json {
    my ( $file, $data ) = @_;
    my $json = JSON::PP->new->utf8->canonical->pretty->encode($data);
    my $tmp  = $file . '.tmp';
    open my $fh, '>', $tmp or die "Could not write $file: $!\n";
    print {$fh} $json;
    close $fh;
    rename $tmp, $file or die "Could not save $file: $!\n";
    return 1;
}

sub _write_if_missing {
    my ( $file, $contents ) = @_;
    return if -e $file;
    open my $fh, '>', $file or die "Could not write $file: $!\n";
    print {$fh} $contents;
    close $fh;
    chmod 0644, $file;
    return 1;
}

sub _clean_env {
    my ($env) = @_;
    $env = {} unless ref $env eq 'HASH';
    my %clean;
    foreach my $key ( sort keys %{$env} ) {
        next unless $key =~ /\A([A-Za-z_][A-Za-z0-9_]{0,63})\z/;
        my $name = $1;
        next if $name eq 'NODEAPPS_STARTUP';
        my $value = $env->{$key};
        $value = '' unless defined $value;
        $value =~ s/[\r\n\0]//g;
        die "Environment value for $name is too long.\n" if length($value) > 4096;
        $clean{$name} = $value;
    }
    return \%clean;
}

sub _normalize_uri {
    my ($uri) = @_;
    $uri = '/' unless defined $uri && $uri ne '';
    $uri = "/$uri" unless $uri =~ m{^/};
    $uri =~ s{/+}{/}g;
    $uri =~ s{/\z}{} unless $uri eq '/';
    die "Application URL path is not allowed.\n" unless $uri =~ m{\A/(?:[A-Za-z0-9._~+-]+/)*[A-Za-z0-9._~+-]*\z};
    die "Application URL path is not allowed.\n" if $uri =~ /\.\./;
    return $uri eq '' ? '/' : $uri;
}

sub _untaint_user {
    my ($user) = @_;
    return unless defined $user && $user =~ /\A([a-z_][a-z0-9_]{0,31})\z/;
    return $1;
}

sub _untaint_app_id {
    my ($id) = @_;
    return unless defined $id && $id =~ /\A([a-z0-9](?:[a-z0-9-]{0,31}))\z/;
    return $1;
}

sub _untaint_version {
    my ($version) = @_;
    return unless defined $version && $version =~ /\A(v\d+\.\d+\.\d+)\z/;
    return $1;
}

sub _untaint_domain {
    my ($domain) = @_;
    $domain = lc( $domain // '' );
    return unless $domain =~ /\A([a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)+)\z/;
    return $1;
}

sub _untaint_relative {
    my ($rel) = @_;
    return unless defined $rel;
    $rel =~ s{\\}{/}g;
    $rel =~ s{\A/+}{};
    $rel =~ s{/+\z}{};
    return unless $rel =~ m{\A([A-Za-z0-9._+=,-]+(?:/[A-Za-z0-9._+=,-]+)*)\z};
    $rel = $1;
    foreach my $part ( split m{/}, $rel ) {
        return if $part eq '.' || $part eq '..';
    }
    return $rel;
}

sub _untaint_startup {
    my ($file) = @_;
    return unless defined $file;
    $file =~ s{\\}{/}g;
    $file =~ s{\A/+}{};
    return unless $file =~ m{\A([A-Za-z0-9._+=,-]+(?:/[A-Za-z0-9._+=,-]+)*)\z};
    $file = $1;
    foreach my $part ( split m{/}, $file ) {
        return if $part eq '.' || $part eq '..';
    }
    return unless $file =~ /\.(?:js|cjs|mjs)\z/;
    return $file;
}

sub _untaint_script {
    my ($script) = @_;
    return unless defined $script && $script =~ /\A([A-Za-z0-9:_-]{1,64})\z/;
    return $1;
}

sub _untaint_abs {
    my ($path) = @_;
    return unless defined $path && $path =~ m{\A(/[A-Za-z0-9._+=,-/]+)\z};
    my $clean = $1;
    foreach my $part ( split m{/}, $clean ) {
        return if $part eq '..';
    }
    return $clean;
}

sub _account_home {
    my ($user) = @_;
    my $dir = ( getpwnam($user) )[7];
    die "Unknown account.\n" unless defined $dir && $dir ne '';
    $dir = _untaint_abs($dir) or die "Account home is not allowed.\n";
    die "Account home is not allowed.\n" unless -d $dir;
    return $dir;
}

sub _path_under {
    my ( $path, $home ) = @_;
    return 0 unless defined $path && defined $home && $path ne '';
    return 1 if $path eq $home;
    return index( $path, $home . '/' ) == 0;
}

sub _strict_under {
    my ( $path, $home ) = @_;
    return 0 unless defined $path && defined $home;
    return index( $path, $home . '/' ) == 0;
}

package NodeApps::Admin;

use strict;
use warnings;

use File::Path qw(make_path remove_tree);
use File::Spec ();
use HTTP::Tiny ();
use JSON::PP   ();

sub _root_only {
    die "This action requires root.\n" if $> != 0;
}

sub versions { NodeApps::list_versions() }

sub set_default {
    NodeApps::require_license();
    my ($version) = @_;
    _root_only();
    $version = NodeApps::_untaint_version($version) or die "Unknown Node.js version.\n";
    my $ok = grep { $_ eq $version } @{ NodeApps::list_versions() };
    die "Install that Node.js version first.\n" unless $ok;
    my $dir = NodeApps::prefix();
    make_path( $dir, { mode => 0755 } ) unless -d $dir;
    open my $fh, '>', NodeApps::default_file() or die "Could not save the default version: $!\n";
    print {$fh} "$version\n";
    close $fh;
    chmod 0644, NodeApps::default_file();
    return $version;
}

sub remove_version {
    NodeApps::require_license();
    my ($version) = @_;
    _root_only();
    $version = NodeApps::_untaint_version($version) or die "Unknown Node.js version.\n";
    my $users = _apps_using($version);
    die "This version is still used by: " . join( ', ', @{$users} ) . ".\n" if @{$users};
    my $dir = File::Spec->catdir( NodeApps::versiondir(), $version );
    die "That version is not installed.\n" unless -d $dir;
    remove_tree($dir);
    if ( NodeApps::default_version() eq $version ) {
        unlink NodeApps::default_file();
        my $left = NodeApps::list_versions();
        set_default( $left->[-1] ) if @{$left};
    }
    return 1;
}

sub install_version {
    NodeApps::require_license();
    my ($spec) = @_;
    _root_only();
    my $version = _resolve_remote($spec);
    my $dest = File::Spec->catdir( NodeApps::versiondir(), $version );
    if ( -x File::Spec->catfile( $dest, 'bin', 'node' ) ) {
        set_default($version) unless NodeApps::default_version();
        return $version;
    }
    make_path( NodeApps::versiondir(), { mode => 0755 } );
    my $name = "node-$version-linux-x64";
    my $url  = "https://nodejs.org/dist/$version/$name.tar.xz";
    my $tmp  = "/tmp/$name.tar.xz";
    my $http = HTTP::Tiny->new( timeout => 300 );
    my $res  = $http->mirror( $url, $tmp );
    die "Could not download $url: " . ( $res->{status} || 'network' ) . "\n" unless $res->{success};
    my $extract = NodeApps::versiondir();
    my $rc = system( '/usr/bin/tar', '-xJf', $tmp, '-C', $extract );
    unlink $tmp;
    die "Could not extract Node.js $version.\n" if $rc != 0;
    my $unpacked = File::Spec->catdir( $extract, $name );
    die "Node.js archive did not contain $name.\n" unless -d $unpacked;
    if ( -e $dest ) {
        remove_tree($dest);
    }
    rename $unpacked, $dest or die "Could not install Node.js $version: $!\n";
    my $node = File::Spec->catfile( $dest, 'bin', 'node' );
    die "Node.js binary is missing after install.\n" unless -x $node;
    system( $node, '-v' ) == 0 or die "Node.js $version failed to run.\n";
    set_default($version) unless NodeApps::default_version();
    return $version;
}

sub available {
    my ($spec) = @_;
    _root_only();
    return _index($spec);
}

sub ensure_passenger {
    _root_only();
    NodeApps::require_license();
    my $log = '/var/log/nodeapps-passenger.log';
    my $pid = fork();
    die "Could not start the Passenger install.\n" unless defined $pid;
    if ( $pid == 0 ) {
        open STDIN,  '<', '/dev/null';
        open STDOUT, '>', $log;
        open STDERR, '>&', \*STDOUT;
        exec '/usr/bin/dnf', '-y', 'install', 'ea-ruby27-mod_passenger', 'ea-apache24-mod_env';
        exit 127;
    }
    return { pid => $pid, log => $log };
}

sub _resolve_remote {
    my ($spec) = @_;
    $spec //= '';
    if ( $spec =~ /\A(v\d+\.\d+\.\d+)\z/ ) {
        return $1;
    }
    my $major = $spec eq '' ? '' : $spec;
    if ( $major ne '' && $major !~ /\A(\d{1,3})\z/ ) {
        die "Give a Node.js major version such as 22, or a full version such as v22.14.0.\n";
    }
    $major = $1 if $major ne '';
    my $rows = _index();
    my @match = @{$rows};
    if ( $major ne '' ) {
        @match = grep { $_->{version} =~ /^\Qv$major.\E/ } @match;
    }
    else {
        @match = grep { $_->{lts} } @match;
    }
    die "No matching Node.js release was published.\n" unless @match;
    return $match[0]->{version};
}

sub _index {
    my $http = HTTP::Tiny->new( timeout => 60 );
    my $res  = $http->get('https://nodejs.org/dist/index.json');
    die "Could not reach nodejs.org.\n" unless $res->{success};
    my $rows = JSON::PP->new->utf8->decode( $res->{content} );
    die "nodejs.org returned an unexpected list.\n" unless ref $rows eq 'ARRAY';
    my @clean;
    foreach my $row ( @{$rows} ) {
        next unless $row->{version} && $row->{version} =~ /\A(v\d+\.\d+\.\d+)\z/;
        push @clean, { version => $1, lts => $row->{lts} ? 1 : 0 };
    }
    return \@clean;
}

sub _apps_using {
    my ($version) = @_;
    my @hits;
    my $users_dir = '/var/cpanel/users';
    return \@hits unless -d $users_dir;
    opendir my $dh, $users_dir or return \@hits;
    foreach my $name ( readdir $dh ) {
        next if $name =~ /^\./;
        next if $name eq 'system';
        my $user = NodeApps::_untaint_user($name) or next;
        my $home = eval { NodeApps::_account_home($user) } or next;
        my $file = File::Spec->catfile( $home, '.nodeapps', 'apps.json' );
        next unless -f $file;
        my $data = NodeApps::_read_json($file) || next;
        foreach my $app ( @{ $data->{apps} || [] } ) {
            push @hits, "$user/" . ( $app->{id} || '?' ) if ( $app->{version} || '' ) eq $version;
        }
    }
    closedir $dh;
    return \@hits;
}

1;
