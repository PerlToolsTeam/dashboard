# 5.40 because we use :reader
use v5.40;

use feature 'class';
no if $^V >= v5.40, warnings => 'experimental::class';

class Dashboard::App {
  our $VERSION = '1.0.0';

  use Dashboard::BadgeMaker;
  use Dashboard::BranchCache;
  use Dashboard::Repository qw(github_repository resource_url);
  use Dashboard::Config qw(read_json_file read_global_config normalize_author);

  use JSON;
  use Path::Tiny;
  use Template;
  use MetaCPAN::Client;
  use HTTP::Tiny;
  use URI;
  use File::Find;
  use POSIX 'strftime';
  use Time::HiRes ();

  field $json = JSON->new->pretty->canonical;
  field $config_file :param = 'dashboard.json';
  field $selected_author :param(author) = undef;
  field $global_cfg = read_global_config($config_file);
  field $mcpan :reader :param = MetaCPAN::Client->new(
    ua => HTTP::Tiny->new(agent => "CPAN Dashboard/$VERSION",
      timeout => $global_cfg->{http_timeout} // 20)
  );
  field $tt;
  field @authors;
  field @urls;
  field @problems;
  field $run_gather :param(gather) = 1;
  field $run_build :param(build) = 1;
  field $branch_cache = Dashboard::BranchCache->new(
    file => $global_cfg->{branch_cache_file} // 'repo_def_branch.json'
  );

  ADJUST {
    die "Invalid --author: expected an uppercase CPAN identifier\n"
      if defined($selected_author) && $selected_author !~ /\A[A-Z][A-Z0-9]*\z/;
  }

  method run {
    @authors = ();
    @urls = ();
    @problems = ();
    $branch_cache->begin_run;
    if ($run_gather) {
      $self->gather_data;
    } else {
      $self->load_data;
    }

    $self->build_site if $run_build;
  }

  method gather_data {
 
    say "Gathering...";

    my @registrations;
    my %seen;
    my @files;
    if (defined $selected_author) {
      my $file = path($global_cfg->{author_dir}, "$selected_author.json");
      die "No registration for author $selected_author at $file\n" unless $file->is_file;
      @files = ($file);
    } else {
      @files = sort { "$a" cmp "$b" } path($global_cfg->{author_dir})->children(qr/\.json\z/);
    }
    for my $file (@files) {
      my $cfg = normalize_author(read_json_file($file), $file);
      die "Author identifier mismatch in $file\n"
        if defined($selected_author) && $cfg->{author}{cpan} ne $selected_author;
      die "Duplicate author.cpan $cfg->{author}{cpan} in $file\n" if $seen{$cfg->{author}{cpan}}++;
      push @registrations, [$file, $cfg];
    }
    for my $registration (@registrations) {
      push @authors, $self->do_author(@$registration);
      push @urls, "https://$global_cfg->{domain}/$authors[-1]{author}{cpan}/";
    }

    $branch_cache->save;
  }

  method do_author ($file, $cfg = undef) {
    $cfg //= normalize_author(read_json_file($file), $file);

    my $id = $cfg->{author}{cpan} // '';
    die "Invalid CPAN identifier in $file\n" unless $id =~ /\A[A-Z][A-Z0-9]*\z/;
    my $attempts = $global_cfg->{fetch_attempts} // 3;
    my ($fresh, $error);
    for my $attempt (1 .. $attempts) {
      try {
        $fresh = $self->fetch_author($cfg);
      }
      catch ($exception) {
        $error = $exception;
      }
      last if $fresh;
      last if $attempt == $attempts || !retryable_fetch_error($error);
      warn "MetaCPAN fetch failed for $id (attempt $attempt/$attempts); retrying: $error";
      $self->wait_before_retry($attempt);
    }

    if ($fresh) {
      my $snapshot = $self->snapshot_path($id);
      $snapshot->parent->mkpath;
      $snapshot->spew_utf8($json->encode($fresh));
      return $fresh;
    }

    chomp $error;
    my $snapshot = $self->snapshot_path($id);
    my ($cached, $cache_error);
    try { $cached = $self->read_snapshot($snapshot, $id) }
    catch ($exception) { $cache_error = $exception }
    unless ($cached) {
      die "MetaCPAN fetch failed for $id: $error\n"
        . "No usable author snapshot at $snapshot: $cache_error";
    }
    warn "MetaCPAN fetch failed for $id: $error\n"
      . "Using cached snapshot $snapshot (gathered "
      . ($cached->{gathered_at} // 'at an unknown time') . ").\n";
    $cached->{fetch_warning} = 'Release metadata could not be refreshed; showing cached data.';
    push @problems, { service => 'MetaCPAN', subject => $id,
      message => $cached->{fetch_warning}, gathered_at => $cached->{gathered_at} };
    return $cached;
  }

  method fetch_author ($cfg) {
    # Do not expose partial pages or replace a snapshot if iteration fails.
    my $fresh = $json->decode($json->encode($cfg));
    my $author = $mcpan->author($cfg->{author}{cpan});
    $fresh->{author}{name} = $author->name;
    my $gravatar = $author->gravatar_url;
    if ($gravatar && $gravatar =~ m{\Ahttps://}) {
      $fresh->{author}{gravatar} = $gravatar;
    }
    my @modules;
    my $releases = $author->releases;
    while (my $release = $releases->next) {
      push @modules, $self->module_from_release($release);
    }
    $fresh->{modules} = [sort { $a->{name} cmp $b->{name} } @modules];
    $fresh->{gathered_at} = strftime('%Y-%m-%dT%H:%M:%SZ', gmtime);
    delete $fresh->{fetch_warning};
    return normalize_author($fresh, "author $cfg->{author}{cpan}");
  }

  sub retryable_fetch_error ($error) {
    return 0 unless defined $error;
    # MetaCPAN::Client drops the status code and wraps the HTTP reason in a URL
    # and a Perl callsite. Neither is evidence that an error is transient.
    $error =~ s/\AFailed to fetch '[^']*':\s*//;
    $error =~ s/\s+at\s+\S+\s+line\s+\d+.*\z//s;
    if ($error =~ /\b(?:HTTP(?:\/\d(?:\.\d)?)?\s+|status[ :=]+)(4\d\d)\b/i) {
      return $1 == 408 || $1 == 429;
    }
    return 0 if $error =~ /certificate (?:verify failed|verification)|invalid certificate/i;
    return $error =~ /\b(?:HTTP(?:\/\d(?:\.\d)?)?\s+|status[ :=]+)5\d\d\b|timed?\s*out|timeout|connection|network|temporary|could not connect|could not resolve|failed to connect|too many requests|internal server error|bad gateway|service unavailable|gateway timeout|name or service not known/i;
  }

  method wait_before_retry ($attempt) {
    my $delay = ($global_cfg->{retry_delay} // 1) * 2 ** ($attempt - 1);
    Time::HiRes::sleep($delay > 10 ? 10 : $delay);
  }

  method snapshot_path ($id) {
    return path($global_cfg->{data_dir} // 'authors/data', $id, 'data.json');
  }

  method read_snapshot ($file, $id) {
    my $data = read_json_file($file);
    # Apply current display settings without requiring another metadata fetch.
    my $registration = path($global_cfg->{author_dir}, "$id.json");
    if ($registration->is_file && ref($data) eq 'HASH' && ref($data->{author}) eq 'HASH') {
      my $cfg = normalize_author(read_json_file($registration), $registration);
      die "Author identifier mismatch in $registration\n" unless $cfg->{author}{cpan} eq $id;
      $data->{author}{github} = $cfg->{author}{github};
      $data->{$_} = $cfg->{$_} for qw(ci distribution_ci sort);
    }
    normalize_author($data, $file);
    die "Invalid author snapshot in $file\n"
      unless ref($data) eq 'HASH' && ref($data->{author}) eq 'HASH'
        && ($data->{author}{cpan} // '') eq $id && ref($data->{modules}) eq 'ARRAY'
        && !grep { ref($_) ne 'HASH' } @{ $data->{modules} };
    return $data;
  }

  method module_from_release {
    my ($rel) = @_;

    my $mod;
    $mod->{name} = $rel->name;
    $mod->{dist} = $rel->distribution;
    $mod->{ver}  = $rel->version;
    $mod->{auth} = $rel->author;
    $mod->{date} = (split /T/, $rel->date)[0];
    $mod->{bugtracker} = '';
    $mod->{uses_rt} = $JSON::false;

    # Get the repo link.
    # 1. It should be in the "web" key
    # 2. Otherwise, check the "url" key
    $mod->{repo} = $rel->resources->{repository}{web}
      // $rel->resources->{repository}{url};

    if ($rel->resources->{bugtracker}{web}) {
      $mod->{bugtracker} = resource_url($rel->resources->{bugtracker}{web}) // '';
      $mod->{uses_rt} = $mod->{bugtracker} =~ /rt\.cpan\.org/ ? $JSON::true : $JSON::false;
    }

    unless ($mod->{repo}) {
      return $mod;
    }

    $mod->{insecure_repo} = $mod->{repo} =~ m|^http:| ? $JSON::true : $JSON::false;
    $mod->{repo} =~ s[/+$][];

    if (my $github = github_repository($mod->{repo})) {
      $mod->{repo} = $github->{url};
      $mod->{repo_owner} = $github->{owner};
      $mod->{repo_name} = $github->{name};
      $mod->{repo_def_branch} = $self->get_repo_default_branch($mod);
      return $mod;
    }

    my $web_url = resource_url($mod->{repo});
    unless ($web_url) {
      warn "Unsupported repository URL for $mod->{name}; retaining distribution without a link.\n";
      push @problems, { service => 'Metadata', subject => $mod->{dist},
        message => 'Unsupported repository URL; distribution retained without a repository link.' };
      $mod->{repo} = undef;
      return $mod;
    }
    $mod->{repo} = $web_url;

    my $repo_uri = URI->new($mod->{repo});
    my $path = $repo_uri->path // '';
    $path =~ s|^/||;
    $path =~ s|/+\z||;
    $path =~ s|\.git\z||;
    @$mod{qw[repo_owner repo_name]} = split m|/|, $path, 3;
    # A valid alternative host is expected, rather than a processing error.
    warn "Non-canonical GitHub repository for $mod->{name} ($mod->{repo}); skipping service badges.\n"
      if lc($repo_uri->host) eq 'github.com';

    return $mod;
  }

  method get_repo_default_branch {
    my ($module) = @_;

    my $repo = github_repository($module->{repo}) or return '';
    return $branch_cache->get($repo->{owner}, $repo->{name});
  }

  method load_data {
    if (defined $selected_author) {
      push @authors, $self->read_snapshot($self->snapshot_path($selected_author), $selected_author);
      push @urls, "https://$global_cfg->{domain}/$selected_author/";
      return;
    }
    my $dir = path($global_cfg->{data_dir} // 'authors/data');
    for my $author_dir (sort { "$a" cmp "$b" } $dir->children) {
      next unless $author_dir->is_dir && $author_dir->child('data.json')->is_file;
      push @authors, $self->read_snapshot($author_dir->child('data.json'), $author_dir->basename);
      push @urls, "https://$global_cfg->{domain}/$authors[-1]{author}{cpan}/";
    }
  }

  method build_site {
    say "Building...";
    path($global_cfg->{output_dir})->mkpath;

    $tt = Template->new({
      ENCODING     => 'utf8',
      INCLUDE_PATH => $global_cfg->{input_dir},
      OUTPUT_PATH  => $global_cfg->{output_dir},
      WRAPPER      => $global_cfg->{wrapper},
      VARIABLES    => {
        analytics    => $global_cfg->{analytics},
        menu         => $global_cfg->{menu},
        domain       => $global_cfg->{domain},
        badges       => Dashboard::BadgeMaker->new,
      },
    });

    $self->make_static_pages;
    $self->make_author_pages;
    $self->make_other_pages;
    $self->make_sitemap;
  }

  method make_static_pages {

    find {
      wanted => sub {
        return unless -f;
        my $file = $_;
        my $rel = path($file)->relative($global_cfg->{static_dir});
        my $out = path($global_cfg->{output_dir}, $rel);
        $out->parent->mkpath;
        path($file)->copy($out);
      },
      no_chdir => 1,
    }, $global_cfg->{static_dir};
  }

  method make_author_pages {
    for (@authors) {
      $tt->process(
        $global_cfg->{author_template},
        $_,
        "$_->{author}{cpan}/index.html",
        { binmode => ':utf8' },
      ) or die $tt->error;

      path($global_cfg->{output_dir}, $_->{author}{cpan}, 'data.json')
        ->spew_utf8($json->encode($_));
    }

    $tt->process(
      $global_cfg->{index_template},
      { authors => \@authors },
      'index.html',
      { binmode => ':utf8' },
    ) or die $tt->error;
    push @urls, "https://$global_cfg->{domain}/";
  }

  method make_other_pages {
    my $report = {
      generated_at => strftime('%Y-%m-%dT%H:%M:%SZ', gmtime),
      mode => $run_gather ? 'gather-and-build' : 'cached-build',
      author_count => scalar @authors,
      problems => [@problems, @{ $branch_cache->problems }],
    };
    # Rendering can stringify numeric scalars; preserve the JSON value types.
    my $report_json = $json->encode($report);
    for (@{ $global_cfg->{page_templates} }) {
      $tt->process(
        "$_.tt",
        { name => ucfirst $_, report => $report },
        "$_/index.html",
        { binmode => ':utf8' },
      ) or die $tt->error;
      path($global_cfg->{output_dir}, 'status', 'data.json')->spew_utf8($report_json)
        if $_ eq 'status';
      push @urls, "https://$global_cfg->{domain}/$_/";
    }
  }

  method make_sitemap {
    @urls = sort @urls;

    $tt->process(
      'sitemap.tt',
      { urls => \@urls},
      'sitemap.xml',
      { binmode => ':utf8' },
    ) or die $tt->error;
  }

  sub valid_repo {
    my ($repo_uri) = @_;

    return unless defined $repo_uri;

    # Default branch lookup only works for GitHub repos
    return !!github_repository($repo_uri);
  }
}

1;
