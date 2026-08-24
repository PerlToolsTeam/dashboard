use v5.40;

use Test::More;

use lib 'lib';
use Dashboard::App;
use Dashboard::BadgeMaker;

{
  package Local::Release;

  sub new ($class, %args) {
    return bless \%args, $class;
  }

  sub name         ($self) { return $self->{name} }
  sub distribution ($self) { return $self->{distribution} }
  sub version      ($self) { return $self->{version} }
  sub author       ($self) { return $self->{author} }
  sub date         ($self) { return $self->{date} }
  sub resources    ($self) { return $self->{resources} }
}

{
  local *Dashboard::App::get_repo_default_branch = sub ($self, $module) {
    return 'main';
  };

  my $app = Dashboard::App->new(gather => 0, build => 0);

  my $no_repo = $app->module_from_release(Local::Release->new(
    name         => 'No-Repo-1.0',
    distribution => 'No-Repo',
    version      => '1.0',
    author       => 'AUTHOR',
    date         => '2024-06-01T00:00:00',
    resources    => {
      bugtracker => { web => 'https://example.invalid/issues' },
      repository => {},
    },
  ));

  is($no_repo->{dist}, 'No-Repo', 'distribution without repo is still returned');
  ok(!defined $no_repo->{repo}, 'distribution without repo has no repo link');
  is($no_repo->{bugtracker}, 'https://example.invalid/issues', 'bugtracker is preserved');

  my $non_github = $app->module_from_release(Local::Release->new(
    name         => 'Non-GH-1.2',
    distribution => 'Non-GH',
    version      => '1.2',
    author       => 'AUTHOR',
    date         => '2024-06-02T00:00:00',
    resources    => {
      repository => { web => 'https://gitlab.example.com/team/non-gh/' },
    },
  ));

  is($non_github->{repo}, 'https://gitlab.example.com/team/non-gh', 'non-GitHub repo is preserved');
  is($non_github->{repo_owner}, 'team', 'non-GitHub repo owner is parsed from the repo path');
  is($non_github->{repo_name}, 'non-gh', 'non-GitHub repo name is parsed from the repo path');
  ok(!exists $non_github->{repo_def_branch}, 'non-GitHub repo does not require a default branch');

  my $github = $app->module_from_release(Local::Release->new(
    name         => 'GH-1.0',
    distribution => 'GH',
    version      => '1.0',
    author       => 'AUTHOR',
    date         => '2024-06-03T00:00:00',
    resources    => {
      repository => { web => 'https://github.com/example/gh' },
    },
  ));

  is($github->{repo_def_branch}, 'main', 'GitHub repo still gets a default branch');
}

{
  my $badges = Dashboard::BadgeMaker->new;

  is($badges->gh({ dist => 'No-Repo' }, 'test.yml'), '', 'GitHub badge is blank without repo details');
  is($badges->gh({ repo => 'https://gitlab.example.com/team/non-gh', repo_owner => 'team', repo_name => 'non-gh', dist => 'Non-GH' }, 'test.yml'), '', 'GitHub badge is blank for non-GitHub repos');
  is($badges->travis({ repo_owner => 'example', repo_name => 'repo', dist => 'Repo' }), '', 'branch-based badge is blank without branch details');
}

done_testing;
