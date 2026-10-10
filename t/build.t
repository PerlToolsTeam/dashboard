use v5.40;
use utf8;
use Test::More;
use JSON;
use Path::Tiny;
use FindBin '$RealBin';
use lib 't/lib';
use Dashboard::TestData qw(client release);
use Dashboard::App;

my $temp = Path::Tiny->tempdir;
my $root = path("$RealBin/..")->absolute;
my $json = JSON->new->pretty->canonical;
my $config = {
  static_dir => "$root/src", input_dir => "$root/tt_lib", output_dir => "$temp/site",
  author_dir => "$temp/authors", data_dir => "$temp/data",
  branch_cache_file => "$temp/branches.json", index_template => 'index.tt',
  author_template => 'dashboard.tt', wrapper => 'page.tt', page_templates => ['add'],
  domain => 'example.invalid', fetch_attempts => 3, retry_delay => 0,
  menu => [{title => 'Docs & help', link => '/help/'}],
};
$temp->child('config.json')->spew_utf8($json->encode($config));
$temp->child('authors')->mkpath;
$temp->child('data/EXAMPLE')->mkpath;
my $registration = { author => { cpan => 'EXAMPLE', github => 'example-user' },
  ci => {}, sort => { column => 0, direction => 'asc' } };
my $author_file = $temp->child('authors/EXAMPLE.json');
$author_file->spew_utf8($json->encode($registration));
my $old = { %$registration, modules => [{name => 'Old-0.5', dist => 'Old',
  ver => '0.5', auth => 'EXAMPLE', date => '2020-01-01'}] };
my $snapshot = $temp->child('data/EXAMPLE/data.json');
$snapshot->spew_utf8($json->encode($old));

sub app (%options) {
  return Dashboard::App->new(config_file => "$temp/config.json", %options);
}

sub quiet :prototype(&) ($code) {
  my $output = '';
  local *STDOUT;
  open STDOUT, '>', \$output or die $!;
  return $code->();
}

my $live = client(name => 'Example Áuthor', releases => [release(distribution => 'Fresh', name => 'Fresh-1.0')]);
quiet { app(mcpan => $live)->run };
is($live->{calls}, 1, 'combined run fetches author exactly once');
my $fresh = $json->decode($snapshot->slurp_utf8);
is($fresh->{modules}[0]{dist}, 'Fresh', 'gather updates the authoritative persistent snapshot');
is($fresh->{author}{name}, 'Example Áuthor', 'Unicode metadata round-trips correctly');
like($fresh->{gathered_at}, qr/\A\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ\z/, 'snapshot records successful gather time');
my $output = $temp->child('site');
is_deeply($json->decode($output->child('EXAMPLE/data.json')->slurp_utf8), $fresh,
  'published JSON equals the snapshot that supplied the HTML');
like($output->child('EXAMPLE/index.html')->slurp_utf8, qr/>Fresh<\/td>/, 'HTML uses fresh release');
unlike($output->child('EXAMPLE/index.html')->slurp_utf8, qr/>Old<\/td>/, 'old snapshot cannot overwrite HTML data');
ok($output->child('index.html')->is_file, 'root index generated');
like($output->child('index.html')->slurp_utf8, qr/Example Áuthor/, 'root index includes author name');
like($output->child('index.html')->slurp_utf8, qr{href="/help/">Docs &amp; help</a>},
  'top-level configured menu is rendered and escaped');
like($output->child('EXAMPLE/index.html')->slurp_utf8, qr{data-sort-name="date"},
  'template supplies stable date column identity');
ok($output->child('add/index.html')->is_file, 'onboarding page generated');
is($output->child('js/dashboard.js')->slurp_utf8, $root->child('src/js/dashboard.js')->slurp_utf8,
  'static JavaScript copied into configured output');
is($output->child('css/style.css')->slurp_utf8, $root->child('src/css/style.css')->slurp_utf8,
  'static CSS copied into configured output');
