package Mojolicious::Plugin::Fondation::OpenAPI::Action::OpenAPIRoutes;

# ABSTRACT: Scans all plugins for share/routes.yaml and merges custom API routes

use Mojo::Base 'Mojolicious::Plugin::Fondation::Action::Base', -signatures;
use YAML::XS qw(LoadFile);

# ---------------------------------------------------------------------------
# after_load — called by Fondation Manager for each plugin
# ---------------------------------------------------------------------------

sub after_load ($self, $long, $conf, $share_dir) {
    return unless $share_dir && -d $share_dir;

    my $routes_file = $share_dir->child('routes.yaml');
    return unless -f $routes_file;

    my $routes = eval { LoadFile($routes_file->to_string) };
    unless ($routes && ref $routes eq 'HASH') {
        $self->log->warn("[$long] Invalid share/routes.yaml: $@");
        return;
    }

    my $manager = $self->manager;
    my $app     = $manager->app;
    $app->{openapi_routes} //= {};

    # Merge: last plugin wins for duplicate paths
    %{$app->{openapi_routes}} = (%{$app->{openapi_routes}}, %$routes);

    my $count = scalar keys %$routes;
    $self->log->debug("[$long] $count route(s) from share/routes.yaml");
}

1;
