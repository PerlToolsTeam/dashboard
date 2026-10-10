use v5.40;
use Test::More;
use JSON;
use Path::Tiny;
use lib 't/lib';
use Dashboard::TestData qw(client release);
use Dashboard::Author;

my $temp = Path::Tiny->tempdir;
my $file = $temp->child('EXAMPLE.json');
$file->spew_utf8(encode_json({ author => { cpan => 'EXAMPLE', github => 'example-user' },
  ci => { use_gh_actions => 1, gh_workflow_names => ['CI'] } }));
my $author = Dashboard::Author->new_from_file("$file", client(), JSON->new);
isa_ok($author, 'Dashboard::Author');
is($author->name, 'Example Author', 'name comes from fixture');
is($author->cpan_name, 'EXAMPLE', 'CPAN identifier comes from configuration');
is($author->github_name, 'example-user', 'GitHub name comes from configuration');
is(scalar @{ $author->distributions }, 1, 'release without a repo is retained');
is($author->distributions->[0]->distribution, 'Example', 'distribution is populated');
is($author->ci->{use_gh_actions}, 1, 'CI selection retained');
done_testing;
