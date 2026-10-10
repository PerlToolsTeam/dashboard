package Dashboard::Config;
use v5.40;
use Exporter 'import';
use JSON;
use Path::Tiny;
use File::Spec;
use Dashboard::Repository qw(github_repository resource_url);
our @EXPORT_OK = qw(read_json_file read_global_config normalize_author effective_ci);

sub invalid ($file, $field, $message) {
  die "Invalid configuration in $file: $field $message\n";
}

sub read_json_file ($file) {
  my ($data, $error);
  eval { $data = JSON->new->decode(path($file)->slurp_utf8); 1 } or $error = $@;
  die "Cannot read JSON from $file: $error" if $error;
  return $data;
}

sub text ($value) {
  return defined($value) && !ref($value) && length($value) && $value !~ /[\x00-\x1f\x7f]/;
}

sub location ($file) {
  my ($volume, $directories, $filename) = File::Spec->splitpath(path($file)->absolute);
  my $resolved = path(File::Spec->catpath($volume, File::Spec->rootdir, ''));
  for my $part (File::Spec->splitdir($directories), $filename) {
    next if $part eq '' || $part eq '.';
    $resolved = $part eq '..' ? $resolved->parent : $resolved->child($part);
    $resolved = $resolved->realpath if $resolved->exists;
  }
  return "$resolved";
}

sub within ($child, $parent) {
  my $prefix = $parent;
  $prefix .= '/' unless $prefix =~ m{/\z};
  return $child eq $parent || index($child, $prefix) == 0;
}

