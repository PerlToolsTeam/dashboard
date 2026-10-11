use v5.40;
use feature 'class';
no warnings 'experimental::class';

class VCS::Repository {
  use URI;

  our $VERSION = '0.001';
  field $name :param :reader = undef;
  field $type :param :reader = undef;
  field $host :param :reader = undef;
  field $hostname :param :reader = undef;
  field $owner :param :reader = undef;
  field $raw_url :param :reader = undef;
  field $path :param :reader = undef;

  my %services = (github => ['GitHub', 'github.com'],
    gitlab => ['GitLab', 'gitlab.com'], bitbucket => ['Bitbucket', 'bitbucket.org']);
  my %domains = map { $services{$_}[1] => $services{$_}[0] } keys %services;

  sub component ($value) {
    return defined($value) && !ref($value) && $value =~ /\A[A-Za-z0-9_.~-]+\z/
      && $value ne '.' && $value ne '..';
  }

  sub namespace ($value) {
    return defined($value) && !ref($value) && length($value)
      && !grep { !component($_) } split m{/}, $value, -1;
  }

  # A tolerant factory for untrusted metadata. Constructors with explicit fields
  # report errors; unsafe or malformed metadata URLs yield no object.
  sub from_url ($class, $url, %args) {
    return undef unless defined($url) && !ref($url) && length($url);
    return eval { $class->new(raw_url => $url, %args) };
  }

