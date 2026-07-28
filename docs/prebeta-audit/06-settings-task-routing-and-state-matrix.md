# Settings, Task Routing, and State Matrix

## Settings order

The new Intelligence surface uses the existing Settings `TabView` and `Form`
language. Its visible order is fixed:

1. **Codex with ChatGPT Subscription**
2. **Speech-to-Text Setup**
   - Local STT Models
   - Remote STT API
   - Not Configured / Record Only
3. **Bring Your Own API Key**
4. **Task Routing**

The header must state:

> Codex is used for text analysis, chat, research and structured outputs.
> Speech-to-text must be configured separately with a local model or a remote
> STT API.

## Capability registry

`Sources/MeetingBuddyApplication/ProviderRoutingContracts.swift` defines exact
model capabilities:

- batch and realtime speech-to-text;
- speaker processing;
- translation;
- selected-text analysis;
- summary/minutes;
- meeting chat;
- document query;
- external research;
- structured output.

Built-in profiles currently describe:

| Provider | Exact current capability | Data route | Cost owner |
| --- | --- | --- | --- |
| Apple Speech | Batch STT | Local only | Local device |
| Apple Translation | Translation | Local only | Local device |
| Apple Foundation Models | Text analysis, summary/minutes, structured output | Local only | Local device |
| Codex subscription | Text tasks; never STT | Authorized text through Codex account | User's Codex subscription |

The registry is eligibility metadata, not runtime readiness or user
authorization.

## Route state

Each global/workspace/meeting entry is exactly one of `inherit`, `disabled`, or
`selection(primary, repair/fallback)`. These states are not represented by an
optional provider. The resolver returns:

- `ready(exact route)`;
- `requiresExecutionAuthorization(candidate)` for an otherwise eligible external
  route that still lacks the complete `ModelRouteRequest` execution gate;
- `recordOnly` for unconfigured STT; or
- `unavailable(reasonCode, repairSelection)`.

Fallback is never activated silently. Runtime states distinguish ready,
not-installed, not-authenticated, invalid credential, incompatible runtime,
quota unavailable, and unavailable.

Provider runtime readiness is not external-processing authorization. Only local
routes can become `ready` in the foundation resolver. Codex/remote candidates
must additionally bind deployment environment, destination, retention, data
categories, organization policy, visible user authorization, and an approved
adapter through the existing `ModelRouteRequest` policy path.

## Task matrix

| Task | Eligible route | Default foundation state |
| --- | --- | --- |
| Speech-to-Text Batch | Batch-capable local/remote STT / None | Apple when installed or explicit Record Only |
| Speech-to-Text Realtime | Realtime-capable local/remote STT / None | Record Only; no built-in realtime model is declared |
| Speaker Processing | Capability-declared local/remote backend | Off |
| Translation | Apple / Codex / capable BYOK | Apple when installed; otherwise explicit repair |
| Text Analysis | Apple / Codex / capable BYOK | Explicit selection |
| Summary & Minutes | Apple / Codex / capable BYOK | Explicit selection |
| Meeting Chat | Codex / capable BYOK / future local text | Off until connected |
| Document Query | Codex / capable BYOK | Off until connected |
| External Research | Codex / capable BYOK | Off; Sensitive forbids |

## Scope and precedence

The intended precedence is:

```text
compiled safety policy
  > exact immutable ModelSecurityPolicySnapshot
  > meeting override (inherit / disabled / selection)
  > workspace override (inherit / disabled / selection)
  > global override (inherit / disabled / selection)
  > fail-closed disabled state
```

Missing entries and `inherit` continue to the next less-specific scope.
`disabled` stops resolution immediately. Therefore a meeting-level explicit
Record Only selection masks a workspace or global STT route and can never be
mistaken for inheritance.

The foundation slice implements this deterministic in-memory three-state scope
stack but does not persist it. Persistence requires schema v11,
migration/rollback proof, supported-v10 tests, and fail-closed unknown decoding.
The stack cannot be assembled from independent identity values and an unrelated
policy snapshot. `TaskRoutingSecurityContext` first validates the exact
`MeetingProfileV1 -> SensitivityLabelV1 -> AccessPolicyV1` graph, derives
`WorkspaceID` and `MeetingID` from that meeting, and requires the immutable
model-policy snapshot to match the graph without wider local, external, or
provider authority. The winning global/workspace/meeting profile origin remains
separate routing evidence.

## Routing snapshot

Before work starts, BlueMinutes must store:

- task;
- exact provider and model;
- selected capability;
- data route;
- cost owner;
- meeting/profile scope;
- exact workspace ID, meeting ID, meeting revision, and winning scope/profile
  origin;
- an owner-bound routing-profile scope: global, exact workspace ID, or exact
  immutable meeting revision; a profile loaded for another owner fails closed;
- visible authorization evidence where external;
- policy revisions and classification;
- resolved timestamp and contract version.

Changing settings later does not rewrite an existing job snapshot.

## Sensitive Meeting

The resolver consumes the exact immutable `ModelSecurityPolicySnapshot`,
including sensitivity-label revision, access-policy revision, effective
classification, no-outbound mode, and approved external provider identifiers.
It does not accept a free-standing UI Boolean or rely on hiding remote options
in SwiftUI. Sensitive/restricted or no-outbound snapshots require `localOnly`
for every task and disable external research. Missing local STT becomes
unavailable/record-only; it never falls back to Codex, remote STT, or a BYOK
text provider.

## Restart behavior

UI preferences remain immediate. Provider runtime reconnect, model install,
and credentials are independently observable. App-server process restart must
not require application restart. A future migration may require reopening a
workspace but must never restart or discard an active meeting.
