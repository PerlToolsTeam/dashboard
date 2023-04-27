use v5.26;
use Object::Pad ':experimental(init_expr)';

class Dashboard::App {
  use strict;
  use warnings;

  use JSON;
  use Path::Tiny;
  use Template;
  use MetaCPAN::Client;
  use URI;
  use FindBin '$RealBin';

  my $json = JSON->new->pretty->utf8;

  field $mcpan { MetaCPAN::Client->new };
  field $global_cfg { $json->decode(path('dashboard.json')->slurp_utf8) };
  field $tt;
  field @authors;
  field @all_authors;
  field @urls;
  field $run_gather :param(gather) = 1;
  field $run_build :param(build) = 1;

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

    for (glob "$RealBin/authors/*.json") {
      push @authors, $self->do_author($_);
      push @urls, "https://$global_cfg->{domain}/$authors[-1]{author}{cpan}/";
    }
  }

  method do_author {
    my ($file) = @_;

    my $cfg = decode_json(path($file)->slurp_utf8);

    $cfg->{modules} = [];

    my $mcpan_author = $mcpan->author($cfg->{author}{cpan});
    my $releases     = $mcpan_author->releases;

    $cfg->{author}{gravatar} = $mcpan_author->gravatar_url;
    $cfg->{author}{name}     = $mcpan_author->name;

    while ( my $rel = $releases->next ) {
      my $mod;
      $mod->{name} = $rel->name;
      $mod->{dist} = $rel->distribution;
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
        $mod->{repo_def_branch} = `gh repo view $path --json defaultBranchRef -q .defaultBranchRef.name`;
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

    path("docs/$cfg->{author}{cpan}/data.json")->spew_utf8($json->encode($cfg));

     return $cfg;
  }

  method load_data {
    for (glob "$RealBin/docs/*/data.json") {
      push @authors, decode_json(path($_)->slurp_utf8);
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
        linked_badge => {
          cpan       => \&cpan_badge_link,
          gh         => \&gh_badge_link,
          travis     => \&travis_badge_link,
          travis_com => \&travis_com_badge_link,
          cirrus     => \&cirrus_badge_link,
          appveyor   => \&appveyor_badge_link,
          coveralls  => \&coveralls_badge_link,
          codecov    => \&codecov_badge_link,
          kritika    => \&kritika_badge_link,
        },
      },
    });

    for (@authors) {
      $tt->process(
        $global_cfg->{author_template},
        $_,
        "$_->{author}{cpan}/index.html",
        { binmode => ':utf8' },
      ) or die $tt->error;
    }

    $tt->process(
      $global_cfg->{index_template},
      { authors => \@authors },
      'index.html',
      { binmode => ':utf8' },
    );
    push @urls, "https://$global_cfg->{domain}/";

    for (@{ $global_cfg->{page_templates} }) {
      $tt->process(
        "$_.tt",
        { name => ucfirst $_ },
        "$_/index.html",
        { binmode => ':utf8' },
      );
      push @urls, "https://$global_cfg->{domain}/$_/";
    }

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

  sub cpan_badge_link {
    my ($module) = @_;

    return badge_link(
      "https://metacpan.org/release/$module->{dist}",
      "https://img.shields.io/cpan/v/$module->{dist}.svg",
      "CPAN version for $module->{dist}",
    );
  }

  sub cirrus_badge_link {
    my ($task, $module) = @_;

    return badge_link(
      "https://cirrus-ci.com/github/$module->{repo_owner}/$module->{repo_name}",
      "https://api.cirrus-ci.com/github/$module->{repo_owner}/$module->{repo_name}.svg?task=$task",
      "Cirrus task $task",
    );
  }

  sub gh_badge_link {
    my ($workflow, $module) = @_;

    return badge_link(
      "https://github.com/$module->{repo_owner}/$module->{repo_name}/actions?query=workflow%3A$workflow",
      "https://github.com/$module->{repo_owner}/$module->{repo_name}/workflows/$workflow/badge.svg",
      "GH Action $workflow",
    );
  }

  sub appveyor_badge_link {
    my ($module) = @_;

    return badge_link(
      "https://ci.appveyor.com/project/$module->{repo_owner}/$module->{repo_name}",
      "https://ci.appveyor.com/api/projects/status/github/$module->{repo_owner}/$module->{repo_name}?svg=true&passingText=Windows%20-%20OK&pendingText=Windows%20-%20%3F%3F%3F&failingText=Windows%20-%20broken",
      "Build status for $module->{dist}",
    );
  }

  sub travis_badge_link {
    my ($module) = @_;

    return badge_link(
      "https://travis-ci.org/$module->{repo_owner}/$module->{repo_name}?branch=$module->{repo_def_branch}",
      "https://travis-ci.org/$module->{repo_owner}/$module->{repo_name}.svg?branch=$module->{repo_def_branch}",
      "Build status for $module->{dist}",
    );
  }

  sub travis_com_badge_link {
      my ($module) = @_;

      return travis_badge_link($module) =~ s/travis-ci\.org/travis-ci.com/gr;
  }

  sub coveralls_badge_link {
    my ($module, $author) = @_;

    return badge_link(
      "https://coveralls.io/github/$module->{repo_owner}/$module->{repo_name}?branch=$module->{repo_def_branch}",
      "https://coveralls.io/repos/$module->{repo_owner}/$module->{repo_name}/badge.svg?branch=$module->{repo_def_branch}&service=github",
      "Test coverage for $module->{dist}",
    );
  }

  sub codecov_badge_link {
    my ($module) = @_;

    return badge_link(
      "https://codecov.io/gh/$module->{repo_owner}/$module->{repo_name}",
      "https://codecov.io/gh/$module->{repo_owner}/$module->{repo_name}/branch/$module->{repo_def_branch}/graph/badge.svg",
      "Test coverage for $module->{dist}",
    );
  }

  sub kritika_badge_link {
    my ($module, $author) = @_;

    return badge_link(
      "https://kritika.io/users/$author->{github}/repos/$module->{repo_owner}+$module->{repo_name}/",
      "https://kritika.io/users/$author->{github}/repos/$module->{repo_owner}+$module->{repo_name}/heads/$module->{repo_def_branch}/status.svg",
      "Kritika grade for $module->{dist}",
    );
  }

  sub badge_link {
    my ($link_url, $img_url, $alt_text) = @_;

    return qq[<a href="$link_url"><img class="backup_picture" alt="$alt_text" src="$img_url"></a>];
  }

}

1;
