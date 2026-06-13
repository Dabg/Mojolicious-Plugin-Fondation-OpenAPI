#!/usr/bin/env perl

use strict;
use warnings;
use Test::More;
use Mojo::File 'path';
use Mojo::JSON qw(encode_json decode_json true);
use Test::Mojo;
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

    # /openapi.json route -- find by scanning children (dot in name tricky for find())
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

# ==========================================================================
# 5. x-auth permission enforcement via Security sub-plugin
# ==========================================================================

{
    my $tmpdir = tempdir(CLEANUP => 1);
    my $app    = create_test_app($tmpdir);

    # Load Fondation core for has_helper (used by Security sub-plugin)
    $app->plugin('Fondation');

    # Build a minimal spec with x-auth on some routes, none on /public
    my $spec = {
        openapi => '3.0.3',
        info    => {title => 'Security Test', version => '1.0'},
        servers => [{url => ''}],
        paths   => {
            '/protected' => {
                get => {
                    operationId => 'protected_list',
                    'x-auth'    => {permissions => ['protected_read']},
                    responses   => {'200' => {description => 'OK'}},
                },
            },
            '/public' => {
                get => {
                    operationId => 'public_list',
                    responses   => {'200' => {description => 'OK'}},
                },
            },
        },
    };

    my $spec_file = $app->home->child('share', 'openapi.json');
    $spec_file->dirname->make_path;
    $spec_file->spew(encode_json($spec));

    # Register named routes BEFORE loading OpenAPI (plugin will discover them)
    my $r = $app->routes;
    $r->get('/protected')->to(cb => sub {
        shift->render(openapi => {status => 'ok'}, status => 200);
    })->name('protected_list');

    $r->get('/public')->to(cb => sub {
        shift->render(openapi => {status => 'ok'}, status => 200);
    })->name('public_list');

    # Mock check_perm via package variable
    our $perm_allowed = 1;
    $app->helper(check_perm => sub { return $perm_allowed });

    $app->plugin(OpenAPI => {
        url     => $spec_file->to_string,
        plugins => [
            'Mojolicious::Plugin::Fondation::OpenAPI::Security',
        ],
    });

    my $t = Test::Mojo->new($app);

    # Public endpoint works (no x-auth)
    $t->get_ok('/public')->status_is(200)
        ->json_is('/status', 'ok');

    # Protected endpoint works when check_perm returns true
    $perm_allowed = 1;
    $t->get_ok('/protected')->status_is(200)
        ->json_is('/status', 'ok');

    # Protected endpoint returns 403 when check_perm returns false
    $perm_allowed = 0;
    $t->get_ok('/protected')->status_is(403);

    # Verify OpenAPI error format
    my $body = decode_json($t->tx->res->body);
    is_deeply(
        $body->{errors}->[0],
        {message => "Permission 'protected_read' required", path => '/x-auth'},
        '403 response uses OpenAPI error format with x-auth path'
    );
}

# ==========================================================================
# 6. Custom routes from routes.yaml: x-auth + validation at runtime
# ==========================================================================

{
    my $tmpdir = tempdir(CLEANUP => 1);
    my $app    = create_test_app($tmpdir);

    # Load Fondation core for has_helper (used by Security sub-plugin)
    $app->plugin('Fondation');

    # Build a spec with custom routes that mirror the routes.yaml fixture
    my $spec = {
        openapi => '3.0.3',
        info    => {title => 'Custom Routes Test', version => '1.0'},
        servers => [{url => ''}],
        paths   => {
            '/api/status' => {
                get => {
                    summary     => 'Health check',
                    operationId => 'health_check',
                    responses   => {
                        '200' => {
                            description => 'OK',
                            content     => {
                                'application/json' => {
                                    schema => {
                                        type       => 'object',
                                        properties => {uptime => {type => 'integer'}},
                                    },
                                },
                            },
                        },
                    },
                },
            },
            '/api/export' => {
                post => {
                    summary     => 'Export data',
                    operationId => 'export_create',
                    'x-auth'    => {permissions => ['export_create']},
                    requestBody => {
                        required => true,
                        content  => {
                            'application/json' => {
                                schema => {
                                    type       => 'object',
                                    required   => ['format'],
                                    properties => {
                                        format => {
                                            type => 'string',
                                            enum => ['csv', 'json', 'xlsx'],
                                        },
                                    },
                                },
                            },
                        },
                    },
                    responses => {'200' => {description => 'Export ready'}},
                },
            },
            '/api/public-xauth' => {
                get => {
                    summary     => 'Public via x-auth empty',
                    operationId => 'public_xauth_list',
                    'x-auth'    => {},
                    responses   => {'200' => {description => 'OK'}},
                },
            },
        },
    };

    my $spec_file = $app->home->child('share', 'openapi.json');
    $spec_file->dirname->make_path;
    $spec_file->spew(encode_json($spec));

    # Register named routes BEFORE loading OpenAPI (plugin discovers them)
    my $r = $app->routes;
    $r->get('/api/status')->to(cb => sub {
        shift->render(openapi => {uptime => 42}, status => 200);
    })->name('health_check');

    $r->post('/api/export')->to(cb => sub {
        my $c = shift;
        $c = $c->openapi->valid_input or return;
        $c->render(openapi => {status => 'ok'}, status => 200);
    })->name('export_create');

    $r->get('/api/public-xauth')->to(cb => sub {
        shift->render(openapi => {status => 'ok'}, status => 200);
    })->name('public_xauth_list');

    # Mock check_perm
    our $custom_perm_allowed = 1;
    $app->helper(check_perm => sub { return $custom_perm_allowed });

    $app->plugin(OpenAPI => {
        url     => $spec_file->to_string,
        plugins => [
            'Mojolicious::Plugin::Fondation::OpenAPI::Security',
        ],
    });

    my $t = Test::Mojo->new($app);

    # ── /api/status (public, no x-auth) ──
    $t->get_ok('/api/status')->status_is(200)
        ->json_is('/uptime', 42, 'public custom route without x-auth');

    # ── /api/export denied without permission ──
    $custom_perm_allowed = 0;
    $t->post_ok('/api/export' => json => {format => 'csv'})
        ->status_is(403, 'custom route blocked without permission');

    # ── /api/export allowed with permission ──
    $custom_perm_allowed = 1;
    $t->post_ok('/api/export' => json => {format => 'csv'})
        ->status_is(200, 'custom route allowed with permission')
        ->json_is('/status', 'ok');

    # ── /api/export validation fails on bad enum ──
    $t->post_ok('/api/export' => json => {format => 'xml'})
        ->status_is(400, 'custom route validation rejects bad enum value');

    # ── /api/export validation fails on missing required field ──
    $t->post_ok('/api/export' => json => {})
        ->status_is(400, 'custom route validation rejects missing required field');

    # ── /api/public-xauth (x-auth: {}) accessible without perm ──
    $custom_perm_allowed = 0;
    $t->get_ok('/api/public-xauth')->status_is(200)
        ->json_is('/status', 'ok', 'x-auth: {} is public, accessible with check_perm=0');

    $custom_perm_allowed = 1;
    $t->get_ok('/api/public-xauth')->status_is(200)
        ->json_is('/status', 'ok', 'x-auth: {} is public, accessible with check_perm=1');
}

done_testing;
