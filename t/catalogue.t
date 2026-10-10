use v5.40;
use Test::More;
use Path::Tiny;
use JSON;
use FindBin '$RealBin';
use lib 't/lib';
use Dashboard::TestData qw(client);
use Dashboard::App;

my $temp = Path::Tiny->tempdir;
my $root = path("$RealBin/..")->absolute;
my $json = JSON->new->canonical;
$temp->child('authors')->mkpath;
$temp->child('data/EXAMPLE')->mkpath;
my $config = {static_dir => "$root/src", input_dir => "$root/tt_lib", output_dir => "$temp/site",
  author_dir => "$temp/authors", data_dir => "$temp/data", branch_cache_file => "$temp/branches.json",
  domain => 'example.invalid', index_template => 'index.tt', author_template => 'dashboard.tt',
  wrapper => 'page.tt', page_templates => []};
$temp->child('config.json')->spew_utf8($json->encode($config));
my $registration = {author => {cpan => 'EXAMPLE'},
  ci => {use_gh_actions => 1, use_coveralls => 1, gh_workflow_names => ['CI']},
  distribution_ci => {Beta => {use_gh_actions => 0, use_coveralls => 0},
    FileWorkflow => {gh_workflow_names => [], gh_workflow_files => ['perl test.yml']}}};
my $file = $temp->child('authors/EXAMPLE.json');
$file->spew_utf8($json->encode($registration));
my @modules;
for my $name (qw(Alpha Beta NoRepo GitLab Bitbucket FileWorkflow Unsafe)) {
  push @modules, {name => "$name-1.0", dist => $name, ver => '1.0', auth => 'EXAMPLE', date => '2026-10-10'};
  my $module = $modules[-1];
  if ($name eq 'GitLab') { $module->{repo} = 'https://gitlab.com/group/subgroup/project' }
  elsif ($name eq 'Bitbucket') { $module->{repo} = 'https://bitbucket.org/example/project' }
  elsif ($name eq 'Unsafe') { @$module{qw(repo bugtracker)} = ('javascript:alert(1)', 'javascript:alert(2)') }
  elsif ($name ne 'NoRepo') {
    @$module{qw(repo repo_owner repo_name repo_def_branch)} =
      ("https://github.com/example/$name", 'example', $name, 'main');
  }
}
my $snapshot = $temp->child('data/EXAMPLE/data.json');
$snapshot->spew_utf8($json->encode({%$registration, modules => \@modules}));
my $before = $snapshot->slurp_utf8;
my $offline = client(errors => ['network must not be used']);
sub build {
  local *STDOUT; open STDOUT, '>', \my $output or die $!;
  Dashboard::App->new(config_file => "$temp/config.json", gather => 0, mcpan => $offline)->run;
}
build();
my $html = $temp->child('site/EXAMPLE/index.html')->slurp_utf8;
my ($tbody) = $html =~ m{<tbody>(.*?)</tbody>}s;
my @rows = $tbody =~ m{<tr>(.*?)</tr>}sg;
is(scalar @rows, scalar @modules, 'every distribution is rendered, including no-repo and non-GitHub entries');
my %rows;
for my $name (map { $_->{dist} } @modules) {
  ($rows{$name}) = grep { /\Q$name\E/ } @rows;
  ok(defined $rows{$name}, "distribution row is present: $name");
}
like($rows{Alpha}, qr{workflows/CI/badge.svg}, 'global workflow default applies to unmodified distribution');
like($rows{Alpha}, qr{coveralls.io}, 'global coverage default applies');
unlike($rows{Beta}, qr{workflows/|coveralls.io}, 'per-distribution disabled services emit no links');
like($rows{FileWorkflow}, qr{actions/workflows/perl%20test.yml/badge.svg}, 'per-distribution workflow filename is used');
unlike($rows{FileWorkflow}, qr{workflows/CI/badge.svg}, 'empty workflow-name override replaces global list');
for my $name (qw(NoRepo GitLab Bitbucket Unsafe)) {
  unlike($rows{$name}, qr{workflows/|coveralls.io}, "$name has no GitHub-specific service links");
  like($rows{$name}, qr{img.shields.io/cpan/}, "$name retains CPAN version badge");
  like($rows{$name}, qr{cpants.cpanauthors.org}, "$name retains CPANTS badge");
}
like($rows{GitLab}, qr{href="https://gitlab.com/group/subgroup/project"}, 'nested GitLab repository link is preserved');
like($rows{Bitbucket}, qr{href="https://bitbucket.org/example/project"}, 'Bitbucket repository link is preserved');
unlike($html, qr{href="javascript:}, 'unsafe repository and bugtracker protocols are not linked');
my ($thead) = $html =~ m{<thead>(.*?)</thead>}s;
my $columns = scalar(() = $thead =~ /<th\b/g);
for my $row (@rows) { is(scalar(() = $row =~ /<td\b/g), $columns, 'disabled service cells preserve table alignment') }

$registration->{distribution_ci}{FileWorkflow}{use_gh_actions} = 0;
$file->spew_utf8($json->encode($registration));
build();
unlike($temp->child('site/EXAMPLE/index.html')->slurp_utf8, qr{actions/workflows/perl%20test.yml/badge.svg},
  'build-only picks up changed CI settings without refreshing release metadata');
is($offline->{calls} // 0, 0, 'catalogue builds make no metadata requests');
is($snapshot->slurp_utf8, $before, 'display setting changes do not rewrite persistent metadata');
my $published = $json->decode($temp->child('site/EXAMPLE/data.json')->slurp_utf8);
is($published->{modules}[5]{ci}{use_gh_actions}, 0, 'published JSON reflects the same effective CI settings as HTML');

done_testing;
