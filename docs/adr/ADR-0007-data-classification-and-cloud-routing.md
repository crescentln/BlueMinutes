# ADR-0007: Data Classification and Cloud Routing

Status: Accepted
Date: 2026-07-17
Decision owners: User and Codex
Applies from: Task 003A contracts; enforced from Task 005B

## Context

Diplomatic source and derived material may range from public to restricted.
Provider availability alone is not authority to transmit content externally.

## Decision

- Meeting audio, transcripts, meeting metadata, and derived intelligence remain
  local by default for every classification, including `public`.
- Every source and derived object carries `public`, `internal`, `sensitive`, or
  `restricted` classification.
- Derived objects inherit the highest input classification unless an explicit,
  reviewed declassification action changes it.
- A provider call is allowed only by the intersection of task capabilities,
  meeting policy, input classification, user provider policy, and provider data
  policy.
- Any deny blocks the call.
- An external path exists only after an explicit architectural policy decision
  names the permitted provider, bounded data categories, destination,
  deployment environment, provider retention, and visible user authorization.
  The same supported workflow retains a local/offline or no-external-processing
  mode.
- Model eligibility additionally evaluates offline/no-outbound mode,
  organization policy, and deployment environment. A model dropdown cannot
  override the decision, and fallback never selects a less restrictive route.
- `sensitive` data is local by default. `restricted` data is not externally
  processed without a separately approved institutional policy.
- The UI displays route, provider, exact bounded material, and policy authority
  before processing and in task history.
- Prompt/source content cannot alter classification or routing rules.

## Consequences

- Classification belongs in foundational domain contracts even before a
  provider exists.
- Accepted Task 005B tests enforcement rather than merely displaying a
  preference; Tasks 007 and 011 revalidate the no-outbound and fallback gates.
- Provider selection is the first in-task Task 005B decision gate before any
  real provider call; it does not block starting 005B and task authorization
  alone does not authorize outbound transfer.
- A summary is not treated as automatically less sensitive than its source.
- Provider fallbacks cannot weaken policy when the preferred route fails.
- No outbound inference provider is approved through Task 011. The only app
  network implementation is the exact-host UN Web TV metadata route accepted
  under ADR-0013; it grants no media acquisition or provider authority.
