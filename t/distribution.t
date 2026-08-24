use FindBin '$RealBin';
use Test::More;

use JSON;
use MetaCPAN::Client;
use HTTP::Tiny;

use Dashboard::Distribution;

my $release = MetaCPAN::Client->new->release('Array-Compare');

ok(my $dist = Dashboard::Distribution->new_from_release($release),
    'Got a distribution');

isa_ok($dist, 'Dashboard::Distribution', '... of the right class');
is($dist->distribution, 'Array-Compare', '... with the right distribution name');
is($dist->main_module_name, 'Array::Compare', '... with the right main module name');

# Test Dashboard::App user agent configuration
use Dashboard::App;

# Test Dashboard::App instantiation
my $app = Dashboard::App->new(gather => 0, build => 0);
isa_ok($app, 'Dashboard::App', 'Dashboard::App object created successfully');

# Verify we can access the MetaCPAN client
my $app_mcpan = $app->mcpan;
isa_ok($app_mcpan, 'MetaCPAN::Client', 'Dashboard::App has MetaCPAN::Client');

# Test the actual user agent string in the MetaCPAN::Client
my $app_ua = $app_mcpan->ua;
isa_ok($app_ua, 'HTTP::Tiny', 'MetaCPAN::Client has HTTP::Tiny user agent');
is($app_ua->{agent}, "CPAN Dashboard/$Dashboard::App::VERSION", 'Dashboard::App MetaCPAN::Client configured with correct user agent');

done_testing;
