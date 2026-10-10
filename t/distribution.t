use v5.40;
use Test::More;
use JSON;
use Path::Tiny;
use lib 't/lib';
use Dashboard::TestData qw(release);
use Dashboard::Distribution;
use Dashboard::App;

my $temp = Path::Tiny->tempdir;
my $cwd = Path::Tiny->cwd;
chdir "$temp" or die $!;
# A stale or malformed experimental file must have no influence on this class.
path('github_repo.json')->spew_utf8('malformed stale experimental data');
{
  local *Dashboard::BranchCache::get = sub { 'main' };
  my $dist = Dashboard::Distribution->new_from_release(release(
    resources => { repository => { web => 'https://github.com/example/repo.git/' } },
  ));
  isa_ok($dist, 'Dashboard::Distribution');
  is($dist->distribution, 'Example', 'distribution name comes from release');
  is($dist->main_module_name, 'Example', 'main module retained');
  is($dist->repo_owner, 'example', 'owner comes from release URL, not stale cache');
  is($dist->repo_name, 'repo', 'repository is normalized');
  is($dist->dump->{repo_def_branch}, 'main', 'uses shared branch lookup');
}
my $no_repo = Dashboard::Distribution->new_from_release(release());
ok(!$no_repo->is_github, 'no-repo release is retained without GitHub status');
chdir "$cwd" or die $!;

my $app = Dashboard::App->new(gather => 0, build => 0);
isa_ok($app->mcpan, 'MetaCPAN::Client');
isa_ok($app->mcpan->ua, 'HTTP::Tiny');
is($app->mcpan->ua->{agent}, "CPAN Dashboard/$Dashboard::App::VERSION", 'identifying user agent');
done_testing;
