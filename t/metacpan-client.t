use v5.40;
use Test::More;
use JSON;
use Path::Tiny;
use FindBin '$RealBin';
use MetaCPAN::Client;
use Dashboard::App;

{
 package Local::MetaCPANHTTP;
 sub new ($class) {bless {searches=>0,queries=>[]},$class}
 sub response ($self,$data) {return {status=>200,success=>1,content=>JSON::encode_json($data)}}
 sub get ($self,$url) {
  return $self->response({production=>{url=>'https://api.example.invalid/v1',domain=>'https://api.example.invalid'}})
   if $url eq 'https://clientinfo.metacpan.org';
  die "Unexpected GET $url\n" unless $url =~ m{/author/EXAMPLE$};
  return $self->response({pauseid=>'EXAMPLE',name=>'Example Author'});
 }
 sub post ($self,$url,$options) {
  my $query=JSON::decode_json($options->{content});
  if ($url =~ m{/release/_search\?}) {
   ++$self->{searches};
   push @{$self->{queries}},$query;
   return $self->response({_scroll_id=>'fixture-scroll',hits=>{
    total=>$self->{searches}==1 ? 2 : 1,
    hits=>[{_source=>{name=>'Example-1.0',distribution=>'Example',version=>'1.0',
     author=>'EXAMPLE',date=>'2026-10-10T00:00:00',resources=>{}}}]
   }});
  }
  die "Unexpected POST $url\n" unless $url =~ m{/_search/scroll\?};
  ++$self->{scrolls};
  return {status=>503,success=>0,reason=>'Service Unavailable',content=>'Service Unavailable'};
 }
 sub delete ($self,$url,$options) {return {status=>200,success=>1,content=>'{}'}}
}
my $temp=Path::Tiny->tempdir;
my $root=path("$RealBin/..")->absolute;
my $json=JSON->new;
$temp->child('authors')->mkpath;
my $registration={author=>{cpan=>'EXAMPLE'},ci=>{}};
my $file=$temp->child('authors/EXAMPLE.json');
$file->spew_utf8($json->encode($registration));
my $cfg={static_dir=>"$root/src",input_dir=>"$root/tt_lib",output_dir=>"$temp/site",
 author_dir=>"$temp/authors",data_dir=>"$temp/data",branch_cache_file=>"$temp/branches.json",
 index_template=>'index.tt',author_template=>'dashboard.tt',wrapper=>'page.tt',
 page_templates=>[],domain=>'example.invalid',fetch_attempts=>3,retry_delay=>0};
$temp->child('config.json')->spew_utf8($json->encode($cfg));
my $ua=Local::MetaCPANHTTP->new;
my $api=MetaCPAN::Client->new(ua=>$ua);
my @warnings;
local $SIG{__WARN__}=sub {push @warnings,@_};
my $fresh=Dashboard::App->new(config_file=>"$temp/config.json",mcpan=>$api)->do_author("$file");
is($ua->{searches},2,'real client restarts filtered search after HTTP 503 during pagination');
is($ua->{scrolls},1,'real client actually reaches a failing scroll request');
for my $query (@{$ua->{queries}}) {
 is_deeply($query->{query},{bool=>{must=>[{term=>{author=>'EXAMPLE'}},{term=>{status=>'latest'}}]}},
  'initial and retried real client queries preserve author and latest filters');
}
is(scalar @{$fresh->{modules}},1,'complete restarted fetch produces one valid distribution');
is($fresh->{modules}[0]{auth},'EXAMPLE','real client response is associated with requested author');
ok(!exists $fresh->{fetch_warning},'successful pagination retry produces fresh metadata');
ok($temp->child('data/EXAMPLE/data.json')->is_file,'successful first gather persists snapshot after restart');
like(join('',@warnings),qr/failed to fetch next scrolled batch/,'native opaque client exception is recognized');
done_testing;
