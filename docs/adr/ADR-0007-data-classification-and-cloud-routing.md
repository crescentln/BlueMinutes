# ADR-0007: Data Classification and Cloud Routing

Status: Accepted
Date: 2026-07-17
Decision owners: User and Codex
Applies from: Task 003A contracts; enforced from Task 005B

## Context

Diplomatic source and derived material may range from public to restricted.
Provider availability alone is not authority to transmit content externally.

## Decision

- Every source and derived object carries `public`, `internal`, `sensitive`, or
  `restricted` classification.
- Derived objects inherit the highest input classification unless an explicit,
  reviewed declassification action changes it.
- A provider call is allowed only by the intersection of task capabilities,
  meeting policy, input classification, user provider policy, and provider data
  policy.
- Any deny blocks the call.
- `sensitive` data is local by default. `restricted` data is not externally
  processed without a separately approved institutional policy.
- The UI displays route, provider, exact bounded material, and policy authority
  before processing and in task history.
- Prompt/source content cannot alter classification or routing rules.

## Consequences

- Classification belongs in foundational domain contracts even before a
  provider exists.
- Task 005B must test enforcement rather than merely displaying a preference.
- A summary is not treated as automatically less sensitive than its source.
- Provider fallbacks cannot weaken policy when the preferred route fails.
