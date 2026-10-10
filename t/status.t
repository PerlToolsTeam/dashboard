use v5.40;
use Test::More;
use JSON;
use Path::Tiny;
use FindBin '$RealBin';
use lib 't/lib';
use Dashboard::TestData qw(client release);
use Dashboard::App;
use Dashboard::BranchCache;

my $root = path("$RealBin/..")->absolute;
my $temp = Path::Tiny->tempdir;
my $json = JSON->new->canonical;
my $cfg = {
  static_dir => "$root/src", input_dir => "$root/tt_lib", output_dir => "$temp/site",
  author_dir => "$temp/authors", data_dir => "$temp/data", branch_cache_file => "$temp/branches.json",
  index_template => 'index.tt', author_template => 'dashboard.tt', wrapper => 'page.tt',
  page_templates => ['status'], domain => 'example.invalid', fetch_attempts => 1, retry_delay => 0,
};
$temp->child('config.json')->spew_utf8($json->encode($cfg));
$temp->child('authors')->mkpath;
$temp->child('data/EXAMPLE')->mkpath;
my $registration = {author => {cpan => 'EXAMPLE'}, ci => {}};
$temp->child('authors/EXAMPLE.json')->spew_utf8($json->encode($registration));
my $snapshot = $temp->child('data/EXAMPLE/data.json');
$snapshot->spew_utf8($json->encode({%$registration, modules => [], gathered_at => '2025-01-01T00:00:00Z'}));
my $before = $snapshot->slurp_utf8;
my $report_path = $temp->child('site/status/data.json');
my $page_path = $temp->child('site/status/index.html');
my @warnings;
local $SIG{__WARN__} = sub {push @warnings, @_};
local *STDOUT;
open STDOUT, '>', \my $stdout or die $!;

sub app (%args) { Dashboard::App->new(config_file => "$temp/config.json", %args) }
app(mcpan => client(errors => ['HTTP 503 <script>secret diagnostics</script>']))->run;
my $report = $json->decode($report_path->slurp_utf8);
is($report->{mode}, 'gather-and-build', 'report identifies metadata refresh build');
is($report->{author_count}, 1, 'report counts authors');
like($report->{generated_at}, qr/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$/, 'report has UTC timestamp');
is_deeply($report->{problems}, [{service => 'MetaCPAN', subject => 'EXAMPLE',
  message => 'Release metadata could not be refreshed; showing cached data.',
  gathered_at => '2025-01-01T00:00:00Z'}], 'JSON describes fallback and source date');
my $page = $page_path->slurp_utf8;
like($page, qr/showing cached data/, 'HTML exposes metadata fallback');
like($page, qr/2025-01-01T00:00:00Z/, 'HTML exposes last successful fetch time');
unlike($page, qr/secret diagnostics/, 'raw service exceptions are kept in logs');
like($page, qr/Builds that fail before publication cannot update this report/, 'fatal failure limitation is visible');
like($temp->child('site/sitemap.xml')->slurp_utf8, qr{https://example.invalid/status/}, 'status page appears in sitemap');
is($snapshot->slurp_utf8, $before, 'status reporting preserves last good data');

my $offline = client(errors => ['must not fetch']);
app(mcpan => $offline, gather => 0)->run;
is($offline->{calls} // 0, 0, 'cached status build does not fetch');
$report = $json->decode($report_path->slurp_utf8);
is($report->{mode}, 'cached-build', 'cached build mode explicit in JSON');
is_deeply($report->{problems}, [], 'old fallback warnings do not leak into next build');
like($page_path->slurp_utf8, qr/did not contact MetaCPAN/, 'cached report states availability was not checked');

{
  local *Dashboard::BranchCache::lookup_default_branch = sub { die "lookup failed\n" };
  my $repo = release(resources => {repository => {web => 'https://github.com/example/project'}});
  my $runner = app(mcpan => client(releases => [$repo]));
  $runner->run;
  $report = $json->decode($report_path->slurp_utf8);
  is($report->{problems}[0]{service}, 'GitHub', 'branch lookup failure appears in report');
  is($report->{problems}[0]{subject}, 'example/project', 'report identifies failed repository');
  like($report->{problems}[0]{message}, qr/may be unavailable/, 'report describes missing branch effect');
  $runner->run;
  $report = $json->decode($report_path->slurp_utf8);
  is(scalar @{$report->{problems}}, 1, 'reused application clears previous lookup failures');
  is(scalar(grep {/Could not get default branch/} @warnings), 2, 'reused application retries branch lookup on next run');
}

{
  $temp->child('branches.json')->spew_utf8($json->encode({example => {project => 'main'}}));
  my $cache = Dashboard::BranchCache->new(file => "$temp/branches.json");
  local *Dashboard::BranchCache::lookup_default_branch = sub { die "lookup failed\n" };
  is($cache->get('example', 'project', 1), 'main', 'refresh failure preserves branch');
  like($cache->problems->[0]{message}, qr/retained the cached branch/, 'report describes retained branch');
}

my $hostile = release(distribution => 'Broken', resources => {repository => {web => 'javascript:alert(1)'}});
app(mcpan => client(releases => [$hostile]))->run;
$report = $json->decode($report_path->slurp_utf8);
is($report->{problems}[0]{service}, 'Metadata', 'unsupported link is reported without losing distribution');
like($temp->child('site/EXAMPLE/index.html')->slurp_utf8, qr/>Broken(?:<\/td>|<br>)/, 'unsupported link retains row');

# Template escaping covers public report fields independently of API normalization.
my $tt = Template->new(INCLUDE_PATH => "$root/tt_lib", WRAPPER => 'page.tt');
my $html = '';
$tt->process('status.tt', { report => { problems => [{service => '<script>', subject => '<img>', message => 'A & B'}] } }, \$html)
  or die $tt->error;
like($html, qr/&lt;script&gt;/, 'report service escaped');
like($html, qr/&lt;img&gt;/, 'report subject escaped');
like($html, qr/A &amp; B/, 'report message escaped');

my $last_report = $report_path->slurp_utf8;
$snapshot->remove;
eval { app(mcpan => client(errors => ['HTTP 404 Not Found']))->run };
like($@, qr/No usable author snapshot/, 'unrecoverable build still fails');
is($report_path->slurp_utf8, $last_report, 'fatal gather does not publish a misleading new status');

done_testing;