my $sitemap = $output->child('sitemap.xml')->slurp_utf8;
like($sitemap, qr{<loc>https://example.invalid/EXAMPLE/</loc>}, 'sitemap includes author');
like($sitemap, qr{<loc>https://example.invalid/add/</loc>}, 'sitemap includes onboarding');
is(scalar(() = $sitemap =~ /<loc>/g), 3, 'sitemap contains exactly author, index, and onboarding');
ok(!$temp->child('docs')->exists, 'custom output does not create a docs directory');

my $offline = client(errors => ['network must not be used']);
quiet { app(mcpan => $offline, gather => 0)->run };
is($offline->{calls} // 0, 0, 'build-only run never fetches metadata');
is_deeply($json->decode($output->child('EXAMPLE/data.json')->slurp_utf8), $fresh,
  'subsequent build uses the updated persistent snapshot');
like($output->child('EXAMPLE/index.html')->slurp_utf8, qr/>Fresh<\/td>/, 'cached build HTML still matches JSON');

{
  $temp->child('dashboard.json')->spew_utf8($json->encode($config));
  my $cwd = Path::Tiny->cwd;
  chdir "$temp" or die $!;
  open my $process, '-|', $^X, "-I$root/lib", "$root/bin/dashboard", '--build' or die $!;
  my $stdout = do { local $/; <$process> };
  close $process;
  is($?, 0, 'CLI build-only command succeeds from a configured clean directory');
  like($stdout, qr/Building/, 'CLI selects build stage');
  unlike($stdout, qr/Gathering/, 'CLI does not select gather without --gather');
  chdir "$cwd" or die $!;
}

my $gather_only = client(releases => [release(distribution => 'Next', name => 'Next-2.0')]);
quiet { app(mcpan => $gather_only, build => 0)->run };
is($json->decode($snapshot->slurp_utf8)->{modules}[0]{dist}, 'Next', 'gather-only persists newer data');
is($json->decode($output->child('EXAMPLE/data.json')->slurp_utf8)->{modules}[0]{dist}, 'Fresh',
  'gather-only leaves previously published site untouched');
quiet { app(mcpan => $offline, gather => 0)->run };
is($json->decode($output->child('EXAMPLE/data.json')->slurp_utf8)->{modules}[0]{dist}, 'Next',
  'build-only publishes the gather-only update');

my @warnings;
local $SIG{__WARN__} = sub { push @warnings, @_ };
my @waits;
local *Dashboard::App::wait_before_retry = sub ($self, $attempt) { push @waits, $attempt };
my $retry = client(errors => ['HTTP 503 Service Unavailable']);
my $retried = app(mcpan => $retry)->do_author("$author_file");
is($retry->{calls}, 2, 'transient failure is retried');
is_deeply(\@waits, [1], 'retry uses bounded backoff hook');
ok(!exists($retried->{fetch_warning}), 'successful retry is not presented as stale data');
my $before_failure = $snapshot->slurp_utf8;

@waits = ();
my $unavailable = client(errors => [('HTTP 503 Service Unavailable') x 3]);
my $recovered = app(mcpan => $unavailable)->do_author("$author_file");
is($unavailable->{calls}, 3, 'transient retries are bounded');
is_deeply(\@waits, [1, 2], 'only the allowed retries wait');
like($recovered->{fetch_warning}, qr/cached data/, 'fallback explicitly reports stale data');
is($snapshot->slurp_utf8, $before_failure, 'failed retrieval does not replace the last good snapshot');
like(join('', @warnings), qr/Using cached snapshot.*gathered/, 'fallback logs identify source and gather time');

my $permanent = client(errors => ['HTTP 404 Not Found']);
app(mcpan => $permanent)->do_author("$author_file");
is($permanent->{calls}, 1, 'permanent failure is not retried');
for my $reason ('Service Unavailable', 'Too Many Requests', 'Internal Server Error',
  'Connection timed out', 'Bad Gateway') {
  ok(Dashboard::App::retryable_fetch_error("Failed to fetch URL: $reason"),
    "recognizes transient reason text: $reason");
}
for my $reason ('HTTP 403 Forbidden', 'HTTP 404 Not Found', 'Invalid release metadata',
  'Invalid release metadata at example.pm line 503') {
  ok(!Dashboard::App::retryable_fetch_error($reason), "does not retry permanent error: $reason");
}

my $partial = client(iterator_error => 'HTTP 503 Service Unavailable',
  releases => [release(distribution => 'Partial', name => 'Partial-1.0')]);
my $partial_fallback = app(mcpan => $partial)->do_author("$author_file");
is($partial->{calls}, 3, 'iteration failures restart the entire author fetch');
is($snapshot->slurp_utf8, $before_failure, 'partial release iteration cannot replace valid data');
isnt($partial_fallback->{modules}[0]{dist}, 'Partial', 'partial releases do not leak into fallback output');

my $unknown_file = $temp->child('authors/UNKNOWN.json');
$unknown_file->spew_utf8($json->encode({author => {cpan => 'UNKNOWN'}, ci => {}}));
eval { app(mcpan => client(errors => ['HTTP 404 Not Found']))->do_author("$unknown_file") };
like($@, qr/MetaCPAN fetch failed for UNKNOWN.*No usable author snapshot/s,
  'first fetch failure identifies author and missing fallback');

{
  local *Path::Tiny::move = sub { die "simulated snapshot rename failure\n" };
  eval { app(mcpan => client())->do_author("$author_file") };
  like($@, qr/simulated snapshot rename failure/, 'snapshot write failure is surfaced');
  is($snapshot->slurp_utf8, $before_failure, 'failed snapshot replacement preserves old bytes');
}

$snapshot->spew_utf8('not JSON');
eval { app(mcpan => client(errors => ['HTTP 404 Not Found']))->do_author("$author_file") };
like($@, qr/No usable author snapshot/, 'corrupt fallback is rejected');

done_testing;
