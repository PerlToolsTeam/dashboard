requires 'perl', '5.040';
requires 'JSON';
requires 'Path::Tiny', '0.125';
requires 'Template';
requires 'MetaCPAN::Client';
requires 'HTTP::Tiny';
requires 'URI';

on 'test' => sub {
  requires 'Test::More';
};
