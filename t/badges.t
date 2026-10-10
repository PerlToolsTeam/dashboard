use v5.40;
use utf8;
use Test::More;
use Dashboard::BadgeMaker;
use Dashboard::Config qw(normalize_author effective_ci);

my $badges = Dashboard::BadgeMaker->new;
my $module = {dist => 'Example', repo => 'https://github.com/example/repo', repo_owner => 'example', repo_name => 'repo'};
my $named = $badges->gh($module, 'Build & test');
like($named, qr{workflows/Build%20%26%20test/badge.svg}, 'workflow display name is encoded as one path component');
like($named, qr{query=workflow%3A%22Build%20%26%20test%22}, 'workflow search uses an encoded quoted name');
like($named, qr/alt="GH Action Build &amp; test"/, 'badge alt text is HTML escaped');
my $file = $badges->gh_file($module, 'perl test.yml');
like($file, qr{actions/workflows/perl%20test.yml/badge.svg}, 'workflow filenames use the documented badge endpoint');
my $hostile = $badges->gh($module, 'CI" onclick="alert(1)');
unlike($hostile, qr/onclick="alert/, 'workflow text cannot escape the image attribute');
like($hostile, qr/&quot;/, 'quotes remain text in alt attribute');
is($badges->gh_badges($module, {use_gh_actions => 0, gh_workflow_names => ['CI']}), '', 'disabled row has no workflow links');
my $combined = $badges->gh_badges($module, {use_gh_actions => 1,
  gh_workflow_names => ['CI'], gh_workflow_files => ['test.yml']});
is(scalar(() = $combined =~ /<img /g), 2, 'named and file-based workflows can both be displayed');
like($combined, qr/<br>/, 'multiple workflow badges remain separated');

my $branched = {%$module, repo_def_branch => 'feature/api&docs#2'};
for my $service (qw(travis travis_com coveralls codecov)) {
  my $html = $badges->$service($branched);
  like($html, qr{feature%2Fapi%26docs%232}, "$service encodes the complete branch name");
  unlike($html, qr{feature/api&amp;docs#2}, "$service cannot turn branch punctuation into URL syntax");
}
like($badges->cirrus($module, 'Test & docs'), qr{task=Test%20%26%20docs},
  'Cirrus task names remain one query value');

my $author = normalize_author({author => {cpan => 'EXAMPLE'},
  ci => {use_gh_actions => 1, use_coveralls => 1, gh_workflow_names => ['CI']},
  distribution_ci => {Disabled => {use_gh_actions => 0}, Different => {gh_workflow_names => ['Build']}}
}, 'EXAMPLE.json');
my $disabled = effective_ci($author, 'Disabled');
is($disabled->{use_gh_actions}, 0, 'distribution override disables inherited service');
is($disabled->{use_coveralls}, 1, 'unspecified service inherits author default');
is_deeply(effective_ci($author, 'Different')->{gh_workflow_names}, ['Build'], 'distribution override replaces workflow list');
is_deeply(effective_ci($author, 'Other')->{gh_workflow_names}, ['CI'], 'other distributions retain global workflows');

for my $override ([], {Bad => []}, {Bad => {use_coveralls => 2}},
  {Bad => {gh_workflow_files => ['../test.yml']}}, {Bad => {gh_workflow_names => 'CI'}}) {
  eval { normalize_author({author => {cpan => 'EXAMPLE'}, distribution_ci => $override}, 'EXAMPLE.json') };
  like($@, qr/distribution_ci/, 'invalid distribution override is rejected with field context');
}

done_testing;
