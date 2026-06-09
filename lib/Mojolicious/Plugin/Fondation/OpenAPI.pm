package Mojolicious::Plugin::Fondation::OpenAPI;
use Mojo::Base 'Mojolicious::Plugin', -signatures;

our $VERSION = '0.01';

use Mojo::JSON qw(decode_json);
use Mojo::File 'path';

# ABSTRACT: OpenAPI specification generator and runtime validator for Fondation applications

sub fondation_meta {
    return {
        dependencies => ['Fondation::Model::DBIx::Async'],
        defaults     => { backend => undef },
    };
}

=head1 NAME

Mojolicious::Plugin::Fondation::OpenAPI - OpenAPI specification generator and runtime validator for Fondation applications

=head1 SYNOPSIS

  # In myapp.conf
  'Fondation::OpenAPI' => {
      backend => 'main',
      schemas => {
          User => {
              columns => {
                  password => {
                      writeOnly => 1,
                      create    => { required => 1 },
                      update    => { required => 0 },
                  },
              },
          },
      },
  }

  # CLI
  $ myapp.pl openapi generate
  $ myapp.pl openapi generate -y
  $ myapp.pl openapi generate --output custom.json

=head1 DESCRIPTION

This plugin provides the C<openapi generate> command to produce an
OpenAPI 3.0.3 specification from DBIx::Class sources. At runtime,
C<fondation_finalyze> loads the generated C<share/openapi.json> via
L<Mojolicious::Plugin::OpenAPI> for request validation and adds
Swagger UI routes in development mode.

=head1 CONFIGURATION

=head2 Plugin config

  'Fondation::OpenAPI' => {
      backend => 'main',          # optional — falls back to DBIx::Async default
      schemas => { ... },         # optional — column overrides
  }

=head2 Backend resolution

The backend name is resolved in this order:

=over

=item 1. OpenAPI's own C<backend> config

=item 2. DBIx::Async's C<default_backend> config key

=item 3. First backend in DBIx::Async's C<backends> array

=back

=head2 Schema config override

Any column property can be overridden via C<schemas> without modifying
DBIx Result classes. See L<Mojolicious::Plugin::Fondation::OpenAPI::Command::openapi>
for the full list of supported keys.

=head1 DEPENDENCIES

This plugin requires L<Fondation::Model::DBIx::Async>.

=head1 COMMANDS

=head2 openapi generate

Generates C<share/openapi.json> and C<public/js/validators.js> from
DBIx::Class sources discovered via the configured backend.

Options: C<-y> (overwrite without prompt), C<--output> (custom path).

=head1 RUNTIME

On startup (C<fondation_finalyze>), if C<share/openapi.json> exists it
is loaded via L<Mojolicious::Plugin::OpenAPI> for request validation.
Swagger UI routes (C</swagger> and C</openapi.json>) are added in
development mode. If the spec is missing, a warning is logged and
startup continues.

=head1 OUTPUT FILES

=over

=item C<share/openapi.json>

OpenAPI 3.0.3 specification with API Base schemas, contextual
projections (only when different), and CRUD paths. Committed to the
application repository.

=item C<public/js/validators.js>

Client-side form validation via C<FondationValidators.validate()>.
Consumed by L<Fondation::Asset> bundles. Committed to the application
repository.

=back

Always run C<openapi generate> before C<asset generate>.

=head1 SEE ALSO

L<Mojolicious::Plugin::Fondation::OpenAPI::Command::openapi>,
L<Fondation::Model::DBIx::Async>,
L<Mojolicious::Plugin::OpenAPI>

=cut

sub register ($self, $app, $conf = {}) {
    $app->defaults('openapi.config' => {
        backend => $conf->{backend},
        schemas => $conf->{schemas} // {},
    });

    push @{$app->commands->namespaces},
        'Mojolicious::Plugin::Fondation::OpenAPI::Command';

    return $self;
}

sub fondation_finalyze ($self, $app, $long_name) {
    my $spec_file = $app->home->child('share', 'openapi.json');

    unless (-f $spec_file) {
        $self->log->warn(
            "No spec found at $spec_file. "
            . "Run 'openapi generate' first."
        );
        return;
    }

    # Load the OpenAPI plugin with the generated spec
    $app->plugin(OpenAPI => { url => $spec_file->to_string });
    $self->log->debug("OpenAPI plugin loaded from $spec_file");

    # Swagger UI in development mode
    if ($app->mode eq 'development') {
        $app->routes->get('/swagger')->to(cb => sub {
            my $c = shift;
            $c->stash(openapi_url => '/openapi.json');
            $c->render(template => 'swagger');
        });

        $app->routes->get('/openapi.json')->to(cb => sub {
            my $c = shift;
            $c->render(json => decode_json($spec_file->slurp));
        });
    }
}

1;
