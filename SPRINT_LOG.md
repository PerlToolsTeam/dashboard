# Robustness session — 10 October 2026

Session window: 14:51–16:21 UTC (90 minutes).
Branch: `robustness-sprints-2026-10-10`.

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
