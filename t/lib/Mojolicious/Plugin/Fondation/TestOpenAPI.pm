package Mojolicious::Plugin::Fondation::TestOpenAPI;

# ABSTRACT: Test plugin providing DBIx::Class Result classes for OpenAPI tests

use Mojo::Base 'Mojolicious::Plugin', -signatures;

sub fondation_meta {
    return {
        dependencies     => ['Fondation::Model::DBIx::Async'],
        defaults     => {
            openapi_exclude => ['bazs'],
            models          => {
                foo => {source => 'foos', backend => 'test'},
                bar => {source => 'bars', backend => 'test'},
                baz => {source => 'bazs', backend => 'test'},
            },
        },
    };
}

sub register ($self, $app, $conf) {
    return $self;
}

1;
