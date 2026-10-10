package Dashboard::TestData;
use v5.40;
use Exporter 'import';
our @EXPORT_OK = qw(release client);

sub release (%args) {
  return Dashboard::TestData::Release->new(
    name => 'Example-1.0', distribution => 'Example', main_module => 'Example',
    version => '1.0', author => 'EXAMPLE', date => '2026-10-10T00:00:00',
    resources => {}, %args,
  );
}

sub client (%args) {
  return bless { name => 'Example Author', gravatar_url => undef,
    releases => [release()], %args }, 'Dashboard::TestData::Client';
}

package Dashboard::TestData::Client;
sub author ($self, $id) {
  ++$self->{calls};
  if (my $error = shift @{ $self->{errors} // [] }) { die $error }
  return bless { %$self }, 'Dashboard::TestData::Author';
}

package Dashboard::TestData::Author;
sub name ($self) { $self->{name} }
sub gravatar_url ($self) { $self->{gravatar_url} }
sub releases ($self) {
  return bless { items => [@{ $self->{releases} }], error => $self->{iterator_error} },
    'Dashboard::TestData::Releases';
}

package Dashboard::TestData::Releases;
sub next ($self) {
  return shift @{ $self->{items} } if @{ $self->{items} };
  die $self->{error} if $self->{error};
  return;
}

package Dashboard::TestData::Release;
sub new ($class, %args) { bless \%args, $class }
sub name ($self) { $self->{name} }
sub distribution ($self) { $self->{distribution} }
sub main_module ($self) { $self->{main_module} }
sub version ($self) { $self->{version} }
sub author ($self) { $self->{author} }
sub date ($self) { $self->{date} }
sub resources ($self) { $self->{resources} }

1;
