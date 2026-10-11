use v5.40;
use Test::More;
use Path::Tiny;
use JSON;
use FindBin '$RealBin';
use VCS::Repository;
use Dashboard::GitHub;
use Dashboard::BranchCache;
use Dashboard::BadgeMaker;

for my $url (
  'https://github.com/example/repo', 'https://GITHUB.COM/example/repo.git///',
  'http://github.com/example/repo/', 'git://github.com/example/repo.git',
  'ssh://git@github.com/example/repo.git', 'git@github.com:example/repo.git',
) {
  my $repo = VCS::Repository->from_url($url);
  is_deeply({owner => $repo->owner, name => $repo->name, url => $repo->url}, {
    owner => 'example', name => 'repo', url => 'https://github.com/example/repo',
  }, "normalize $url");
}

for my $url (
  undef, '', 'https://github.com.evil.invalid/example/repo',
  'https://evil.invalid/github.com/example/repo',
  'https://github.com@example.invalid/example/repo',
  'https://user:password@github.com/example/repo',
  'https://github.com/example', 'https://github.com/example/repo/issues',
  'https://github.com/example/..', 'https://github.com/example/repo?x=1',
  'https://github.com/example/repo#fragment',
  'https://github.com/example/repo;touch-marker',
  q{https://github.com/example/$(touch-marker)},
  "https://github.com/example/repo\n", 'ftp://github.com/example/repo',
) {
  my $repo = VCS::Repository->from_url($url);
  ok(!($repo && $repo->is_github && $repo->is_complete),
    'reject misleading or malformed GitHub identity: ' . ($url // 'undef'));
}

my $temp = Path::Tiny->tempdir;
my $gh = $temp->child('gh');
$gh->spew_utf8("#!$^X\n" . <<'STUB');
use strict;
use warnings;
use JSON;
open my $fh, '>>', $ENV{DASHBOARD_GH_LOG} or die $!;
print {$fh} encode_json(\@ARGV), "\n";
close $fh;
print $ENV{DASHBOARD_GH_OUTPUT} // "main\n";
exit($ENV{DASHBOARD_GH_STATUS} // 0);
STUB
chmod 0755, "$gh" or die $!;
local $ENV{PATH} = "$temp:$ENV{PATH}";
local $ENV{DASHBOARD_GH_LOG} = $temp->child('calls');
local $ENV{DASHBOARD_GH_OUTPUT} = "main\n";
local $ENV{DASHBOARD_GH_STATUS} = 0;

my $github = Dashboard::GitHub->new;
my $repository = VCS::Repository->new(host => 'GitHub', owner => 'example', name => 'repo');
my $unexecuted = VCS::Repository->from_url('git@example.invalid:team/project.git');
is($unexecuted->type, undef, 'unknown SSH host does not guess a VCS type');
ok(!path($ENV{DASHBOARD_GH_LOG})->exists, 'constructing and parsing repository objects never invokes gh');
is($github->lookup_default_branch($repository), 'main', 'lookup succeeds');
is_deeply(decode_json((path($ENV{DASHBOARD_GH_LOG})->lines_utf8)[0]),
  ['repo', 'view', 'example/repo', '--json', 'defaultBranchRef', '-q', '.defaultBranchRef.name'],
  'GitHub CLI receives separate literal arguments');
eval { VCS::Repository->new(host => 'GitHub', owner => 'example;touch-marker', name => 'repo') };
like($@, qr/Invalid repository owner/, 'invalid cache keys never reach the CLI');
is(scalar path($ENV{DASHBOARD_GH_LOG})->lines_utf8, 1, 'invalid input did not run gh');
for my $repo (
  VCS::Repository->from_url('https://gitlab.com/example/repo'),
  VCS::Repository->from_url('https://github.com/example/repo/issues'),
  VCS::Repository->new(host => 'GitHub', hostname => 'enterprise.example', owner => 'example', name => 'repo'),
) {
  eval { $github->lookup_default_branch($repo) };
  like($@, qr/Invalid GitHub repository/, 'adapter rejects unsupported or incomplete identities');
}
is(scalar path($ENV{DASHBOARD_GH_LOG})->lines_utf8, 1, 'unsupported identities never invoke gh');

my $file = $temp->child('branches.json');
$file->spew_utf8(encode_json({ example => { good => 'stable', empty => '' } }));
my $cache = Dashboard::BranchCache->new(file => "$file");
is($cache->get('example', 'good'), 'stable', 'valid cached branch avoids lookup');
is($cache->get('example', 'empty'), 'main', 'existing empty cache entry is retried');
$cache->save;
is(decode_json($file->slurp_utf8)->{example}{empty}, 'main', 'successful lookup persisted');

local $ENV{DASHBOARD_GH_STATUS} = 1;
my @warnings;
local $SIG{__WARN__} = sub { push @warnings, @_ };
is($cache->get('example', 'good', 1), 'stable', 'failed refresh returns the old branch');
is($cache->get('example', 'missing'), '', 'failed lookup without cache returns no branch');
$cache->save;
my $saved = decode_json($file->slurp_utf8);
is($saved->{example}{good}, 'stable', 'failed refresh does not erase a valid cache entry');
ok(!exists($saved->{example}{missing}), 'failure does not persist an empty branch');
like(join('', @warnings), qr/example\/good.*failed/, 'failure diagnostic identifies repository');

local $ENV{DASHBOARD_GH_STATUS} = 0;
my $next = Dashboard::BranchCache->new(file => "$file");
is($next->get('example', 'missing'), 'main', 'a later cache instance retries a failed lookup');
local $ENV{DASHBOARD_GH_OUTPUT} = "\n";
is($next->get('example', 'good', 1), 'stable', 'empty successful output also preserves old branch');

{
  my $before = $file->slurp_utf8;
  local *Path::Tiny::move = sub { die "simulated rename failure\n" };
  eval { $next->save };
  like($@, qr/simulated rename failure/, 'cache write failure is reported');
  is($file->slurp_utf8, $before, 'failed atomic replacement preserves the previous cache file');
}

{
  my $cwd = Path::Tiny->cwd;
  chdir "$temp" or die $!;
  path('repo_def_branch.json')->spew_utf8(encode_json({ example => { repo => 'stable' },
    'bad;owner' => { repo => 'stable' } }));
  open my $process, '-|', $^X, "$RealBin/../refresh_branch_cache" or die $!;
  my $output = do { local $/; <$process> };
  close $process;
  is($?, 0, 'refresh script completes after empty and malformed lookups');
  is(decode_json(path('repo_def_branch.json')->slurp_utf8)->{example}{repo}, 'stable',
    'refresh script preserves the last-known-good branch on empty output');
  chdir "$cwd" or die $!;
}

my $badges = Dashboard::BadgeMaker->new;
is($badges->gh({repo => 'https://evil.invalid/github.com/example/repo',
  repo_owner => 'example', repo_name => 'repo'}, 'CI'), '', 'misleading host has no GitHub badge');
is($badges->gh({repo => 'https://github.com/example/repo',
  repo_owner => 'other', repo_name => 'repo'}, 'CI'), '', 'mismatched cached owner has no badge');

done_testing;
