use v5.36;
use Feature::Compat::Class;

no if $^V >= v5.38, warnings => 'experimental::class';

class Dashboard::App {
  use strict;
  use warnings;

  use Dashboard::BadgeMaker;

  use JSON;
  use Path::Tiny;
  use Template;
  use MetaCPAN::Client;
  use URI;
  use FindBin '$RealBin';
  use File::Find;

  field $mcpan = MetaCPAN::Client->new;
  field $json = JSON->new->pretty->canonical->utf8;
  field $global_cfg = $json->decode(path('dashboard.json')->slurp_utf8);
  field $tt;
  field @authors;
  field @all_authors;
  field @urls;
  field $run_gather :param(gather) = 1;
  field $run_build :param(build) = 1;
  field $repo_def_branch;
  field $branch_cache_file = 'repo_def_branch.json';

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

    # This should be the initialiser expression for $repo_def_branch
    if (-f $branch_cache_file) {
      $repo_def_branch = $json->decode(path($branch_cache_file)->slurp_utf8);
    } else {
      $repo_def_branch = {};
    }

    for (glob "$RealBin/../authors/*.json") {
      push @authors, $self->do_author($_);
      push @urls, "https://$global_cfg->{domain}/$authors[-1]{author}{cpan}/";
    }

    path($branch_cache_file)->spew_utf8($json->encode($repo_def_branch));
  }

  method do_author {
    my ($file) = @_;

    my $cfg = $json->decode(path($file)->slurp_utf8);

    $cfg->{modules} = [];

    my $mcpan_author = $mcpan->author($cfg->{author}{cpan});
    my $releases     = $mcpan_author->releases;

    $cfg->{author}{gravatar} = $mcpan_author->gravatar_url;
    $cfg->{author}{name}     = $mcpan_author->name;

    while ( my $rel = $releases->next ) {
      my $mod;
      $mod->{name} = $rel->name;
      $mod->{dist} = $rel->distribution;
      $mod->{ver}  = $rel->version;
      $mod->{auth} = $rel->author;
      $mod->{date} = (split /T/, $rel->date)[0];
      # Get the repo link.
      # 1. It should be in the "web" key
      # 2. Otherwise, check the "url" key
      $mod->{repo} = $rel->resources->{repository}{web}
        // $rel->resources->{repository}{url};

       if ($rel->resources->{bugtracker}{web}) {
        $mod->{bugtracker} = $rel->resources->{bugtracker}{web};
        $mod->{uses_rt} = $mod->{bugtracker} =~ /rt.cpan.org/;
      }

      unless ($mod->{repo}) {
        warn "No repo for $mod->{name}\n";
        next;
      }

      unless (valid_repo($mod->{repo})) {
        warn "Skipping $mod->{repo}\n";
        next;
      }

      $mod->{repo} =~ s[/$][];
      # We need the repo's name. Try to extract it from the URL
      my $repo_uri = URI->new($mod->{repo});
      if ($mod->{repo} =~ /^(http|git)/) {
        my $path = $repo_uri->path;
        $path =~ s|^/||; # Remove leading slash
        $path =~ s|\.git$||; # Remove trailing .git
        @$mod{qw[repo_owner repo_name]} = split m|/|, $path, 2;
        $mod->{repo_name} =~ s/\.git$// if $mod->{repo} =~ /^git/;
        $mod->{repo_def_branch} = $self->get_repo_default_branch($mod);
        chomp($mod->{repo_def_branch});
      } else {
        warn "Strange repo for $mod->{name} ($mod->{repo}). Skipping.\n";
        next;
      }
      $mod->{insecure_repo} = $mod->{repo} =~ m|^http:|;
      push @{ $cfg->{modules} }, $mod;
    }

    $cfg->{modules} = [ sort { $a->{name} cmp $b->{name} } @{$cfg->{modules}} ];

    $cfg->{sort} //= {};
    $cfg->{sort}{column} //= 0;
    $cfg->{sort}{column} = 2 if 'date' eq lc $cfg->{sort}{column};
    $cfg->{sort}{direction} //= 'asc';

    path("docs/$cfg->{author}{cpan}")->mkdir;
    path("docs/$cfg->{author}{cpan}/data.json")->spew_utf8($json->encode($cfg));

     return $cfg;
  }

  method get_repo_default_branch {
    my ($module) = @_;

    my $path = "$module->{repo_owner}/$module->{repo_name}";

    unless (exists $repo_def_branch->{$module->{repo_owner}} and
      exists $repo_def_branch->{$module->{repo_owner}}{$module->{repo_name}}) {
        $repo_def_branch->{$module->{repo_owner}}{$module->{repo_name}}
          = `gh repo view $path --json defaultBranchRef -q .defaultBranchRef.name`;
        chomp $repo_def_branch->{$module->{repo_owner}}{$module->{repo_name}};
    }

    return $repo_def_branch->{$module->{repo_owner}}{$module->{repo_name}};
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

      path("authors/data/$_->{author}{cpan}")->mkdir;
      path("authors/data/$_->{author}{cpan}/data.json")
        ->copy("docs/$_->{author}{cpan}/data.json");
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

    # Currently we only support Github repos
    return $repo_uri =~ m|github\.com/|;
  }
}

1;
