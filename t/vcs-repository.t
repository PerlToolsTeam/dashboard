use v5.40;
use Test::More;
use VCS::Repository;

# This test uses only the candidate CPAN class and its URI dependency.
for my $case (
  ['GitHub', 'github.com', 'example', 'repo'],
  ['GitLab', 'gitlab.com', 'group/subgroup', 'project'],
  ['Bitbucket', 'bitbucket.org', 'example', 'project'],
) {
  my ($host, $hostname, $owner, $name) = @$case;
  my $repo = VCS::Repository->new(host => $host, owner => $owner, name => $name);
  is($repo->host, $host, 'hosting service retained');
  is($repo->hostname, $hostname, 'service default hostname');
  is($repo->type, 'Git', 'known service infers Git');
  ok($repo->is_git && !$repo->is_subversion, 'VCS predicates');
  ok($repo->is_complete, 'explicit identity is complete');
  is($repo->url, "https://$hostname/$owner/$name", 'default style is web');
  is($repo->url(style => 'http'), "https://$hostname/$owner/$name.git", 'http means HTTPS clone URL');
  is($repo->url(style => 'ssh'), "git\@$hostname:$owner/$name.git", 'SSH clone URL');
  for my $url ($repo->url, $repo->url(style => 'http'), $repo->url(style => 'ssh'),
    "ssh://git\@$hostname/$owner/$name.git", "git://$hostname/$owner/$name.git") {
    my $parsed = VCS::Repository->from_url($url);
    ok($parsed, "parse $url") or next;
    is($parsed->raw_url, $url, 'original input is preserved exactly');
    is($parsed->owner, $owner, 'parsed namespace');
    is($parsed->name, $name, 'parsed name');
    is($parsed->url, $repo->url, 'constructed and parsed web URLs agree');
  }
}

my $public = VCS::Repository->new(hostname => 'github.com', owner => 'example', name => 'repo');
ok($public->is_github, 'hostname identifies a known service');
ok(!$public->is_gitlab && !$public->is_bitbucket, 'service predicates distinguish providers');

my $private = VCS::Repository->from_url('https://forge.example/team/subgroup/project.git', host => 'GitLab');
is($private->hostname, 'forge.example', 'actual hostname separate from service');
is($private->owner, 'team/subgroup', 'explicit self-hosted provider parses namespaces');
is($private->url, 'https://forge.example/team/subgroup/project', 'self-hosted URL uses actual hostname');

my $unknown_url = 'https://source.example/viewvc/project/trunk?revision=42';
my $unknown = VCS::Repository->from_url($unknown_url);
ok($unknown && !$unknown->is_complete, 'unfamiliar layout produces a partial object');
is($unknown->name, undef, 'partial object does not invent a name');
is($unknown->owner, undef, 'partial object does not invent an owner');
is($unknown->type, undef, 'unknown VCS type is preserved');
is($unknown->host, undef, 'hostname does not invent a hosting service');
is($unknown->hostname, 'source.example', 'partial object retains hostname');
is($unknown->raw_url, $unknown_url, 'partial object retains exact input');
is($unknown->url, $unknown_url, 'partial web link remains usable');
is($unknown->url(style => 'http'), undef, 'partial identity cannot invent a clone URL');
is($unknown->url(style => 'ssh'), undef, 'partial identity cannot invent an SSH URL');

my $svn = VCS::Repository->new(type => 'svn', hostname => 'svn.example', owner => 'repos', name => 'project');
ok($svn->is_subversion && !$svn->is_git, 'Subversion type normalized');
is($svn->url, 'https://svn.example/repos/project', 'explicit Subversion web URL');
is($svn->url(style => 'http'), 'https://svn.example/repos/project', 'Subversion clone has no .git suffix');
is($svn->url(style => 'ssh'), 'svn+ssh://svn.example/repos/project', 'Subversion SSH transport');
my $svn_url = 'svn://svn.example/repos/project/trunk';
my $partial_svn = VCS::Repository->from_url($svn_url);
ok($partial_svn->is_subversion, 'svn scheme identifies Subversion');
is($partial_svn->name, undef, 'SVN checkout path cannot establish repository root');
is($partial_svn->raw_url, $svn_url, 'SVN original retained');
is($partial_svn->url, undef, 'SVN transport does not invent a browser URL');
my $svn_ssh = VCS::Repository->from_url('svn+ssh://alice@svn.example/repos/project');
ok($svn_ssh && $svn_ssh->is_subversion, 'Subversion SSH URLs accept a username without a password');
is($svn_ssh->raw_url, 'svn+ssh://alice@svn.example/repos/project', 'SVN SSH username retained in raw URL');
my $svn_web = VCS::Repository->from_url($unknown_url, type => 'Subversion');
ok($svn_web->is_subversion, 'callers can supply type for an ambiguous web URL');
is($svn_web->url, $unknown_url, 'supplied type preserves unfamiliar web layout');

for my $url ('javascript:alert(1)', 'file:///etc/passwd', 'https://user:secret@github.com/example/repo',
  "https://github.com/example/repo\n", 'https://github.com/example/repo bad',
  'ssh://other@github.com/example/repo', 'svn+ssh://alice:secret@svn.example/repos/project',
  'https://example..invalid/project') {
  is(VCS::Repository->from_url($url), undef, "reject unsafe or unsupported input: $url");
}
for my $url ('https://github.com/example/repo/issues', 'https://github.com/example/repo?x=1',
  'https://github.com/example/repo#fragment', 'https://gitlab.com/group/project/-/tree/main',
  'https://github.com:1234/example/repo') {
  my $repo = VCS::Repository->from_url($url);
  ok($repo && !$repo->is_complete, 'service page or nonstandard port is not a complete repository identity');
  is($repo->url, $url, 'unrecognised web link is preserved');
}
for my $args (
  {}, {name => '..'}, {name => 'repo', owner => 'example;touch-marker', host => 'GitHub'},
  {name => 'repo', owner => 'nested/group', hostname => 'github.com'},
  {name => 'repo', host => 'GitHub', type => 'Subversion'},
  {name => 'repo', owner => 'example', path => 'other/repo', host => 'GitHub'},
  {raw_url => 'https://github.com/example/repo', owner => 'other'},
  {raw_url => 'https://github.com/example/repo', hostname => 'evil.invalid'},
  {name => 'repo', hostname => 'evil.invalid', host => 'GitHub', owner => []},
) {
  eval { VCS::Repository->new(%$args) };
  ok($@, 'invalid or contradictory explicit fields are rejected');
}
eval { $public->url(style => 'ftp') };
like($@, qr/Unsupported repository URL style/, 'unsupported output styles report an error');
eval { $public->url(stlye => 'http') };
like($@, qr/Unknown repository URL option/, 'misspelled options report an error');

done_testing;