  ADJUST {
    for my $value ($name, $type, $host, $hostname, $owner, $raw_url, $path) {
      die "Invalid repository field\n" if defined($value)
        && (ref($value) || $value =~ /[\x00-\x20\x7f]/);
    }
    if (defined $host) {
      $host = $services{lc $host}[0] if exists $services{lc $host};
    }
    if (defined $type) {
      die "Unsupported repository type '$type'\n" unless $type =~ /\A(?:git|svn|subversion)\z/i;
      $type = lc($type) eq 'git' ? 'Git' : 'Subversion';
    }
    if (defined $raw_url) {
      die "Invalid repository URL\n" unless length $raw_url;
      my $parse_url = $raw_url;
      $parse_url =~ s{\Agit\@([^/:]+):}{ssh://git\@$1/};
      my ($scheme) = $parse_url =~ m{\A(https?|git|git\+ssh|ssh|svn|svn\+ssh)://}i;
      die "Unsupported repository URL\n" unless defined $scheme;
      $scheme = lc $scheme;
      # URI's generic transport handlers do not expose authority accessors.
      $parse_url =~ s{\A[^:]+://}{https://};
      my $uri = URI->new($parse_url);
      die "Invalid repository hostname\n" unless $uri->can('host')
        && defined($uri->host) && length($uri->host)
        && $uri->host !~ /[\x00-\x20\x7f<>"']/;
      die "Repository URL credentials are not supported\n" if defined($uri->userinfo)
        && !(($scheme =~ /\A(?:ssh|git\+ssh)\z/ && $uri->userinfo eq 'git')
          || ($scheme eq 'svn+ssh' && component($uri->userinfo)));
      my $parsed_hostname = lc $uri->host;
      die "Conflicting repository hostname\n"
        if defined($hostname) && lc($hostname) ne $parsed_hostname;
      $hostname = $parsed_hostname;
      my $service = $domains{$hostname};
      die "Conflicting repository host\n" if defined($host) && defined($service) && $host ne $service;
      $host //= $service;
      my $inferred_type = $scheme =~ /\Asvn/ ? 'Subversion'
        : $scheme =~ /\A(?:git|git\+ssh)\z/ ? 'Git'
        : defined($host) && exists($services{lc $host}) ? 'Git' : undef;
      die "Conflicting repository type\n"
        if defined($type) && defined($inferred_type) && $type ne $inferred_type;
      $type //= $inferred_type;
      # Only known hosting services have a predictable repository URL layout.
      # Preserve unfamiliar paths intact rather than guessing a repository name.
      if (defined($host) && exists($services{lc $host})
          && !defined($uri->query) && !defined($uri->fragment)
          && $uri->port == 443) {
        my $parsed_path = $uri->path;
        $parsed_path =~ s{\A/}{};
        $parsed_path =~ s{/+\z}{};
        $parsed_path =~ s{\.git\z}{};
        my @parts = split m{/}, $parsed_path, -1;
        if (@parts >= 2 && !grep { !component($_) || $_ eq '-' } @parts) {
          my $parsed_name = pop @parts;
          my $parsed_owner = join '/', @parts;
          my $valid_owner = $host eq 'GitLab' ? namespace($parsed_owner)
            : $parsed_owner =~ /\A[A-Za-z0-9][A-Za-z0-9-]*\z/;
          if ($valid_owner) {
            die "Conflicting repository name\n" if defined($name) && $name ne $parsed_name;
            die "Conflicting repository owner\n" if defined($owner) && $owner ne $parsed_owner;
            die "Conflicting repository path\n" if defined($path) && $path ne $parsed_path;
            $name = $parsed_name;
            $owner = $parsed_owner;
            $path = $parsed_path;
          }
        }
      }
    }
    die "Repository name is required without raw_url\n" unless defined($name) || defined($raw_url);
    die "Invalid repository name\n" if defined($name) && !component($name);
    die "Invalid repository owner\n" if defined($owner) && !namespace($owner);
    die "Invalid repository path\n" if defined($path) && !namespace($path);
    $hostname //= $services{lc $host}[1] if defined($host) && exists($services{lc $host});
    if (defined $hostname) {
      $hostname = lc $hostname;
      die "Invalid repository hostname\n" unless length($hostname) <= 253
        && !grep { length($_) > 63 || $_ !~ /\A[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?\z/ }
          split /\./, $hostname, -1;
      my $service = $domains{$hostname};
      die "Conflicting repository host\n" if defined($host) && defined($service) && $host ne $service;
      $host //= $service;
    }
    if (defined($host) && exists($services{lc $host})) {
      die "Conflicting repository type\n" if defined($type) && $type ne 'Git';
      $type //= 'Git';
      die "GitHub and Bitbucket owners cannot contain nested namespaces\n"
        if $host ne 'GitLab' && defined($owner) && $owner !~ /\A[A-Za-z0-9][A-Za-z0-9-]*\z/;
    }
    $path //= (defined($owner) ? "$owner/$name" : $name) if defined($name);
    die "Conflicting repository path\n" if defined($name) && defined($path)
      && $path ne (defined($owner) ? "$owner/$name" : $name);
  }

  method is_git { return defined($type) && $type eq 'Git' }
  method is_subversion { return defined($type) && $type eq 'Subversion' }
  method is_github { return defined($host) && $host eq 'GitHub' }
  method is_gitlab { return defined($host) && $host eq 'GitLab' }
  method is_bitbucket { return defined($host) && $host eq 'Bitbucket' }
  method is_complete {
    return 0 unless defined($name) && defined($hostname) && defined($path);
    return 0 if defined($host) && exists($services{lc $host}) && !defined($owner);
    return 1;
  }

  method url (%args) {
    die "Unknown repository URL option\n" if grep { $_ ne 'style' } keys %args;
    my $style = $args{style} // 'web';
    die "Unsupported repository URL style '$style'\n" unless $style =~ /\A(?:web|http|ssh)\z/;
    unless ($self->is_complete) {
      return $raw_url if $style eq 'web' && defined($raw_url) && $raw_url =~ /\Ahttps?:\/\//i;
      return undef;
    }
    return "https://$hostname/$path" if $style eq 'web';
    return undef unless defined $type;
    if ($self->is_git) {
      return "https://$hostname/$path.git" if $style eq 'http';
      return "git\@$hostname:$path.git";
    }
    return "https://$hostname/$path" if $style eq 'http';
    return "svn+ssh://$hostname/$path";
  }
}

1;
