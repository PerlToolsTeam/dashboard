# Repository and configuration classes

Issue #127 introduces `VCS::Repository` and turns `Dashboard::Config` into a
native Perl class. Both use Perl's `class`, `field`, and `method` syntax and
require Perl 5.40 or later. Repository's namespace is provisional while its API
is established inside dashboard.

## Repository API

```perl
use VCS::Repository;

my $repo = VCS::Repository->new(
    host => 'GitHub', owner => 'example', name => 'project',
);
$repo->url;                  # https://github.com/example/project
$repo->url(style => 'web');  # same browser URL
$repo->url(style => 'http'); # https://github.com/example/project.git
$repo->url(style => 'ssh');  # git@github.com:example/project.git

my $parsed = VCS::Repository->from_url(
    'https://gitlab.com/group/subgroup/project.git',
);
$parsed->owner;             # group/subgroup
$parsed->name;              # project
$parsed->raw_url;           # exact input, including .git
```

Constructor fields have readers: `name`, `type`, `host`, `hostname`, `owner`,
`raw_url`, and `path`. `type` is `Git`, `Subversion`, or undefined; `svn` is
accepted and normalized to `Subversion`. `host` identifies a hosting service,
such as `GitHub`, whereas `hostname` is its actual domain. `path` is the relative
repository path constructed from owner/name or parsed from a recognized host.
`owner` can contain nested GitLab namespaces. Readers have no corresponding
setters.

The constructor accepts explicit fields, `raw_url`, or both. When both are
supplied, contradictory parsed identity fields are rejected. Explicit fields
require a name; a URL may produce a partial object with no name. GitHub,
GitLab, and Bitbucket have known URL layouts and imply Git. `is_git`,
`is_subversion`, `is_github`, `is_gitlab`, and `is_bitbucket` report the VCS or
service. `is_complete` reports whether enough identity is available to construct
URLs. Being on github.com alone is insufficient to establish repository identity.

For a self-hosted GitLab instance, supply `host => 'GitLab'` when parsing its
URL. A hostname by itself does not imply that it runs GitLab. Unknown web hosts
retain `raw_url` and `hostname` without guessing owner, name, or VCS type. Callers
can supply `type => 'Subversion'` for a web URL whose VCS cannot be inferred.
`svn://` and `svn+ssh://` URLs identify Subversion, but their checkout paths do
not establish repository roots and remain partial unless identity is supplied.

For partial objects, `url(style => 'web')` returns the original HTTP(S) URL, if
available; clone styles return undefined. A non-web transport never invents a
browser link. Explicit Subversion fields construct HTTPS URLs without `.git` and
`svn+ssh://hostname/path` for SSH. Unknown output styles or option names raise
errors. Fields supplied without a raw URL describe the endpoint the caller
intends; URL construction does not probe whether that endpoint exists.

`from_url` is a tolerant factory for untrusted metadata: unsafe or malformed
inputs return undefined. `new` reports invalid or contradictory fields as
exceptions. Control characters, unsupported schemes, and embedded passwords are
rejected. HTTP credentials are rejected; known Git SSH URLs accept the `git`
username, and Subversion SSH accepts usernames without passwords. Recognized
service subpages, queries, fragments, and nonstandard ports do not become complete
repository identities. HTTP inputs for recognized repositories normalize to
HTTPS; `http` means an HTTPS clone URL, not unencrypted HTTP.

The class does not access the network, invoke a command, or read dashboard files.

## Dashboard integration

`Dashboard::GitHub` performs explicit default-branch lookup:

```perl
my $github = Dashboard::GitHub->new;
my $branch = $github->lookup_default_branch($repo);
```

The adapter accepts complete public GitHub identities and invokes `gh` using
separate literal arguments. It relies on the caller's existing GitHub CLI
authentication. It does not support GitHub Enterprise instances yet.
`Dashboard::BranchCache` owns persistence and fallback behavior; it can receive
an adapter through its `github` constructor parameter. Lookup failures retain
valid cached branches and appear in build diagnostics.

`Dashboard::URL::resource_url` validates generic HTTP(S) display links, including
bugtrackers. That dashboard helper is separate from the candidate VCS library.
Unfamiliar repositories remain visible in the dashboard with their usable web
links; GitHub badges still require a complete GitHub identity. Gathering retains
an optional normalized `repo_type` from supported metadata or an inferred type.
Unknown-host owner/name fields are no longer guessed from arbitrary URL segments.

## Configuration API

```perl
use Dashboard::Config;

my $global = Dashboard::Config->new(file => 'dashboard.json', kind => 'global');
my $registration = Dashboard::Config->new(file => 'authors/EXAMPLE.json');
my $in_memory = Dashboard::Config->new(
    file => 'generated registration',
    data => { author => { cpan => 'EXAMPLE' } },
);
my $settings = $registration->effective_ci('Example-Distribution');
my $normalized = $registration->data;
```

Each instance owns its source (`file`), `kind`, and normalized `data`. `kind`
defaults to `author`; only `author` and `global` are supported. Constructors
load and validate JSON unless supplied in-memory data. The source label is
included in validation errors; in-memory configurations default to `<memory>`.
`data` returns the normalized hash used by the existing rendering pipeline.
The hash remains mutable for the application; readers do not imply deep
immutability. `effective_ci` returns merged settings for an author configuration.

`Dashboard::Config->read_data($file)` reads JSON without configuration validation.
Snapshot loading uses it to apply the current author registration *before*
constructing a validated configuration. It is not a bypass for application
configuration loading. Path overlap checks, author/CI/sort validation, and
preflight checks retain their previous behavior.

## CPAN extraction assessment

Recommendation: establish this API in dashboard first, then extract the local
identity/URL class after real repository fixtures have exercised its boundaries.
The MetaCPAN module lookup for `VCS::Repository` returned HTTP 404 on 11 October
2026; this is a preliminary namespace check, not a reservation. Confirm naming
and possible overlap with existing repository libraries before publication.

An eventual distribution needs:

- `lib/VCS/Repository.pm`, its API documentation, and standalone repository tests;
- a `cpanfile` declaring Perl 5.40 and URI, with Test::More for tests;
- distribution metadata, versioning, licence, Changes, and release tooling;
- CI on the supported Perl versions and tests for additional real URL layouts.

The current `t/vcs-repository.t` exercises the candidate module independently of
dashboard classes, data, credentials, and external services. Generic URL
validation, configuration, GitHub CLI authentication/lookup, branch caching, and
badge rendering stay in dashboard. No GitHub CLI dependency belongs in the first
CPAN distribution. If provider APIs are added later, make them explicit adapters
with testable transports rather than automatic constructor side effects.

After extraction, dashboard would declare the distribution as a dependency,
remove its bundled copy and standalone tests, and keep its integration tests.
No deployment, snapshot-format migration, or CPAN publication is part of this
initial refactor.
