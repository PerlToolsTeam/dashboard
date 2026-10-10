# Metadata gathering failure — 10 October 2026

Generation run [38067343497](https://github.com/PerlToolsTeam/dashboard/actions/runs/38067343497)
passed its tests, then failed gathering MIKKOI with `failed to fetch next scrolled
batch`. That author had no persistent snapshot, so fallback could not continue.
The preceding log contained releases unrelated to MIKKOI. The cause of that
unfiltered response has not been established.

Live queries now return 23 MIKKOI releases using both MetaCPAN::Client 2.040000 and
2.044000, including the exact production image and dependencies. A verified fresh
snapshot is stored in `authors/data/MIKKOI/data.json`, with every release belonging
to MIKKOI and a successful gather timestamp.

The recovery change:

- Retries the client's opaque scroll errors within the existing attempt limit.
  These exceptions suppress HTTP status information, so they previously escaped
  the HTTP/network retry classifier.
- Rejects releases belonging to another author before repository processing.
- Checks the completed list against the iterator's advertised total, catching
  early empty pages as well as exceptions. Invalid lists never replace snapshots.
- Pins generation to Perl 5.44 and adds that version to test CI, alongside 5.40
  and 5.42, matching the production major version instead of drifting with latest.

Validation: 310 offline Perl checks pass locally and in the exact production image
(`sha256:0ea4a4de1034d374754e596f439f126ce29194f7735a5200c2842df70bde06bd`).
The real MetaCPAN client is exercised against mocked HTTP responses, including
HTTP 503 on pagination followed by a successful complete restart. Three JavaScript
checks pass. A cold-output integration build with three injected scroll failures
renders all 23 MIKKOI rows from the new snapshot, displays a cache warning, and
preserves the snapshot bytes. All stored snapshots were checked for foreign-author
records; none were found.

After merging the fix, generation must complete successfully before publication
can be considered verified. The existing site remains unchanged by failed runs.
