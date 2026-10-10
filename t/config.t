use v5.40;
use Test::More;
use Path::Tiny;
use JSON;
use FindBin '$RealBin';
use lib 't/lib';
use Dashboard::Config qw(read_global_config normalize_author);
use Dashboard::TestData qw(client);
use Dashboard::App;

my $temp = Path::Tiny->tempdir;
my $json = JSON->new->canonical;
my $root = path("$RealBin/..")->absolute;
$temp->child('static')->mkpath;
$temp->child('authors')->mkpath;
$temp->child('data')->mkpath;
my $global = { static_dir => "$temp/static", input_dir => "$root/tt_lib",
  output_dir => "$temp/site", author_dir => "$temp/authors", data_dir => "$temp/data",
  branch_cache_file => "$temp/branches.json", domain => 'example.invalid',
  author_template => 'dashboard.tt', index_template => 'index.tt', wrapper => 'page.tt',
  page_templates => ['add'] };
my $file = $temp->child('config.json');

sub write_config ($data) { $file->spew_utf8($json->encode($data)) }
write_config($global);
my $defaults = read_global_config("$file");
is($defaults->{fetch_attempts}, 3, 'bounded attempts have a default');
is($defaults->{http_timeout}, 20, 'HTTP timeout has a default');
is_deeply($defaults->{menu}, [], 'menu defaults to empty');

for my $case (
  [output_dir => '', qr/output_dir/], [output_dir => "$temp/static/site", qr/separate from static_dir/],
  [output_dir => "$temp/not-created/../static", qr/separate from static_dir/],
  [output_dir => "$temp", qr/separate from/],
  [output_dir => '/', qr/separate from/],
  [branch_cache_file => "$temp/site/branches.json", qr/branch_cache_file/],
  [domain => 'https://example.invalid', qr/domain/], [domain => 'example..invalid', qr/domain/],
  [domain => 'example.invalid:99999', qr/domain/], [fetch_attempts => 0, qr/fetch_attempts/],
  [fetch_attempts => 6, qr/fetch_attempts/], [http_timeout => -1, qr/http_timeout/],
  [retry_delay => 11, qr/retry_delay/], [page_templates => 'add', qr/page_templates/],
  [page_templates => ['../add'], qr/page_templates/], [index_template => 'missing.tt', qr/index_template/],
  [menu => [{title => 'Bad', link => 'javascript:alert(1)'}], qr/menu/],
) {
  my ($key, $value, $error) = @$case;
  write_config({%$global, $key => $value});
  my $client = client();
  eval { Dashboard::App->new(config_file => "$file", mcpan => $client)->run };
  like($@, $error, "invalid global $key is rejected");
  like($@, qr/\Q$file\E/, 'global error identifies configuration file');
  is($client->{calls} // 0, 0, 'invalid global configuration makes no network calls');
  ok(!$temp->child('site')->exists, 'invalid global configuration creates no partial site');
}

my $author = { author => {cpan => 'EXAMPLE', github => 'example-user'}, ci => {} };
my $normalized = normalize_author($json->decode($json->encode($author)), 'EXAMPLE.json');
is_deeply($normalized->{sort}, {column => 'name', direction => 'asc'}, 'author defaults use stable sort names');
is_deeply($normalized->{ci}{gh_workflow_names}, [], 'omitted workflow names default to empty array');
is($normalized->{ci}{use_gh_actions}, 0, 'omitted CI flags default to disabled');

for my $case ([0 => 'name'], [3 => 'date'], [name => 'name'], [repo => 'name'], [DATE => 'date']) {
  my $data = $json->decode($json->encode($author));
  $data->{sort} = {column => $case->[0], direction => 'DESC'};
  my $sort = normalize_author($data, 'EXAMPLE.json')->{sort};
  is_deeply($sort, {column => $case->[1], direction => 'desc'}, 'legacy/symbolic sort settings normalize');
}

write_config($global);
my $good = $temp->child('authors/EXAMPLE.json');
$good->spew_utf8($json->encode($author));
my $bad = $temp->child('authors/ZZZ.json');
for my $case (
  [{author => []}, qr/author/],
  [{author => {cpan => '../ESCAPE'}}, qr/author.cpan/],
  [{author => {cpan => 'lowercase'}}, qr/author.cpan/],
  [{author => {cpan => 'OTHER', github => 'bad;name'}}, qr/author.github/],
  [{%$author, ci => []}, qr/ci/],
  [{%$author, ci => {use_gh_actions => 2}}, qr/ci.use_gh_actions/],
  [{%$author, ci => {use_unknown => 1}}, qr/ci.use_unknown/],
  [{%$author, ci => {gh_workflow_names => 'CI'}}, qr/ci.gh_workflow_names/],
  [{%$author, ci => {gh_workflow_names => ['']}}, qr/ci.gh_workflow_names/],
  [{%$author, sort => {column => 2}}, qr/sort.column/],
  [{%$author, sort => {column => 'bugs'}}, qr/sort.column/],
  [{%$author, sort => {direction => 'sideways'}}, qr/sort.direction/],
) {
  $bad->spew_utf8($json->encode($case->[0]));
  my $client = client();
  my $application = Dashboard::App->new(config_file => "$file", mcpan => $client);
  my $stdout = '';
  { local *STDOUT; open STDOUT, '>', \$stdout or die $!; eval { $application->run } }
  like($@, $case->[1], 'invalid author field is reported');
  like($@, qr/\Q$bad\E/, 'author error identifies configuration file');
  is($client->{calls} // 0, 0, 'all registrations are validated before the first fetch');
  ok(!$temp->child('data/EXAMPLE/data.json')->exists, 'valid earlier author was not partially written');
  ok(!$temp->child('site')->exists, 'invalid registration creates no partial site');
}
$bad->spew_utf8($json->encode($author));
my $client = client();
{ local *STDOUT; open STDOUT, '>', \my $stdout or die $!;
  eval { Dashboard::App->new(config_file => "$file", mcpan => $client)->run } }
like($@, qr/Duplicate author.cpan/, 'duplicate author IDs are rejected before generation');
is($client->{calls} // 0, 0, 'duplicate registrations make no network calls');

my $boolean = normalize_author({author => {cpan => 'BOOL'},
  ci => {use_gh_actions => JSON::true, gh_workflow_names => ['Build and test']}}, 'BOOL.json');
ok($boolean->{ci}{use_gh_actions}, 'JSON boolean flags are supported');

done_testing;
