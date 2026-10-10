use v5.40;

use feature 'class';
no if $^V >= v5.38, warnings => 'experimental::class';

class Dashboard::BadgeMaker {

  use Dashboard::Repository qw(github_repository);
  use URI::Escape 'uri_escape_utf8';

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
    return '' unless $self->has_repo_details($module);

    return $self->badge_link(
      "https://cirrus-ci.com/github/$module->{repo_owner}/$module->{repo_name}",
      "https://api.cirrus-ci.com/github/$module->{repo_owner}/$module->{repo_name}.svg?task=$task",
      "Cirrus task $task",
    );
  }

  method gh {
    my ($module, $workflow) = @_;
    return '' unless $self->has_repo_details($module);

    my $encoded = uri_escape_utf8($workflow);
    my $search = $workflow;
    $search =~ s/([\\"])/\\$1/g;
    my $query = uri_escape_utf8(qq[workflow:"$search"]);
    return $self->badge_link(
      "https://github.com/$module->{repo_owner}/$module->{repo_name}/actions?query=$query",
      "https://github.com/$module->{repo_owner}/$module->{repo_name}/workflows/$encoded/badge.svg",
      "GH Action $workflow",
    );
  }

  method gh_file ($module, $file) {
    return '' unless $self->has_repo_details($module);
    my $encoded = uri_escape_utf8($file);
    my $base = "https://github.com/$module->{repo_owner}/$module->{repo_name}/actions/workflows/$encoded";
    return $self->badge_link($base, "$base/badge.svg", "GH Action $file");
  }

  method gh_badges ($module, $settings) {
    return '' unless $settings->{use_gh_actions};
    my @badges = (
      (map { $self->gh($module, $_) } @{ $settings->{gh_workflow_names} // [] }),
      (map { $self->gh_file($module, $_) } @{ $settings->{gh_workflow_files} // [] }),
    );
    return join '<br>', grep { length } @badges;
  }

  method appveyor {
    my ($module) = @_;
    return '' unless $self->has_repo_details($module);

    return $self->badge_link(
      "https://ci.appveyor.com/project/$module->{repo_owner}/$module->{repo_name}",
      "https://ci.appveyor.com/api/projects/status/github/$module->{repo_owner}/$module->{repo_name}?svg=true&passingText=Windows%20-%20OK&pendingText=Windows%20-%20%3F%3F%3F&failingText=Windows%20-%20broken",
      "Build status for $module->{dist}",
    );
  }

  method travis {
    my ($module) = @_;
    return '' unless $self->has_branch_details($module);

    return $self->badge_link(
      "https://travis-ci.org/$module->{repo_owner}/$module->{repo_name}?branch=$module->{repo_def_branch}",
      "https://travis-ci.org/$module->{repo_owner}/$module->{repo_name}.svg?branch=$module->{repo_def_branch}",
      "Build status for $module->{dist}",
    );
  }

  method travis_com {
      my ($module) = @_;

      return $self->travis($module) =~ s/travis-ci\.org/travis-ci.com/gr;
  }

  method coveralls {
    my ($module, $author) = @_;
    return '' unless $self->has_branch_details($module);

    return $self->badge_link(
      "https://coveralls.io/github/$module->{repo_owner}/$module->{repo_name}?branch=$module->{repo_def_branch}",
      "https://coveralls.io/repos/$module->{repo_owner}/$module->{repo_name}/badge.svg?branch=$module->{repo_def_branch}&service=github",
      "Test coverage for $module->{dist}",
    );
  }

  method codecov {
    my ($module) = @_;
    return '' unless $self->has_branch_details($module);

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
    for my $value ($link_url, $img_url, $alt_text) {
      $value =~ s/&/&amp;/g;
      $value =~ s/</&lt;/g;
      $value =~ s/>/&gt;/g;
      $value =~ s/"/&quot;/g;
      $value =~ s/'/&#39;/g;
    }

    return qq[<a href="$link_url"><img class="backup_picture" alt="$alt_text" src="$img_url"></a>];
  }

  method has_repo_details {
    my ($module) = @_;

    my $repo = github_repository($module->{repo}) or return;
    return $module->{repo_owner} && $module->{repo_name}
      && $module->{repo_owner} eq $repo->{owner}
      && $module->{repo_name} eq $repo->{name};
  }

  method has_branch_details {
    my ($module) = @_;

    return $self->has_repo_details($module) && $module->{repo_def_branch};
  }

}

1;
