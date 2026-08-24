use FindBin '$RealBin';
use Test::More;

use JSON;
use MetaCPAN::Client;

use Dashboard::Author;

ok(my $author = Dashboard::Author->new_from_file(
    "$RealBin/../authors/DAVECROSS.json",
    MetaCPAN::Client->new,
    JSON->new->pretty->canonical->utf8),
    'Got an author');

isa_ok($author, 'Dashboard::Author', '... of the right class');
is($author->name, 'Dave Cross', '... with the right name');
is($author->cpan_name, 'DAVECROSS', '... with the right CPAN name');
is($author->github_name, 'davorg', '... with the right GitHub name');

done_testing;
