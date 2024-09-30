use 5.36.0;
use Feature::Compat::Class;

no if $^V >= v5.38, warnings => 'experimental::class';

class Dashboard::Author {
  use Dashboard::Distribution;
  use Path::Tiny;

  field $name :reader :param;
  field $cpan_name :reader :param;
  field $github_name :reader :param;
  field $gravatar_url :reader :param;
  field $distributions :reader :param = [];
  field $sort :reader :param = {};
  field $ci :reader :param;

  method new_from_file :common {
    my ($file, $mcpan, $json) = @_;

    my $data = $json->decode(path($file)->slurp_utf8);

    my $mcpan_author = $mcpan->author($data->{author}{cpan});

    my $sort = $data->{sort} // {};
    $sort->{column} //= 0;
    $sort->{column} = 2 if 'date' eq lc $sort->{column};
    $sort->{direction} //= 'asc';

    my @distributions;

    if ($data->{distributions}) {
      @distributions = map { Dashboard::Distribution->new(%$_) } @{ $data->{distributions} };
    } else {
      my $releases = $mcpan_author->releases;

      while ( my $rel = $releases->next ) {
        push @distributions, Dashboard::Distribution->new_from_release($rel);
      }

      @distributions = sort { $a->name cmp $b->name } @distributions;
    }

    my @ci_systems = qw[gh_actions cirrus appveyor travis travis_com coveralls codecov];
    my $ci;


    $ci->{"use_$_"} = ($data->{ci}{"use_$_"} // 0) for @ci_systems;

    $ci->{gh_workflow_names} = ($data->{ci}{gh_workflow_names} // []);

    my $self = $class->new(
      name         => $mcpan_author->name,
      gravatar_url => $mcpan_author->gravatar_url,
      cpan_name    => $data->{author}{cpan},
      github_name  => $data->{author}{github},
      sort         => $sort,
      distributions => \@distributions,
      ci          => $ci,
    );

    return $self;
  }

  method new_from_data :common {
    my ($data) = @_;

    $data->{distributions} = [
      map { Dashboard::Distribution->new_from_data($_) } @{ $data->{distributions} } 
    ];

    return $class->new(%$data);
  }

  method dump {
    my $ci;

    for (keys %{ $self->ci }) {
      if (/^use_/) {
        $ci->{$_} = $self->ci->{$_} ? $JSON::true : $JSON::false;
      } else {
        $ci->{$_} = $self->ci->{$_};
      }
    }

    my $data = {
      author => {
        cpan   => $self->cpan_name,
        github => $self->github_name,
        gravatar => $self->gravatar_url,
        name => $self->name,
      },
      sort => $self->sort,
      distributions => [ map { $_->dump } @{ $self->distributions } ],
      ci => $ci,
    };

    return $data;
  }

  method as_json {
    return JSON->new->pretty->encode($self->dump)
  }

  method write_data_file {
    path('docs/' . $cpan_name . '/data.json')->spew_utf8($self->as_json);
  }
}
