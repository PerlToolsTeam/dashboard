use 5.40.0;

use feature 'class';
no if $^V >= v5.38, warnings => 'experimental::class';

class Dashboard::Author {
  use Dashboard::Distribution;
  use Path::Tiny;
  use Dashboard::Config qw(normalize_author);

  field $name :reader :param;
  field $cpan_name :reader :param;
  field $github_name :reader :param;
  field $gravatar_url :reader :param = '/images/gravatar.png';
  field $distributions :reader :param = [];
  field $sort :reader :param = {};
  field $ci :reader :param;

  sub new_from_file {
    my ($class, $file, $mcpan, $json) = @_;

    my $data = normalize_author($json->decode(path($file)->slurp_utf8), $file);

    my $mcpan_author = $mcpan->author($data->{author}{cpan});

    my $sort = $data->{sort} // {};

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

    my $ci = $data->{ci};

    my $gravatar_url = $mcpan_author->gravatar_url;
    unless ($gravatar_url and $gravatar_url =~ m[^https:]) {
      undef $gravatar_url;
    }
    my $self = $class->new(
      name         => $mcpan_author->name,
      gravatar_url => $gravatar_url // '/images/gravatar.png',
      cpan_name    => $data->{author}{cpan},
      github_name  => $data->{author}{github},
      sort         => $sort,
      distributions => \@distributions,
      ci          => $ci,
    );

    return $self;
  }

  sub new_from_data {
    my ($class, $data) = @_;

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
    path('docs/' . $cpan_name)->mkdir;
    path('docs/' . $cpan_name . '/data.json')->spew_utf8($self->as_json);
  }
}

1;
