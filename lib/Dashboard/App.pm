# 5.40 because we use :reader
use v5.40;

use feature 'class';
no if $^V >= v5.40, warnings => 'experimental::class';

class Dashboard::App {
  our $VERSION = '1.0.0';

  use Dashboard::BadgeMaker;
  use Dashboard::BranchCache;
  use Dashboard::Repository qw(github_repository);

  use JSON;
  use Path::Tiny;
  use Template;
  use MetaCPAN::Client;
  use HTTP::Tiny;
  use URI;
  use FindBin '$RealBin';
  use File::Find;

  # :reader only exists for the tests
  field $mcpan :reader = MetaCPAN::Client->new(
    ua => HTTP::Tiny->new(agent => "CPAN Dashboard/$VERSION")
  );
  field $json = JSON->new->pretty->canonical->utf8;
  field $global_cfg = $json->decode(path('dashboard.json')->slurp_utf8);
  field $tt;
  field @authors;
  field @all_authors;
  field @urls;
  field $run_gather :param(gather) = 1;
  field $run_build :param(build) = 1;
  field $branch_cache = Dashboard::BranchCache->new;

  method run {
    if ($run_gather) {
      $self->gather_data;
    } else {
      $self->load_data;
    }

    $self->build_site if $run_build;
  }

  method gather_data {
 
    say "Gathering...";

    for (glob "$RealBin/../authors/*.json") {
      push @authors, $self->do_author($_);
      push @urls, "https://$global_cfg->{domain}/$authors[-1]{author}{cpan}/";
    }

    $branch_cache->save;
  }

  method do_author {
    my ($file) = @_;

    my $cfg = $json->decode(path($file)->slurp_utf8);

    $cfg->{modules} = [];

    my @modules;

    try {
      my $mcpan_author = $mcpan->author($cfg->{author}{cpan});
      my $releases     = $mcpan_author->releases;

      my $gravatar = $mcpan_author->gravatar_url;
      if ($gravatar and $gravatar =~ m[^https:]) {
        $cfg->{author}{gravatar} = $gravatar;
      }
      $cfg->{author}{name} = $mcpan_author->name;

      while ( my $rel = $releases->next ) {
        push @modules, $self->module_from_release($rel);
      }
    }
    catch ($e) {
      chomp $e;
      my $data_file = path("docs/$cfg->{author}{cpan}/data.json");

      if ($data_file->is_file) {
        warn "MetaCPAN fetch failed for $cfg->{author}{cpan}: $e\n"
           . "Re-using previously generated data from $data_file.\n";
        return $json->decode($data_file->slurp_utf8);
      }

      die "MetaCPAN fetch failed for $cfg->{author}{cpan} "
        . "and no cached data is available: $e\n";
    }

    $cfg->{modules} = [ sort { $a->{name} cmp $b->{name} } @modules ];

    $cfg->{sort} //= {};
    $cfg->{sort}{column} //= 0;
    $cfg->{sort}{column} = 2 if 'date' eq lc $cfg->{sort}{column};
    $cfg->{sort}{direction} //= 'asc';

    path("docs/$cfg->{author}{cpan}")->mkdir;
    path("docs/$cfg->{author}{cpan}/data.json")->spew_utf8($json->encode($cfg));

    return $cfg;
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
    $mod->{uses_rt} = 0;

    # Get the repo link.
    # 1. It should be in the "web" key
    # 2. Otherwise, check the "url" key
    $mod->{repo} = $rel->resources->{repository}{web}
      // $rel->resources->{repository}{url};

    if ($rel->resources->{bugtracker}{web}) {
      $mod->{bugtracker} = $rel->resources->{bugtracker}{web};
      $mod->{uses_rt} = $mod->{bugtracker} =~ /rt\.cpan\.org/;
    }

    unless ($mod->{repo}) {
      return $mod;
    }

    $mod->{insecure_repo} = $mod->{repo} =~ m|^http:|;
    $mod->{repo} =~ s[/+$][];

    if (my $github = github_repository($mod->{repo})) {
      $mod->{repo} = $github->{url};
      $mod->{repo_owner} = $github->{owner};
      $mod->{repo_name} = $github->{name};
      $mod->{repo_def_branch} = $self->get_repo_default_branch($mod);
      return $mod;
    }

    # We need the repo's name. Try to extract it from the URL.
    if ($mod->{repo} =~ /^(http|git)/) {
      my $repo_uri = URI->new($mod->{repo});
      my $path = $repo_uri->path // '';
      $path =~ s|^/||;     # Remove leading slash
      $path =~ s|\.git$||; # Remove trailing .git
      $path =~ s|/+$||;    # Remove trailin slashes

      @$mod{qw[repo_owner repo_name]} = split m|/|, $path, 3;

      if (defined $mod->{repo_owner} and defined $mod->{repo_name}) {
        $mod->{repo_name} =~ s|\.git$||;

        warn "Unsupported repository for GitHub badges: $mod->{name} ($mod->{repo}).\n";
      } else {
        warn "Strange repo for $mod->{name} ($mod->{repo}).\n";
      }
    } else {
      warn "Strange repo for $mod->{name} ($mod->{repo}).\n";
    }

    return $mod;
  }

  method get_repo_default_branch {
    my ($module) = @_;

    my $repo = github_repository($module->{repo}) or return '';
    return $branch_cache->get($repo->{owner}, $repo->{name});
  }

  method load_data {
    for (glob "$RealBin/../authors/data/*/data.json") {
      push @authors, $json->decode(path($_)->slurp_utf8);
      push @urls, "https://$global_cfg->{domain}/$authors[-1]{author}{cpan}/";
    }
  }

  method build_site {
    say "Building...";

    $tt = Template->new({
      ENCODING     => 'utf8',
      INCLUDE_PATH => $global_cfg->{input_dir},
      OUTPUT_PATH  => $global_cfg->{output_dir},
      WRAPPER      => $global_cfg->{wrapper},
      VARIABLES    => {
        analytics    => $global_cfg->{analytics},
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
        my $rel = path($file)->relative('.');
        $rel =~ s|$global_cfg->{static_dir}/||g;
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

      if (-f "authors/data/$_->{author}{cpan}/data.json") {
        path("docs/$_->{author}{cpan}")->mkdir;
        path("authors/data/$_->{author}{cpan}/data.json")
          ->copy("docs/$_->{author}{cpan}/data.json");
      }
    }

    $tt->process(
      $global_cfg->{index_template},
      { authors => \@authors },
      'index.html',
      { binmode => ':utf8' },
    );
    push @urls, "https://$global_cfg->{domain}/";
  }

  method make_other_pages {
    for (@{ $global_cfg->{page_templates} }) {
      $tt->process(
        "$_.tt",
        { name => ucfirst $_ },
        "$_/index.html",
        { binmode => ':utf8' },
      );
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
    );
  }

  sub valid_repo {
    my ($repo_uri) = @_;

    return unless defined $repo_uri;

    # Default branch lookup only works for GitHub repos
    return !!github_repository($repo_uri);
  }
}

1;
