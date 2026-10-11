use v5.40;
use feature 'class';
no warnings 'experimental::class';

class Dashboard::GitHub {
  use VCS::Repository;

  # Constructing a repository is local; only this explicit operation invokes gh.
  method lookup_default_branch ($repository) {
    die "Invalid GitHub repository owner/name\n"
      unless $repository && $repository->isa('VCS::Repository')
        && $repository->is_github && $repository->is_complete
        && $repository->hostname eq 'github.com';
    my $identity = $repository->owner . '/' . $repository->name;
    open my $fh, '-|', 'gh', 'repo', 'view', $identity,
      '--json', 'defaultBranchRef', '-q', '.defaultBranchRef.name'
      or die "Cannot run gh for $identity: $!\n";
    my $branch = do { local $/; <$fh> } // '';
    close $fh;
    my $status = $?;
    die "gh repo view for $identity failed (status $status)\n" if $status;
    $branch =~ s/\r?\n\z//;
    die "gh returned an empty or invalid branch for $identity\n"
      unless length($branch) && $branch !~ /[\x00-\x20\x7f]/;
    return $branch;
  }
}
1;
