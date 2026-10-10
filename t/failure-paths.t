use v5.40;
use Test::More;
use JSON;
use Path::Tiny;
use FindBin '$RealBin';
use lib 't/lib';
use Dashboard::TestData qw(client);
use Dashboard::App;

for my $error (
  "Failed to fetch 'https://fastapi.metacpan.org/v1/author/TIMEOUT': Not Found at /tmp/client.pm line 503.",
  'Invalid release metadata at /tmp/network-timeout.pm line 503.',
  'HTTP 403 Forbidden: connection not authorized',
  'HTTP 404 Not Found: timeout endpoint does not exist',
  'SSL connection failed: certificate verify failed',
  undef,
) {
  ok(!Dashboard::App::retryable_fetch_error($error), 'permanent reason does not inherit retry words from context');
}
for my $error (
  "Failed to fetch 'https://fastapi.metacpan.org/v1/author/EXAMPLE': Could not connect to 'host:443': refused at client.pm line 2.",
  'Could not resolve host: fastapi.metacpan.org',
  'Temporary failure in name resolution',
  'HTTP/1.1 408 Request Timeout',
  'HTTP 429 Too Many Requests',
  'HTTP 503 Service Unavailable',
) {
  ok(Dashboard::App::retryable_fetch_error($error), 'actual network/server reason remains retryable');
}

my $temp = Path::Tiny->tempdir;
my $root = path("$RealBin/..")->absolute;
my $templates = $temp->child('templates');
$templates->mkpath;
for my $file ($root->child('tt_lib')->children(qr/\.tt\z/)) {
  $file->copy($templates->child($file->basename));
}
$temp->child('data/EXAMPLE')->mkpath;
$temp->child('authors')->mkpath;
my $json = JSON->new;
$temp->child('data/EXAMPLE/data.json')->spew_utf8($json->encode({author => {cpan => 'EXAMPLE'}, modules => []}));
my $cfg = {
  static_dir => "$root/src", input_dir => "$templates", output_dir => "$temp/site",
  author_dir => "$temp/authors", data_dir => "$temp/data", branch_cache_file => "$temp/branches.json",
  index_template => 'index.tt', author_template => 'dashboard.tt', wrapper => 'page.tt',
  page_templates => ['status'], domain => 'example.invalid',
};
$temp->child('config.json')->spew_utf8($json->encode($cfg));
$templates->child('index.tt')->spew_utf8('[% IF %]');
local *STDOUT;
open STDOUT, '>', \my $output or die $!;
eval { Dashboard::App->new(config_file => "$temp/config.json", gather => 0, mcpan => client())->run };
like($@, qr/parse error.*index.tt/s, 'invalid home-page template fails build');
ok(!$temp->child('site/status/data.json')->exists, 'failed home page cannot publish successful status report');
ok(!$temp->child('site/sitemap.xml')->exists, 'failed home page stops remaining publication steps');

done_testing;
