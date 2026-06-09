#!/usr/bin/env perl

use strict;
use warnings;
use Test::More;
use Mojo::File 'path';
use Mojo::JSON qw(encode_json decode_json);
use File::Temp 'tempdir';
use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/lib";
use lib "$FindBin::Bin/../../Mojolicious-Plugin-Fondation/lib";

use Mojolicious::Plugin::Fondation::TestHelper qw(create_test_app);

# ==========================================================================
# 1. No spec file → warning, no crash
# ==========================================================================

{
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
                },
            }},
            {'Fondation::TestOpenAPI' => {}},
            {'Fondation::OpenAPI' => {}},
        ],
    });

    my $c = $app->build_controller;
    ok(!$c->has_helper('openapi.validate'), 'openapi helper not registered without spec');
}

# ==========================================================================
# 2. Spec file exists → OpenAPI plugin loaded
# ==========================================================================

{
    my $tmpdir = tempdir(CLEANUP => 1);
    my $dbfile = "$tmpdir/test.db";
    my $app    = create_test_app($tmpdir);

    # MUST create spec BEFORE plugin loading
    my $spec_dir = $app->home->child('share');
    $spec_dir->make_path;
    $spec_dir->child('openapi.json')->spew(encode_json({
        openapi => '3.0.3',
        info    => { title => 'Test', version => '1.0' },
        paths   => {},
    }));

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
                },
            }},
            {'Fondation::TestOpenAPI' => {}},
            {'Fondation::OpenAPI' => {}},
        ],
    });

    my $c = $app->build_controller;
    ok($c->has_helper('openapi.validate'), 'openapi helper registered with spec');
}

# ==========================================================================
# 3. Development mode → Swagger UI routes added
# ==========================================================================

{
    my $tmpdir = tempdir(CLEANUP => 1);
    my $dbfile = "$tmpdir/test.db";
    my $app    = create_test_app($tmpdir);
    $app->mode('development');

    # MUST create spec BEFORE plugin loading
    my $spec_dir = $app->home->child('share');
    $spec_dir->make_path;
    $spec_dir->child('openapi.json')->spew(encode_json({
        openapi => '3.0.3',
        info    => { title => 'Test', version => '1.0' },
        paths   => {},
    }));

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
                },
            }},
            {'Fondation::TestOpenAPI' => {}},
            {'Fondation::OpenAPI' => {}},
        ],
    });

    ok(defined $app->routes->find('swagger'), 'GET /swagger route exists in dev mode');

    # /openapi.json route — find by scanning children (dot in name tricky for find())
    my $found_json = 0;
    for my $child (@{$app->routes->children}) {
        my $p = $child->pattern->unparsed // '';
        if ($p eq '/openapi.json') {
            $found_json = 1;
            last;
        }
    }
    ok($found_json, 'GET /openapi.json route exists in dev mode');
}

# ==========================================================================
# 4. Production mode → no Swagger UI routes
# ==========================================================================

{
    my $tmpdir = tempdir(CLEANUP => 1);
    my $dbfile = "$tmpdir/test.db";
    my $app    = create_test_app($tmpdir);
    $app->mode('production');

    # MUST create spec BEFORE plugin loading
    my $spec_dir = $app->home->child('share');
    $spec_dir->make_path;
    $spec_dir->child('openapi.json')->spew(encode_json({
        openapi => '3.0.3',
        info    => { title => 'Test', version => '1.0' },
        paths   => {},
    }));

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
                },
            }},
            {'Fondation::TestOpenAPI' => {}},
            {'Fondation::OpenAPI' => {}},
        ],
    });

    my $swagger = $app->routes->find('swagger');
    ok(!defined $swagger, 'no GET /swagger route in production mode');
}

done_testing;
