package Dashboard::Repository;

use v5.40;
use Exporter 'import';
use URI;

our @EXPORT_OK = qw(github_repository valid_repo_parts lookup_default_branch);

sub valid_repo_parts ($owner, $name) {
  return defined($owner) && defined($name)
    && $owner =~ /\A[A-Za-z0-9][A-Za-z0-9-]*\z/
    && $name =~ /\A[A-Za-z0-9_.-]+\z/
    && $name ne '.' && $name ne '..';
}

sub github_repository ($url) {
  return unless defined($url) && !ref($url) && $url !~ /[\x00-\x20\x7f]/;

  # CPAN metadata commonly uses either a URI or Git's scp-style SSH syntax.
  $url =~ s|\Agit\@github\.com:|ssh://git\@github.com/|i;
  my ($scheme) = $url =~ m{\A(https?|git|ssh)://}i;
  return unless defined $scheme;
  # URI's generic git/ssh handlers do not all provide host accessors.
  $url =~ s{\A(?:git|ssh)://}{https://}i;
  my $uri = URI->new($url);
  return unless $uri->can('host') && defined($uri->host)
    && lc($uri->host) eq 'github.com';
  return if $uri->can('userinfo') && defined($uri->userinfo)
    && (lc($scheme) ne 'ssh' || $uri->userinfo ne 'git');
  return if defined($uri->query) || defined($uri->fragment);

  my $path = $uri->path;
  $path =~ s|/+\z||;
  $path =~ s|\.git\z||;
  my ($owner, $name) = $path =~ m|\A/([^/]+)/([^/]+)\z|;
  return unless valid_repo_parts($owner, $name);
  return { owner => $owner, name => $name,
    url => "https://github.com/$owner/$name" };
}

sub lookup_default_branch ($owner, $name) {
  die "Invalid GitHub repository owner/name\n" unless valid_repo_parts($owner, $name);
  my $repository = "$owner/$name";
  open my $fh, '-|', 'gh', 'repo', 'view', $repository,
    '--json', 'defaultBranchRef', '-q', '.defaultBranchRef.name'
    or die "Cannot run gh for $repository: $!\n";
  my $branch = do { local $/; <$fh> } // '';
  close $fh;
  my $status = $?;
  die "gh repo view for $repository failed (status $status)\n" if $status;
  $branch =~ s/\r?\n\z//;
  die "gh returned an empty or invalid branch for $repository\n"
    unless length($branch) && $branch !~ /[\x00-\x20\x7f]/;
  return $branch;
}

1;
