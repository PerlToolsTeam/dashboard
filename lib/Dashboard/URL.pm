package Dashboard::URL;
use v5.40;
use Exporter 'import';
use URI;
our @EXPORT_OK = qw(resource_url);

# Generic display-link validation belongs to the dashboard, not the VCS model.
sub resource_url ($url) {
  return unless defined($url) && !ref($url) && $url !~ /[\x00-\x1f\x7f]/;
  my $uri = URI->new($url);
  return unless $uri->scheme && $uri->scheme =~ /\Ahttps?\z/i
    && $uri->can('host') && defined($uri->host) && length($uri->host)
    && $uri->host !~ /[\x00-\x20\x7f<>"']/;
  return $uri->as_string;
}
1;
