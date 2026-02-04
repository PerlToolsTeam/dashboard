use v5.40;

use feature 'class';
no if $^V >= v5.38, warnings => 'experimental::class';

class Dashboard::BadgeMaker {

  method cpan {
    my ($module) = @_;

    return $self->badge_link(
      "https://metacpan.org/release/$module->{dist}",
      "https://img.shields.io/cpan/v/$module->{dist}.svg",
      "CPAN version for $module->{dist}",
    );
  }

  method cirrus {
    my ($module, $task) = @_;

    return $self->badge_link(
      "https://cirrus-ci.com/github/$module->{repo_owner}/$module->{repo_name}",
      "https://api.cirrus-ci.com/github/$module->{repo_owner}/$module->{repo_name}.svg?task=$task",
      "Cirrus task $task",
    );
  }

  method gh {
    my ($module, $workflow) = @_;

    return $self->badge_link(
      "https://github.com/$module->{repo_owner}/$module->{repo_name}/actions?query=workflow%3A$workflow",
      "https://github.com/$module->{repo_owner}/$module->{repo_name}/workflows/$workflow/badge.svg",
      "GH Action $workflow",
    );
  }

  method appveyor {
    my ($module) = @_;

    return $self->badge_link(
      "https://ci.appveyor.com/project/$module->{repo_owner}/$module->{repo_name}",
      "https://ci.appveyor.com/api/projects/status/github/$module->{repo_owner}/$module->{repo_name}?svg=true&passingText=Windows%20-%20OK&pendingText=Windows%20-%20%3F%3F%3F&failingText=Windows%20-%20broken",
      "Build status for $module->{dist}",
    );
  }

  method travis_com {
      my ($module) = @_;

    return $self->badge_link(
      "https://travis-ci.com/$module->{repo_owner}/$module->{repo_name}?branch=$module->{repo_def_branch}",
      "https://travis-ci.com/$module->{repo_owner}/$module->{repo_name}.svg?branch=$module->{repo_def_branch}",
      "Build status for $module->{dist}",
    );
  }

  method coveralls {
    my ($module, $author) = @_;

    return $self->badge_link(
      "https://coveralls.io/github/$module->{repo_owner}/$module->{repo_name}?branch=$module->{repo_def_branch}",
      "https://coveralls.io/repos/$module->{repo_owner}/$module->{repo_name}/badge.svg?branch=$module->{repo_def_branch}&service=github",
      "Test coverage for $module->{dist}",
    );
  }

  method codecov {
    my ($module) = @_;

    return $self->badge_link(
      "https://codecov.io/gh/$module->{repo_owner}/$module->{repo_name}",
      "https://codecov.io/gh/$module->{repo_owner}/$module->{repo_name}/branch/$module->{repo_def_branch}/graph/badge.svg",
      "Test coverage for $module->{dist}",
    );
  }

  method cpants {
    my ($module) = @_;

    return $self->badge_link(
      "https://cpants.cpanauthors.org/release/$module->{auth}/$module->{dist}-$module->{ver}",
      "https://cpants.cpanauthors.org/release/$module->{auth}/$module->{dist}-$module->{ver}.svg",
      "Kwalitee for $module->{dist}",
    );
  }

  method badge_link {
    my ($link_url, $img_url, $alt_text) = @_;

    return qq[<a href="$link_url"><img class="backup_picture" alt="$alt_text" src="$img_url"></a>];
  }

}

1;
