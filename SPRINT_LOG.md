# Robustness session — 10 October 2026

Session window: 14:51–16:21 UTC (90 minutes).
Branch: `robustness-sprints-2026-10-10`.
The fourth sprint continues on `dashboard-ci-overrides-2026-10-10`, based on the
three robustness commits in draft PR #122. Sprints 4 onward are in draft PR #123.

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

## Sprint 5: visible processing problems

Addresses #45.

- Added a navigable build-status page and machine-readable report with build time,
  build mode, author count, and recovered processing problems.
- Exposed metadata fallbacks, snapshot dates, failed branch lookups, and unsupported
  repository links using predefined public messages; raw errors stay in logs.
- Distinguished cached builds from successful metadata refreshes and linked to
  workflow logs for fatal failures that cannot update the published report.
- Reset lookup failure memoization between runs of a reused application, allowing
  later runs to retry without duplicating old problems.

Validation: 362 offline Perl checks across ten files and five JavaScript checks
pass. Coverage includes recovery reports, repeated runs, no-network cached builds,
escaped public fields, retained branches, and fatal failure preserving the previous
status report. External badge availability remains a browser concern.

## Sprint 6: single-author development runs

Addresses #47.

- Added `--author CPANID` for gather, cached build, and combined runs, without
  fetching or changing unselected author snapshots.
- Added `--config FILE` to make isolated development output easy to select.
- Preserved both-stage defaults when only an author or configuration is supplied;
  rejected unknown options and unexpected arguments instead of silently building.
- Documented partial indexes/sitemaps and recommended separate development output.

Validation: 391 offline Perl checks across eleven files and five JavaScript checks
pass. Selection tests cover missing/invalid IDs, identity mismatch, unchanged
unselected snapshots, unrelated invalid registrations, real CLI cached selection,
stage defaults, and help/error handling.

## Sprint 7: simpler author onboarding

Addresses #24 and documents the maintainer's existing policy in #103.

- Replaced the fork/clone checklist with GitHub's web-file editor flow and linked
  official instructions for automatically creating a fork and proposing a change.
- Added a browser form that prepares validated registration JSON and its filename,
  with optional services disabled by default and workflow-name validation.
- Retained instructions for contributors using the page without JavaScript.
- Added form behavior checks to PR and publication gates, plus a cross-language
  fixture validating the generated JSON with the production Perl validator.

Validation: 397 Perl checks across twelve files and twelve JavaScript checks pass.
Browser behavior covers minimal registration, optional services, escaping through
JSON serialization, invalid IDs/usernames, missing workflow names, and stale output.
An additional headless Chromium check passes against generated onboarding HTML
for minimal signup, workflow validation, and selected services with networking disabled.

## Sprint 8: catalogue audit and missing-metadata guidance

Addresses #31 and #115.

- Audited the authors in #31 against the current live MetaCPAN latest-release
  query and rendered every returned release through the production parser/template.
- TOBYINK returned 347 releases and 347 rows, including 15 without a usable
  repository and 40 with a non-GitHub repository. SZABGAB returned 36 and 36,
  including three without a repository and one with a non-GitHub repository.
- Recorded query scope and counts in `audits/catalogue-2026-10-10.json`.
  The historical repository-only filter was already absent from the active
  parser; this session adds regression coverage and a visible explanation.
- Added a missing-link indicator with guidance for updating release metadata.
  Valid GitLab/Bitbucket links remain usable and retain generic badges.

Validation: 400 offline Perl checks across twelve files and twelve JavaScript
checks pass. Live API totals matched rendered rows exactly for both cited authors.
The read-only audit did not replace stored snapshots or change branch caches.

## Sprint 9: final failure-path review

Completes additional edge cases under #93 and #121.

- Made a failed home-page template render stop the build, matching author,
  additional-page, and sitemap error handling.
- Classified retry reasons after removing MetaCPAN's URL and Perl callsite;
  author IDs and filenames containing timeout/network words no longer trigger retries.
- Added HTTP::Tiny's actual connection/DNS failure phrases and ensured explicit
  permanent HTTP responses and certificate verification errors are not retried.

Validation: 415 offline Perl checks across thirteen files and twelve JavaScript
checks pass. Invalid home-page templates stop before status/sitemap publication;
network errors remain retryable while context-only matches remain permanent.

## Sprint 10: rendering and badge-URL review

Additional rendering fixes found during final verification.

- Corrected the Font Awesome integrity hash, which incorrectly contained the
  Bootstrap CSS hash and caused browsers to block the stylesheet.
- Updated onboarding accordion attributes for the pinned Bootstrap 5 bundle.
- URL encoded branch names and Cirrus task names so punctuation cannot change
  URL paths, fragments, or query values.

Validation: 424 offline Perl checks across thirteen files and twelve JavaScript
checks pass. All three declared CDN integrity hashes match the pinned asset bytes.
An isolated Chromium check verifies accordion expansion/collapse and registration
generation using those exact Bootstrap assets with external networking disabled.

## Publication follow-up

PR #122 was merged during the session, and #123 now targets master. Tests on
Perl 5.40 and 5.42 passed, but the generation container exposed a fixture portability
bug: the fake GitHub CLI used `/usr/bin/perl`, while dependencies were installed
for `/usr/local/bin/perl`. Updated its shebang to the running test interpreter
(`$^X`). The publication gate correctly prevented deployment of that failed run.
This fix is included in #123; the generator must be rerun after it is merged.

The subsequent generation run passed its test gates but failed on an opaque
MetaCPAN scrolling error for MIKKOI, which had no fallback snapshot. PR #125 adds
bounded retries for those errors, checks release ownership and completeness,
and supplies a verified 23-release snapshot. The same recovery fix is included
here, with CI expanded to Perl 5.44 and generation pinned to that tested major.
Combined validation now passes 457 Perl checks and twelve JavaScript checks.
