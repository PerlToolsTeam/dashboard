# Robustness session — 10 October 2026

Session window: 14:51–16:21 UTC (90 minutes).
Branch: `robustness-sprints-2026-10-10`.
The fourth sprint continues on `dashboard-ci-overrides-2026-10-10`, based on the
three robustness commits in draft PR #122.

## Sprint 1: repository lookup and branch-cache recovery

Addresses #119 and #118; establishes the offline test foundation for #121.

- Added shared hostname/path validation and normalized GitHub URLs.
- Removed shell interpolation from all tracked repository lookups.
- Preserved valid branch values on failed or empty refreshes and retried empty
  entries on later runs.
- Removed the alternate classes' dependency on the untracked experimental
  `github_repo.json`, including its mismatched fields and undeclared printer.
- Replaced live-service tests and stale assertions with deterministic fixtures.
- Added a deployment test gate and pinned the cache workflow to Perl 5.40.

Validation: `prove -Ilib t` passes 82 checks across five files. Coverage includes
misleading URLs, malformed cache keys, literal CLI arguments, failed and empty
lookups, atomic-write failure, refresh-script execution, and independence from
the stale experimental cache. Generated-site integration tests follow in the
snapshot sprint.

## Sprint 2: persistent snapshots and metadata recovery

Addresses #117 and #93; completes the generated-site coverage for #121.

- Gathering atomically updates `authors/data/AUTHOR/data.json`; building renders
  HTML and JSON from the same data and honors the configured output directory.
- Added bounded transient retries, HTTP timeouts, and last-known-good snapshot
  fallback that works without a pre-existing generated site.
- Failed/partial iteration never replaces a complete snapshot. Fallback pages
  show a warning and successful fetches record a UTC timestamp.
- Fixed Unicode JSON handling and surfaced additional-page/sitemap render errors.
- Added isolated integration tests using actual templates/assets and fixtures,
  including the real CLI build-only entry point.
- Added push/PR test coverage on Perl 5.40 and 5.42.

Validation: `prove -Ilib t` passes 132 checks across six files. The default suite
requires no network calls or credentials and does not change repository snapshots
or caches. Live-service retrieval and deployed browser rendering remain outside
this session's local checks.

## Sprint 3: configuration preflight and stable table ordering

Addresses #120 and #82.

- Added a shared validator for global paths, required templates, domain,
  request/retry limits, registrations, CI values, and sort settings.
- Validated every registration and duplicate author ID before fetching any
  author. Build-only snapshots receive the same author configuration checks.
- Prevented output paths from overlapping persistent data or source files,
  including traversal through nonexistent path components.
- Normalized legacy sort indexes to names and resolved indexes from header
  attributes in the browser, preserving ordering when columns move.
- Fixed top-level navigation menus and initialization on pages without tables.
- Added browser-script behavior checks to PR tests and the publication gate.

Validation: 277 Perl checks across seven files and three Node.js behavior checks
pass. Changed workflow YAML parses successfully. The first two sprint commits
also passed GitHub Actions on Perl 5.40 and 5.42 (draft PR #122).

## Sprint 4: per-distribution CI settings and reliable badge rendering

Addresses #5 and #102, with regression coverage for #31 and #115.

- Confirmed the workflow mismatch described in #102 through public GitHub API
  reads: Acme-Constructor-Pythonic has no workflows, while the other cited
  repository defines CI.
- Added validated `distribution_ci` overrides and explicit workflow filename
  support. Unspecified fields inherit author defaults; empty lists replace them.
- Applied current registration settings during cached builds without changing
  persistent metadata or fetching any external service.
- Disabled the nonexistent default workflow for the verified TOBYINK example.
- URL encoded workflow names/files, escaped badge attributes and repository links,
  and rejected executable protocols in repository/bugtracker links.
- Fixed fallback handling for badge errors that occur before document.ready and
  prevented retry loops when the fallback image itself is missing.
- Verified all rows and CPAN/CPANTS badges remain available for no-repo, GitLab,
  and Bitbucket distributions, with consistent table alignment.

Validation: 334 Perl checks across nine files and five JavaScript checks pass.
The real catalogue test uses the production templates with mixed repository
hosts, disabled services, alternate workflow filenames, and changed cached-build
settings. The original distribution-count discrepancy in #31 has not been
reproduced against current MetaCPAN data, so that issue remains an audit candidate.
