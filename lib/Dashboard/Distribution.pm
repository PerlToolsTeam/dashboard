use 5.40.0;

use feature 'class';
no if $^V >= v5.38, warnings => 'experimental::class';

class Dashboard::Distribution {

  use JSON;
  use URI;
  use Path::Tiny;

  field $name :param :reader;
  field $distribution :param :reader;
  field $main_module_name :param :reader;
  field $version :param;
  field $author :param;
  field $date :param;
  field $repo :param;
  field $uses_rt :param;
  field $repo_name :param :reader;
  field $repo_owner :param :reader;
  field $repo_def_branch :param;
  field $is_insecure_repo :param;
  field $bugtracker :param;

  # TODO: Can new_from_release and new_from_data be implemented using
  # ADJUST?

  sub new_from_release {
    my $class = shift;
    my ($release) = @_;

    my %dist_data;
    $dist_data{name}         = $release->name;
    $dist_data{distribution} = $release->distribution;
    $dist_data{main_module_name} = $release->main_module;
    $dist_data{version}      = $release->version;
    $dist_data{author}       = $release->author;
    $dist_data{date}         = (split /T/, $release->date)[0];

    # Get the repo link.
    # 1. It should be in the "web" key
    # 2. Otherwise, check the "url" key
    $dist_data{repo} = $release->resources->{repository}{web}
      // $release->resources->{repository}{url};

    $dist_data{bugtracker} = '';
    if ($release->resources->{bugtracker}{web}) {
      $dist_data{bugtracker} = $release->resources->{bugtracker}{web};
    }
    $dist_data{uses_rt} = $dist_data{bugtracker} =~ /rt.cpan.org/;

    unless ($dist_data{repo}) {
      warn "No repo for $dist_data{name}\n";
      return;
    }

    $dist_data{repo} =~ s[/$][];

    my $repo_data;
    if ($dist_data{repo} =~ m|github\.com/| and $repo_data = $class->get_github_data($dist_data{author}, $dist_data{distribution})) {
      for (qw[repo_owner repo_name repo_def_branch]) {
        $dist_data{$_} = $repo_data->{$_};
      }
      $dist_data{repo} = $repo_data->{url};
    } else {
      warn "No repo data for $dist_data{distribution} ($dist_data{repo}). Skipping.\n";

      # We need the repo's name. Try to extract it from the URL
      my $repo_uri = URI->new($dist_data{repo});
      if ($dist_data{repo} =~ /^(http|git)/) {
        my $path = $repo_uri->path;
        $path =~ s|^/||; # Remove leading slash
        $path =~ s|\.git$||; # Remove trailing .git
        @dist_data{qw[repo_owner repo_name]} = split m|/|, $path, 2;
        $dist_data{repo_name} =~ s/\.git$// if $dist_data{repo} =~ /^git/;
        $dist_data{repo_def_branch} = get_repo_default_branch(\%dist_data);
      } else {
        warn "Strange repo for $dist_data{name} (%dist_data{repo}). Skipping.\n";
        return;
      }
    }

    $dist_data{is_insecure_repo} = $dist_data{repo} =~ m|^http:|;

    return $class->new(%dist_data);
  }

  sub new_from_data {
    my $class = shift;
    my ($data) = @_;

    return $class->new(%$data);
  }

  method dump {
    my $data = {
      author       => $author,
      bugtracker   => $bugtracker,
      date         => $date,
      distribution => $distribution,
      is_insecure_repo => ($is_insecure_repo ? $JSON::true : $JSON::false ),
      name         => $name,
      main_module_name => $main_module_name,
      version      => $version,
      repo         => $repo,
      uses_rt      => ($uses_rt ? $JSON::true : $JSON::false ),
      is_github    => ($self->is_github ? $JSON::true : $JSON::false),
      repo_name    => $repo_name,
      repo_owner   => $repo_owner,
      repo_def_branch => $repo_def_branch,
    };

    return $data;
  }

  method is_github {
    return unless defined $repo;
    # Currently we only support Github repos
    return $repo =~ m|github\.com/|;
  }

  sub get_github_data {
    my $class = shift;
    my ($author, $distribution) = @_;

    warn "Getting github data for $author/$distribution\n";

    return unless -f 'github_repo.json';

    my $data = JSON->new->decode(path('github_repo.json')->slurp_utf8);

    if ($data->{$author} and $data->{$author}{$distribution}) {
      use Data::Printer;
      p $data->{$author}{$distribution};
      return $data->{$author}{$distribution};
    } else {
      return;
    }
  }

  # Note: a subroutine, not a method, because it needs to be
  # called from a static context (i.e., not on an instance of the class).
  sub get_repo_default_branch {
    my ($dist_data) = @_;

    state $branch_cache_file = 'repo_def_branch.json';
    state $repo_def_branch = -f $branch_cache_file ? JSON->new->decode(path($branch_cache_file)->slurp_utf8) : {};

    my $path = "$dist_data->{repo_owner}/$dist_data->{repo_name}";

    unless (exists $repo_def_branch->{$dist_data->{repo_owner}} and
      exists $repo_def_branch->{$dist_data->{repo_owner}}{$dist_data->{repo_name}}) {
        $repo_def_branch->{$dist_data->{repo_owner}}{$dist_data->{repo_name}}
          = ``;
        chomp $repo_def_branch->{$dist_data->{repo_owner}}{$dist_data->{repo_name}};
    }

    return $repo_def_branch->{$dist_data->{repo_owner}}{$dist_data->{repo_name}};
  }
}

1;
