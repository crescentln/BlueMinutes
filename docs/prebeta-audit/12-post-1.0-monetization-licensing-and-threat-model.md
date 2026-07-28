# Post-1.0 Monetization, Licensing, and Threat Model

## Current phase

Public Beta and 1.0 use `BillingMode.disabled`.

Disabled means:

- every product feature is unlocked;
- no trial countdown or paywall;
- no device limit;
- no account/activation requirement;
- no licensing client construction;
- no billing/licensing network request;
- no Stripe or website availability dependency; and
- recording, STT, Codex, editing, export, and update state remain independent.

`BillingFeatureGate.publicBeta` encodes this behavior. Production cannot be
constructed through the current public application contract. Internal sandbox
requires a non-public build approval token and still is not wired into app
composition. The running app composes the public-Beta release configuration in
the About surface, which shows all features unlocked, billing disabled, and the
website disconnected. A full runtime network-spy session is still required
before claiming complete zero outbound billing traffic. A bounded isolated
idle/About/close/reopen/quit smoke observed no established TCP or UDP socket,
but did not exercise every provider, failure, or duration state.

## Modes

| Mode | Intended use | Current availability |
| --- | --- | --- |
| `disabled` | Beta/1.0 unlocked product | Composed and live-observed in About; bounded no-socket smoke passes, full runtime network-spy proof pending |
| `sandbox` | Explicit internal payment/license tests | Vocabulary and build gate only |
| `production` | Post-1.0 commercial service | No constructor/client/UI; go/no-go required |

## Future commercial policy from v4

The post-1.0 design target, not current behavior:

- seven-day trial;
- USD 50 annual standard price;
- USD 35 invoices through 2027-08-31 America/New_York;
- USD 50 for new purchases and renewals from 2027-09-01;
- up to three devices;
- existing-user migration with a complete trial where promised;
- local data remains readable after entitlement loss;
- an active meeting may finish and save if entitlement changes;
- production can roll back to disabled without corrupting local work.

These values must not appear as an active offer until legal, tax, support,
refund, privacy, terms, monitoring, migration, and rollback gates pass.

## Website/payment boundary

The separately developed BlueMinutes website remains disconnected from this
repository. No visible website, account, billing, or download state grants
desktop authority.

The sandbox payment repository has versioned HTTP/license concepts, but the app
does not connect to it. A checkout success redirect is not payment or
entitlement proof. Future activation must validate server-signed,
device-bound entitlement material and exact status through the licensed
protocol.

App-side `WebsiteIntegrationConfiguration` defaults to `.disconnected` and permits
no update or billing endpoint while disabled. Public/support/privacy links stay
separate from billing. Any future update feed requires the dedicated updater
approval and exact update-feed allowlist; the composed release configuration
rejects a missing or different `UpdatePolicy.feedURL`.

## Future server boundary

A separately approved production design needs:

- versioned public config;
- checkout and customer portal;
- webhook-authoritative payment state;
- claim/activate/refresh/deactivate/device APIs;
- signed entitlement with key rotation;
- replay/idempotency protection;
- server-side time and campaign cutoff;
- bounded offline lease and grace policy;
- revocation/device replacement;
- privacy-minimal identifiers;
- audit/monitoring without meeting metadata; and
- reverse-order rollback to disabled.

## Threat model

Protect against:

- forged or replayed entitlement;
- browser success URL treated as authority;
- sandbox/production endpoint confusion;
- device-ID cloning and excessive activation;
- local clock rollback;
- stale signing keys;
- webhook duplication/reordering;
- licensing outage blocking a meeting;
- secrets or full account data in logs;
- a compromised website granting app access; and
- a production flag enabled by one runtime preference.

Reasonable code-signing and server-signature checks are appropriate.
Kernel extensions, invasive anti-debugging, and destructive lockout are
rejected. Local user data must remain accessible.
