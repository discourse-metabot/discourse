# Plugin badge identity (review proposal)

## Identity and normal operation

Core badges have reserved numeric IDs. Historically plugin badges were allocated
site-local IDs (normally >=100) and then seeded by display name. A display name
is not ownership: a plugin could overwrite an unrelated custom badge, including
its query, type and `system` flag.

This proposal keeps the existing numeric primary keys rather than attempting to
renumber historical installations. `badges.plugin_badge_key` is a nullable,
uniquely indexed, immutable namespaced identifier (for example `live:host`).
The resolver finds that ownership record and runs `Badge.seed(:id)` against its
site-local numeric ID. Keys are explicit literals, never derived dynamically
from translated or editable display names. The admin badge API cannot set them.

The helper serializes plugin resolution and ordinary automatically allocated
badge creation with the same transaction-scoped PostgreSQL advisory lock.
The unique key index is an additional integrity guard. This does not change
core's reserved IDs or renumber custom badges.

Live's instant grants, master enable/disable switch and Topic Voting's targeted
backfill/notification handling now use ownership keys. A badge grouping is
presentation, not plugin ownership. A custom badge in the Live grouping must
not be disabled by Live; moving a real Live badge must not detach its ownership.

All four bundled `Badge.seed(:name)` fixtures (Live, Solved, Reactions and Topic
Voting) use the resolver. Patreon still creates a site-managed, non-system
Patron badge; it is not converted into a system/plugin badge by this proposal.

## Historic installations

On the first seed, an unowned historical badge may be adopted only when exactly
one known-name candidate has `system=true`, a matching protected-field
fingerprint and an exact known query. Outer whitespace may be trimmed, but SQL
literals/comments are not normalized. Live supplies the explicit old Voice-table
variant of its trusted fixture definition. Instant badges additionally require
a known Voice/Live grouping and the expected icon.

Adoption attaches ownership without changing the primary key. Existing awards,
profile title references, notification payloads and URLs therefore keep their
original numeric references. Existing disabled states and per-site defaultable
customizations remain intact. Repeated seeds resolve ownership directly.

Historical definitions that do not match the known fingerprint are **not**
automatically claimed. In particular this is not an exhaustive catalog of every
previous plugin query version. Administrators need to review such unmatched
records. A matching fingerprint is a compatibility heuristic, not proof that a
badge was never overwritten by an older name-based seed.

### Patron: deliberately ambiguous history

An old `Patron` with `system=true` and a Voice/Live query might be either a real
Live badge or a custom badge already overwritten by the faulty seed. The current
row cannot distinguish those histories. The original custom query/type and the
provenance of individual awards cannot be reconstructed reliably from it.

Therefore the new Live definition is **Live Patron**, owned by `live:patron`.
The old Patron row is not adopted, renamed, deleted, enabled, disabled or assigned
a guessed Patreon query. Its ID, definition and awards remain untouched. A
pre-existing disabled/clobbered Patron is **not automatically restored by this
PR**; it requires administrator review against a backup or the intended custom
badge definition. Existing genuine Live Patron awards are likewise not silently
moved to the new badge. This is the deliberate safety trade-off for ambiguous
historical data.

For an affected site, take a backup, inspect badge/award history, and restore the
intended definition and enabled state explicitly on the original ID. Do not
infer Patreon membership from the name or assume all existing grants came from
one source. Re-running seeds after repair must leave that custom row alone.

### Other name collisions

For a previously unowned key, an occupied desired name causes a warning and a
skipped plugin seed, not takeover or an upgrade failure. This includes a custom
`Live Patron`: the plugin badge remains unavailable until the collision is
resolved explicitly. For an already owned badge, an occupied new default name
leaves its current name in place while seeding its definition by ID.

## Verification

Focused specs cover stable IDs, repeat seeding, custom/unrelated-system name
collisions, legacy Voice adoption, preservation of grants/profile-title IDs and
disabled states, immutable ownership, admin API assignment rejection, SQL-literal
fingerprint differences, Live grouping independence, safe instant grants and
custom Patron HTTP 200 before/after a disabled-Live seed.

These are review-proposal semantics, not a claim of automatic recovery for lost
custom definitions or a full historic-upgrade/rolling-deployment matrix.
