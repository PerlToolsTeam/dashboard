use v5.40;
use feature 'class';
no warnings 'experimental::class';

class Dashboard::BranchCache {
  use JSON;
  use Path::Tiny;
  use Dashboard::Repository qw(valid_repo_parts lookup_default_branch);

  field $file :param = 'repo_def_branch.json';
  field $data = {};
  field %failed;
  field @problems;

  method begin_run {
    %failed = ();
    @problems = ();
  }

  method problems { return [@problems] }

  ADJUST {
    if (path($file)->is_file) {
      $data = JSON->new->decode(path($file)->slurp_utf8);
      die "Invalid branch cache in $file: expected an object\n" unless ref($data) eq 'HASH';
      for my $owner (keys %$data) {
        die "Invalid branch cache in $file: $owner must contain an object\n"
          unless ref($data->{$owner}) eq 'HASH';
      }
    }
  }

  method get ($owner, $name, $refresh = 0) {
    unless (valid_repo_parts($owner, $name)) {
      warn "Ignoring invalid repository in branch cache\n";
      return '';
    }
    my $cached = $data->{$owner}{$name} // '';
    $cached = '' if ref($cached) || $cached =~ /[\x00-\x20\x7f]/;
    return $cached if length($cached) && !$refresh;
    return $cached if $failed{"$owner/$name"};

    try {
      my $branch = lookup_default_branch($owner, $name);
      $data->{$owner}{$name} = $branch;
      return $branch;
    }
    catch ($error) {
      chomp $error;
      warn "Could not get default branch for $owner/$name: $error\n";
      push @problems, {
        service => 'GitHub', subject => "$owner/$name",
        message => length($cached)
          ? 'Default branch lookup failed; retained the cached branch.'
          : 'Default branch lookup failed; branch-specific badges may be unavailable.',
      };
      $failed{"$owner/$name"} = 1;
      return $cached;
    }
  }

  method refresh {
    for my $owner (sort keys %$data) {
      for my $name (sort keys %{ $data->{$owner} }) {
        $self->get($owner, $name, 1);
      }
    }
  }

  method save {
    # Path::Tiny writes a sibling temporary file and atomically renames it.
    path($file)->spew_utf8(JSON->new->pretty->canonical->encode($data));
  }
}

1;
