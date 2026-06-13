package Mojolicious::Plugin::Fondation::OpenAPI::Security;
use Mojo::Base -base, -signatures;

# ABSTRACT: Authorization enforcement for OpenAPI routes via x-auth

our $VERSION = '0.01';

sub register ($self, $app, $config) {
    my $openapi = $config->{openapi}
        or return;

    return $openapi->route(
        $openapi->route->under('/')->to(cb => sub {
            my $c = shift;
            return 1 if $c->req->method eq 'OPTIONS';

            my $op_spec = $c->openapi->spec || {};
            my $x_auth  = $op_spec->{'x-auth'} || {};
            #$c->app->log->info('[Security] op_spec keys: ' . join(', ', sort keys %$op_spec));
            #$c->app->log->info('[Security] x-auth: ' . $c->dumper($x_auth));

            # No x-auth → public endpoint
            return 1 unless %$x_auth;

            # Check permissions
            if (my $permissions = $x_auth->{permissions}) {
                for my $perm (@$permissions) {
                    if ($c->has_helper('check_perm')) {
                        unless ($c->check_perm($perm)) {
                            return $self->_forbidden(
                                $c, "Permission '$perm' required");
                        }
                    }
                }
            }

            # Check groups
            if (my $groups = $x_auth->{groups}) {
                for my $group (@$groups) {
                    if ($c->has_helper('check_group')) {
                        unless ($c->check_group($group)) {
                            return $self->_forbidden(
                                $c, "Group '$group' required");
                        }
                    }
                }
            }

            $c->app->log->info('[Security] All checks passed');
            return 1;
        }));
}

sub _forbidden ($self, $c, $message) {
    $c->render(
        openapi => {
            errors => [{message => $message, path => '/x-auth'}],
        },
        status => 403,
    );
    return undef;
}

1;

=encoding utf8

=head1 NAME

Mojolicious::Plugin::Fondation::OpenAPI::Security - Authorization enforcement for OpenAPI routes via x-auth

=head1 DESCRIPTION

This is an OpenAPI sub-plugin (loaded via the C<plugins> option of
L<Mojolicious::Plugin::OpenAPI>). It wraps all OpenAPI routes with an
C<under> condition that reads the C<x-auth> extension from the current
operation spec and enforces permissions and group membership.

=head1 OPERATION

For each request to an OpenAPI-managed route, the plugin:

=over

=item 1. Reads the current operation spec via C<< $c->openapi->spec >>

=item 2. Looks for an C<x-auth> key

=item 3. Calls C<< $c->check_perm($permission) >> for each entry in
C<x-auth.permissions>

=item 4. Calls C<< $c->check_group($group) >> for each entry in
C<x-auth.groups>

=item 5. Returns a 403 with a standardised OpenAPI error body on failure

=back

If no C<x-auth> is present (public endpoint or generator omitted it),
the request proceeds without checks.

The C<check_perm> and C<check_group> helpers are provided by Fondation
core as no-ops. A future C<Fondation::Authorization> plugin overrides
them with real logic. If neither helper exists (checked via
C<has_helper>), checks are silently skipped.

=head1 CONFIGURATION

This plugin requires no explicit configuration. It is loaded by
C<Fondation::OpenAPI> during C<fondation_finalyze>:

    $app->plugin(OpenAPI => {
        url     => $spec_file,
        plugins => [
            '+Security',
            'Mojolicious::Plugin::Fondation::OpenAPI::Security',
        ],
    });

=head1 SEE ALSO

L<Mojolicious::Plugin::Fondation::OpenAPI>,
L<Mojolicious::Plugin::OpenAPI::Security>,
L<Mojolicious::Plugin::OpenAPI>

=cut
