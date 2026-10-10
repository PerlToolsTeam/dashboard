use v5.40;
use Test::More;
use JSON;
use Path::Tiny;
use FindBin '$RealBin';
use lib 't/lib';
use Dashboard::TestData qw(client release);
use Dashboard::App;

my $root = path("$RealBin/..")->absolute;
my $temp = Path::Tiny->tempdir;
my $json = JSON->new->canonical;
my $cfg = {
  static_dir => "$root/src", input_dir => "$root/tt_lib", output_dir => "$temp/site",
  author_dir => "$temp/authors", data_dir => "$temp/data", branch_cache_file => "$temp/branches.json",
  index_template => 'index.tt', author_template => 'dashboard.tt', wrapper => 'page.tt',
  page_templates => [], domain => 'example.invalid', fetch_attempts => 1, retry_delay => 0,
};
$temp->child('config.json')->spew_utf8($json->encode($cfg));
$temp->child('authors')->mkpath;
for my $id ('EXAMPLE', 'OTHER') {
  my $author = {author => {cpan => $id, name => "$id Author"}, ci => {}};
  $temp->child("authors/$id.json")->spew_utf8($json->encode($author));
  $temp->child("data/$id")->mkpath;
  $temp->child("data/$id/data.json")->spew_utf8($json->encode({%$author, modules => []}));
}
my $other_before = $temp->child('data/OTHER/data.json')->slurp_utf8;
# Unrelated registration errors must not prevent selected-author development.
$temp->child('authors/BROKEN.json')->spew_utf8('not JSON');
my $output = '';
local *STDOUT;
open STDOUT, '>', \$output or die $!;
my $live = client(releases => [release()]);
Dashboard::App->new(config_file => "$temp/config.json", author => 'EXAMPLE', mcpan => $live)->run;
is($live->{calls}, 1, 'selected gather fetches exactly one author');
is($temp->child('data/OTHER/data.json')->slurp_utf8, $other_before, 'unselected snapshot unchanged');
ok($temp->child('site/EXAMPLE/index.html')->is_file, 'selected dashboard generated');
ok(!$temp->child('site/OTHER')->exists, 'unselected dashboard not generated');
my $index = $temp->child('site/index.html')->slurp_utf8;
like($index, qr{/EXAMPLE/}, 'partial index includes selected author');
unlike($index, qr{/OTHER/}, 'partial index excludes other author');
my $sitemap = $temp->child('site/sitemap.xml')->slurp_utf8;
like($sitemap, qr{/EXAMPLE/}, 'partial sitemap includes selected author');
unlike($sitemap, qr{/OTHER/}, 'partial sitemap excludes other author');

my $offline = client(errors => ['must not fetch']);
Dashboard::App->new(config_file => "$temp/config.json", author => 'EXAMPLE', mcpan => $offline, gather => 0)->run;
is($offline->{calls} // 0, 0, 'selected cached build does not fetch');

for my $id ('example', '../EXAMPLE', 'EXAMPLE/OTHER', '') {
  eval { Dashboard::App->new(config_file => "$temp/config.json", author => $id, mcpan => $offline)->run };
  like($@, qr/Invalid --author/, "rejects invalid selector [$id]");
}
eval { Dashboard::App->new(config_file => "$temp/config.json", author => 'UNKNOWN', mcpan => $offline)->run };
like($@, qr/No registration for author UNKNOWN/, 'unknown gather author has useful error');
is($offline->{calls} // 0, 0, 'unknown author fails before API request');
eval { Dashboard::App->new(config_file => "$temp/config.json", author => 'UNKNOWN', mcpan => $offline, gather => 0)->run };
like($@, qr/UNKNOWN.*data.json/, 'missing selected snapshot is identified');

$temp->child('authors/EXAMPLE.json')->spew_utf8($json->encode({author => {cpan => 'OTHER'}, ci => {}}));
eval { Dashboard::App->new(config_file => "$temp/config.json", author => 'EXAMPLE', mcpan => $offline)->run };
like($@, qr/Author identifier mismatch/, 'selected registration identity checked');
$temp->child('authors/EXAMPLE.json')->spew_utf8($json->encode({author => {cpan => 'EXAMPLE'}, ci => {}}));

sub cli (@args) {
  open my $process, '-|', $^X, "-I$root/lib", "$root/bin/dashboard", @args or die $!;
  my $stdout = do { local $/; <$process> };
  close $process;
  return ($? >> 8, $stdout);
}
my ($status, $stdout) = cli('--build', '--author', 'OTHER', '--config', "$temp/config.json");
is($status, 0, 'CLI selected build with custom config succeeds');
like($stdout, qr/Building/, 'CLI custom config selects build');
unlike($stdout, qr/Gathering/, 'explicit build skips gather');
like($temp->child('site/index.html')->slurp_utf8, qr{/OTHER/}, 'CLI selection changes partial index');
unlike($temp->child('site/index.html')->slurp_utf8, qr{/EXAMPLE/}, 'CLI excludes previous author from partial index');
($status, $stdout) = cli('--help');
is($status, 0, 'CLI help exits successfully without instantiating application');
like($stdout, qr/--author CPANID/, 'help documents author selection');
like($stdout, qr/separate output directory/, 'help explains partial-build output');
{
  local *STDERR;
  open STDERR, '>', \my $errors or die $!;
  ($status, $stdout) = cli('--bogus');
  isnt($status, 0, 'unknown CLI options fail rather than silently selecting cached build');
  ($status, $stdout) = cli('--build', 'unwanted');
  isnt($status, 0, 'unexpected positional arguments fail');
}

# Inject a stub App into the CLI process to verify stage defaults without network.
my $stub = $temp->child('stub/Dashboard/App.pm');
$stub->parent->mkpath;
$stub->spew_utf8(q{package Dashboard::App; sub new {my ($class,%args)=@_; bless \%args,$class} sub run {my ($self)=@_; print "gather=$self->{gather} build=$self->{build} author=$self->{author}\n"} 1;});
open my $process, '-|', $^X, "-I$temp/stub", "$root/bin/dashboard", '--author', 'EXAMPLE' or die $!;
my $defaults = do {local $/; <$process>};
close $process;
is($? >> 8, 0, 'author-only CLI invocation succeeds');
like($defaults, qr/gather=1 build=1 author=EXAMPLE/, 'author-only option retains both-stage defaults');

done_testing;