sub read_global_config ($file) {
  my $cfg = read_json_file($file);
  invalid($file, 'root', 'must be an object') unless ref($cfg) eq 'HASH';
  my %defaults = (author_dir => 'authors', data_dir => 'authors/data',
    branch_cache_file => 'repo_def_branch.json', fetch_attempts => 3,
    http_timeout => 20, retry_delay => 1);
  $cfg->{$_} //= $defaults{$_} for keys %defaults;
  for my $key (qw(static_dir input_dir output_dir author_dir data_dir branch_cache_file domain
    index_template author_template wrapper)) {
    invalid($file, $key, 'must be a non-empty string') unless text($cfg->{$key});
  }
  for my $key (qw(static_dir input_dir)) {
    invalid($file, $key, 'must name an existing directory') unless path($cfg->{$key})->is_dir;
  }
  for my $key (qw(author_dir data_dir)) {
    invalid($file, $key, 'must name a directory')
      if path($cfg->{$key})->exists && !path($cfg->{$key})->is_dir;
  }
  invalid($file, 'output_dir', 'must not name a file') if path($cfg->{output_dir})->is_file;
  my $output = location($cfg->{output_dir});
  for my $key (qw(static_dir input_dir author_dir data_dir)) {
    my $source = location($cfg->{$key});
    invalid($file, 'output_dir', "must be separate from $key")
      if within($output, $source) || within($source, $output);
  }
  invalid($file, 'branch_cache_file', 'must be outside output_dir')
    if within(location($cfg->{branch_cache_file}), $output);
  my ($host, $port) = $cfg->{domain} =~ /\A([^:]+)(?::([0-9]+))?\z/;
  invalid($file, 'domain', 'must be a hostname with an optional valid port')
    unless defined($host) && length($host) <= 253
      && !grep { length($_) > 63 || $_ !~ /\A[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?\z/ }
        split(/\./, $host, -1);
  invalid($file, 'domain', 'has an invalid port') if defined($port) && ($port < 1 || $port > 65535);
  for my $key (qw(index_template author_template wrapper)) {
    invalid($file, $key, 'must name a template in input_dir')
      unless $cfg->{$key} =~ /\A[A-Za-z0-9_-]+\.tt\z/
        && path($cfg->{input_dir}, $cfg->{$key})->is_file;
  }
  invalid($file, 'input_dir', 'must contain sitemap.tt')
    unless path($cfg->{input_dir}, 'sitemap.tt')->is_file;
  $cfg->{page_templates} //= [];
  invalid($file, 'page_templates', 'must be an array') unless ref($cfg->{page_templates}) eq 'ARRAY';
  for my $page (@{ $cfg->{page_templates} }) {
    invalid($file, 'page_templates', 'must contain existing page template names')
      unless text($page) && $page =~ /\A[a-z][a-z0-9_-]*\z/
        && path($cfg->{input_dir}, "$page.tt")->is_file;
  }
  for my $setting ([fetch_attempts => 1, 5], [http_timeout => 1, 60], [retry_delay => 0, 10]) {
    my ($key, $min, $max) = @$setting;
    invalid($file, $key, "must be an integer between $min and $max")
      unless defined($cfg->{$key}) && !ref($cfg->{$key}) && $cfg->{$key} =~ /\A[0-9]+\z/
        && $cfg->{$key} >= $min && $cfg->{$key} <= $max;
  }
  if (defined($cfg->{analytics})) {
    invalid($file, 'analytics', 'must contain only letters, digits, and hyphens')
      unless $cfg->{analytics} eq '' || $cfg->{analytics} =~ /\A[A-Za-z0-9-]+\z/;
  }
  $cfg->{menu} //= [];
  invalid($file, 'menu', 'must be an array') unless ref($cfg->{menu}) eq 'ARRAY';
  for my $item (@{ $cfg->{menu} }) {
    invalid($file, 'menu', 'must contain objects with a title and a web or site-relative link')
      unless ref($item) eq 'HASH' && text($item->{title}) && text($item->{link})
        && $item->{link} =~ m{\A(?:https?://|/(?!/))};
  }
  return $cfg;
}

sub normalize_ci ($ci, $file, $field, $defaults = 1) {
  invalid($file, $field, 'must be an object') unless ref($ci) eq 'HASH';
  my %flags = map { ("use_$_", 1) } qw(gh_actions cirrus appveyor travis travis_com coveralls codecov);
  my %lists = map { $_ => 1 } qw(gh_workflow_names gh_workflow_files cirrus_task_names);
  for my $key (keys %$ci) {
    invalid($file, "$field.$key", 'is not a supported setting') unless $flags{$key} || $lists{$key};
  }
  for my $key (keys %flags) {
    $ci->{$key} //= 0 if $defaults;
    next unless exists $ci->{$key};
    invalid($file, "$field.$key", 'must be 0, 1, or a JSON boolean')
      unless defined($ci->{$key}) && (JSON::is_bool($ci->{$key})
        || (!ref($ci->{$key}) && $ci->{$key} =~ /\A[01]\z/));
  }
  for my $key (keys %lists) {
    $ci->{$key} //= [] if $defaults;
    next unless exists $ci->{$key};
    invalid($file, "$field.$key", 'must be an array of non-empty names')
      unless ref($ci->{$key}) eq 'ARRAY' && !grep { !text($_) || $_ !~ /\S/ } @{ $ci->{$key} };
  }
  for my $filename (@{ $ci->{gh_workflow_files} // [] }) {
    invalid($file, "$field.gh_workflow_files", 'must contain workflow YAML filenames')
      unless $filename =~ /\A[^\/\\]+\.ya?ml\z/i;
  }
  return $ci;
}

sub effective_ci ($data, $distribution) {
  return { %{ $data->{ci} }, %{ $data->{distribution_ci}{$distribution} // {} } };
}

sub normalize_author ($data, $file) {
  invalid($file, 'root', 'must be an object') unless ref($data) eq 'HASH';
  invalid($file, 'author', 'must be an object') unless ref($data->{author}) eq 'HASH';
  my $author = $data->{author};
  invalid($file, 'author.cpan', 'must be an uppercase CPAN identifier')
    unless text($author->{cpan}) && $author->{cpan} =~ /\A[A-Z][A-Z0-9]*\z/;
  $author->{github} //= '';
  invalid($file, 'author.github', 'must be a GitHub username or an empty string')
    unless !ref($author->{github}) && ($author->{github} eq ''
      || $author->{github} =~ /\A[A-Za-z0-9][A-Za-z0-9-]*\z/);
  $data->{ci} //= {};
  normalize_ci($data->{ci}, $file, 'ci');
  $data->{distribution_ci} //= {};
  invalid($file, 'distribution_ci', 'must be an object') unless ref($data->{distribution_ci}) eq 'HASH';
  for my $distribution (keys %{ $data->{distribution_ci} }) {
    invalid($file, 'distribution_ci', 'keys must be distribution names')
      unless $distribution =~ /\A[A-Za-z0-9][A-Za-z0-9_.-]*\z/;
    normalize_ci($data->{distribution_ci}{$distribution}, $file, "distribution_ci.$distribution", 0);
  }
  $data->{sort} //= {};
  invalid($file, 'sort', 'must be an object') unless ref($data->{sort}) eq 'HASH';
  my %columns = (0 => 'name', 3 => 'date', name => 'name', repo => 'name', date => 'date');
  my $column = $data->{sort}{column} // 'name';
  invalid($file, 'sort.column', 'must be name, repo, date, 0, or 3')
    unless !ref($column) && exists $columns{lc($column)};
  $data->{sort}{column} = $columns{lc($column)};
  my $direction = $data->{sort}{direction} // 'asc';
  invalid($file, 'sort.direction', 'must be asc or desc')
    unless !ref($direction) && $direction =~ /\A(?:asc|desc)\z/i;
  $data->{sort}{direction} = lc($direction);
  if (exists $data->{modules}) {
    invalid($file, 'modules', 'must be an array of distribution records')
      unless ref($data->{modules}) eq 'ARRAY';
    my %display = %{ $data->{ci} };
    for my $module (@{ $data->{modules} }) {
      invalid($file, 'modules', 'must contain objects with distribution names')
        unless ref($module) eq 'HASH' && text($module->{dist});
      if (exists $module->{repo}) {
        my $github = github_repository($module->{repo});
        $module->{repo} = $github ? $github->{url} : resource_url($module->{repo});
      }
      $module->{bugtracker} = resource_url($module->{bugtracker}) // '' if exists $module->{bugtracker};
      $module->{ci} = effective_ci($data, $module->{dist});
      for my $key (grep { /^use_/ } keys %{ $module->{ci} }) {
        $display{$key} = 1 if $module->{ci}{$key};
      }
    }
    $data->{display_ci} = \%display;
  }
  return $data;
}

1;
