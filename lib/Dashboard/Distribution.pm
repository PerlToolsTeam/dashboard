use 5.40.0;

use feature 'class';
no if $^V >= v5.38, warnings => 'experimental::class';

class Dashboard::Distribution {

  use JSON;
  use URI;
  use Path::Tiny;
  use Dashboard::BranchCache;
  use Dashboard::Repository qw(github_repository);

  field $name :param :reader;
  field $distribution :param :reader;
  field $main_module_name :param :reader;
  field $version :param;
  field $author :param;
  field $date :param;
  field $repo :param = undef;
  field $uses_rt :param;
  field $repo_name :param :reader = undef;
  field $repo_owner :param :reader = undef;
  field $repo_def_branch :param = undef;
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

    $dist_data{is_insecure_repo} = ($dist_data{repo} // '') =~ m|^http:|;
    if (my $github = github_repository($dist_data{repo})) {
      $dist_data{repo} = $github->{url};
      $dist_data{repo_owner} = $github->{owner};
      $dist_data{repo_name} = $github->{name};
      $dist_data{repo_def_branch} = get_repo_default_branch(\%dist_data);
    }

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
    return !!github_repository($repo);
  }

  # Note: a subroutine, not a method, because it needs to be
  # called from a static context (i.e., not on an instance of the class).
  sub get_repo_default_branch {
    my ($dist_data) = @_;

    state $cache = Dashboard::BranchCache->new;
    return $cache->get($dist_data->{repo_owner}, $dist_data->{repo_name});
  }
}

1;
