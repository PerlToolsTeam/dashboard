use strict;
use warnings;

use Plack::Builder;

use Plack::App::File;
my $app = Plack::App::File->new(root => 'docs')->to_app;

builder {
      enable "DirIndex", dir_index => 'index.html';
      $app;
}
