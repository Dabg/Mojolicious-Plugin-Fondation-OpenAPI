#!/usr/bin/env perl

use strict;
use warnings;
use Test::More;
use Mojo::JSON qw(decode_json);
use File::Temp 'tempdir';
use FindBin;

use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/lib";
use lib "$FindBin::Bin/../../Mojolicious-Plugin-Fondation/lib";

use Mojolicious::Plugin::Fondation::TestHelper qw(create_test_app);

# ==========================================================================
# Helper: build a test app with OpenAPI plugin + custom routes fixture
# ==========================================================================

sub build_app {
    my $tmpdir = tempdir(CLEANUP => 1);
    my $dbfile = "$tmpdir/test.db";
    my $app    = create_test_app($tmpdir);

    $app->plugin('Fondation' => {
        dependencies => [
            {'Fondation::Model::DBIx::Async' => {
                backends => [
                    test => {
                        dsn          => "dbi:SQLite:dbname=$dbfile",
                        schema_class => 'TestSchema',
                        workers      => 1,
                    },
                ],
                models => {
                    foo => {source => 'foos'},
                    bar => {source => 'bars'},
                },
            }},
            {'Fondation::TestOpenAPI' => {
                share_dir => "$FindBin::Bin/share/fondation/test_openapi",
            }},
            {'Fondation::OpenAPI' => {}},
        ],
    });

    return $app;
}

# ==========================================================================
# Helper: generate spec via internal methods (avoid exit())
# ==========================================================================

sub generate_spec {
    my ($app) = @_;

    my $config = $app->defaults->{'openapi.config'};
    require Mojolicious::Plugin::Fondation::OpenAPI::Command::openapi;
    my $cmd = Mojolicious::Plugin::Fondation::OpenAPI::Command::openapi->new(app => $app);

    my $schema_class = $cmd->_get_schema_class($app, $config);
    return $cmd->_build_spec($schema_class, $app, $config);
}

# ==========================================================================
# 1. Custom routes are merged into spec
# ==========================================================================

{
    my $app  = build_app;
    my $spec = generate_spec($app);

    # Check custom routes exist
    ok(exists $spec->{paths}{'/api/status'},
        '/api/status custom route exists');
    ok(exists $spec->{paths}{'/api/export'},
        '/api/export custom route exists');

    # Check CRUD routes still exist (from TestOpenAPI sources)
    ok(exists $spec->{paths}{'/foo'},
        'CRUD route /foo still exists');

    # Verify /api/status structure
    my $status = $spec->{paths}{'/api/status'}{get};
    is($status->{summary},                'Health check', 'status summary');
    is($status->{operationId},            'health_check', 'status operationId');
    is($status->{'x-mojo-to'},            'Status#check', 'status x-mojo-to');
    is_deeply($status->{'x-auth'}, {},   'status x-auth empty (public)');

    # Verify /api/export structure
    my $export = $spec->{paths}{'/api/export'}{post};
    is($export->{summary},                 'Export data',    'export summary');
    is($export->{operationId},             'export_create',  'export operationId');
    is($export->{'x-mojo-to'},             'Export#create',  'export x-mojo-to');
    is_deeply($export->{'x-auth'},         {permissions => ['export_create']},
        'export x-auth');
    ok($export->{requestBody}{required},   'export requestBody required');
    my $schema = $export->{requestBody}{content}{'application/json'}{schema};
    is_deeply($schema->{required},         ['format'], 'export format required');
    is_deeply($schema->{properties}{format}{enum}, ['csv', 'json', 'xlsx'],
        'export format enum');

    # Check CRUD x-auth still works
    my $foo_list = $spec->{paths}{'/foo'}{get};
    is_deeply($foo_list->{'x-auth'}, {permissions => ['foo_list']},
        'CRUD x-auth foo_list still present');
}

# ==========================================================================
# 2. Custom route overwrites CRUD route on same path
# ==========================================================================

{
    my $app  = build_app;
    my $spec = generate_spec($app);

    # /api/status is custom only — should NOT have CRUD stuff
    my $status = $spec->{paths}{'/api/status'};
    ok(!exists $status->{post},    'no POST on /api/status (custom only)');
    ok(!exists $status->{put},     'no PUT on /api/status');
    ok(!exists $status->{delete},  'no DELETE on /api/status');
    ok(exists $status->{get},      'GET on /api/status (from custom)');
}

# ==========================================================================
# 3. openapi_routes is populated on $app
# ==========================================================================

{
    my $app  = build_app;
    my $spec = generate_spec($app);

    my $routes = $app->{openapi_routes};
    ok($routes, 'openapi_routes exists');
    is(scalar keys %$routes, 2, '2 custom routes collected');
}

done_testing;
