package Cpanel::API::NodeApp;

use strict;
use warnings;

our $VERSION = '1.0.0';

use Cpanel          ();
use Cpanel::API     ();
use JSON::PP        ();

use lib '/usr/local/nodeapps/lib';
use NodeApps ();

my $FEATURE = 'nodeapps';

sub list_apps      { _run( @_, sub { $_[0]->list_apps } ) }
sub list_versions  { _run( @_, sub { { versions => NodeApps::list_versions(), default_version => NodeApps::default_version() } } ) }
sub list_domains   { _run( @_, sub { $_[0]->list_domains } ) }
sub system_status  { _run( @_, sub { $_[0]->system_status } ) }
sub restart_app    { _run( @_, sub { my ( $app, %in ) = @_; $app->restart_app( $in{id} ) } ) }
sub run_npm_install { _run( @_, sub { my ( $app, %in ) = @_; $app->run_npm_install( $in{id} ) } ) }
sub run_next_build { _run( @_, sub { my ( $app, %in ) = @_; $app->run_next_build( $in{id} ) } ) }
sub job_status     { _run( @_, sub { my ( $app, %in ) = @_; $app->job_status( $in{id} ) } ) }
sub read_log       { _run( @_, sub { my ( $app, %in ) = @_; { log => $app->read_log( $in{id}, $in{which} ) } } ) }

sub create_app {
    _run( @_, sub {
        my ( $app, %in ) = @_;
        return $app->create_app(
            id       => $in{id},
            type     => $in{type},
            mode     => $in{mode},
            root     => $in{root},
            domain   => $in{domain},
            uri      => $in{uri},
            startup  => $in{startup},
            version  => $in{version},
            env      => _env( $in{env_json} ),
            scaffold => defined $in{scaffold} ? $in{scaffold} : 1,
        );
    } );
}

sub update_app {
    _run( @_, sub {
        my ( $app, %in ) = @_;
        return $app->update_app(
            id      => $in{id},
            mode    => $in{mode},
            domain  => $in{domain},
            uri     => $in{uri},
            startup => $in{startup},
            version => $in{version},
            env     => _env( $in{env_json} ),
        );
    } );
}

sub set_enabled {
    _run( @_, sub {
        my ( $app, %in ) = @_;
        return $app->set_enabled( $in{id}, $in{enabled} );
    } );
}

sub delete_app {
    _run( @_, sub {
        my ( $app, %in ) = @_;
        return $app->delete_app( $in{id}, $in{remove_files} );
    } );
}

sub run_script {
    _run( @_, sub {
        my ( $app, %in ) = @_;
        return $app->run_script( $in{id}, $in{script} );
    } );
}

sub _run {
    my ( $args, $result, $code ) = @_;
    if ( !main::hasfeature($FEATURE) ) {
        $result->error('_ERROR_FEATURE');
        return 0;
    }
    if ( eval { $Cpanel::CPDATA{'DEMO'} } ) {
        $result->error('_ERROR_DEMO_MODE');
        return 0;
    }

    my $user = $Cpanel::user || '';
    my $home = $Cpanel::homedir || '';
    my $manager = eval { NodeApps->new( user => $user, homedir => $home ) };
    if ( !$manager ) {
        $result->raw_error( $@ || 'Could not open this account.' );
        return 0;
    }

    my %in;
    foreach my $key (qw(id type mode root domain uri startup version env_json enabled remove_files scaffold script which)) {
        my ($value) = $args->get($key);
        $in{$key} = $value if defined $value;
    }

    my $data = eval { $code->( $manager, %in ) };
    if ($@) {
        my $err = $@;
        $err =~ s/\s+\z//;
        $result->raw_error($err);
        return 0;
    }
    $result->data($data);
    return 1;
}

sub _env {
    my ($json) = @_;
    return {} unless defined $json && $json ne '' && $json ne '[]' && $json ne 'null';
    my $data = eval { JSON::PP->new->utf8->decode($json) };
    return {} if !$@ && ref $data eq 'ARRAY' && !@{$data};
    die "Environment variables must be valid JSON.\n" if $@ || ref $data ne 'HASH';
    return $data;
}

1;
