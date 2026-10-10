use v5.40;
use Test::More;
use JSON;
use Path::Tiny;
use FindBin '$RealBin';
use lib 't/lib';
use Dashboard::TestData qw(client release);
use Dashboard::App;

my $root=path("$RealBin/..")->absolute;
my $temp=Path::Tiny->tempdir;
my $json=JSON->new;
$temp->child('authors')->mkpath;
$temp->child('data/EXAMPLE')->mkpath;
my $cfg={static_dir=>"$root/src",input_dir=>"$root/tt_lib",output_dir=>"$temp/site",
 author_dir=>"$temp/authors",data_dir=>"$temp/data",branch_cache_file=>"$temp/branches.json",
 index_template=>'index.tt',author_template=>'dashboard.tt',wrapper=>'page.tt',
 page_templates=>[],domain=>'example.invalid',fetch_attempts=>3,retry_delay=>0};
$temp->child('config.json')->spew_utf8($json->encode($cfg));
my $registration={author=>{cpan=>'EXAMPLE'},ci=>{}};
my $file=$temp->child('authors/EXAMPLE.json');
$file->spew_utf8($json->encode($registration));
my $snapshot=$temp->child('data/EXAMPLE/data.json');
$snapshot->spew_utf8($json->encode({%$registration,modules=>[{dist=>'Last-Good',name=>'Last-Good-1.0',auth=>'EXAMPLE'}]}));
my $before=$snapshot->slurp_utf8;
my @warnings;
local $SIG{__WARN__}=sub {push @warnings,@_};
sub app ($api) {Dashboard::App->new(config_file=>"$temp/config.json",mcpan=>$api)}

for my $error ('failed to create a scrolled search','failed to fetch next scrolled batch') {
 my $api=client(errors=>[$error]);
 my $fresh=app($api)->do_author("$file");
 is($api->{calls},2,"retries opaque API error: $error");
 ok(!exists $fresh->{fetch_warning},'successful retry uses fresh data');
}
$snapshot->spew_utf8($before);
my $partial=client(iterator_error=>'failed to fetch next scrolled batch',releases=>[release()]);
my $cached=app($partial)->do_author("$file");
is($partial->{calls},3,'opaque scroll failure restarts complete author fetch within retry limit');
like($cached->{fetch_warning},qr/cached data/,'exhausted scroll retries use snapshot');
is($snapshot->slurp_utf8,$before,'failed pagination preserves last good snapshot');

my $short=client(declared_total=>2,releases=>[release()]);
$cached=app($short)->do_author("$file");
is($short->{calls},3,'silently short iterator is retried');
is($cached->{modules}[0]{dist},'Last-Good','short iterator does not become an incomplete catalogue');
is($snapshot->slurp_utf8,$before,'silently short iterator cannot overwrite snapshot');
like(join('',@warnings),qr/Incomplete release list.*expected 2, received 1/,'count diagnostic identifies short result');

{
 my $foreign=client(releases=>[release(author=>'SOMEONEELSE')]);
 my $parsed=0;
 local *Dashboard::App::module_from_release=sub {++$parsed; die "should never parse foreign release\n"};
 $cached=app($foreign)->do_author("$file");
 is($foreign->{calls},3,'wrong-author response is retried within limit');
 is($parsed,0,'foreign releases rejected before repository lookups or processing');
 is($cached->{modules}[0]{dist},'Last-Good','foreign result falls back to correct author snapshot');
 is($snapshot->slurp_utf8,$before,'foreign result cannot contaminate snapshot');
 like(join('',@warnings),qr/Unexpected release author 'SOMEONEELSE' while gathering EXAMPLE/,'foreign response diagnostic identifies both authors');
}

my $over=client(declared_total=>0,releases=>[release()]);
app($over)->do_author("$file");
is($over->{calls},3,'unexpected extra results are rejected too');
is($snapshot->slurp_utf8,$before,'unexpected extra results preserve cache');

my $empty=client(declared_total=>0,releases=>[]);
my $fresh=app($empty)->do_author("$file");
is($empty->{calls},1,'legitimate empty catalogue succeeds');
is_deeply($fresh->{modules},[],'zero advertised releases produce complete empty catalogue');
ok(!exists $fresh->{fetch_warning},'complete empty catalogue is fresh data');

$snapshot->remove;
my $first=client(iterator_error=>'failed to fetch next scrolled batch');
eval {app($first)->do_author("$file")};
is($first->{calls},3,'first gather also retries opaque pagination failure');
like($@,qr/No usable author snapshot/,'no-cache exhaustion still fails explicitly');
ok(!$snapshot->exists,'failed first gather cannot persist partial snapshot');

done_testing;
