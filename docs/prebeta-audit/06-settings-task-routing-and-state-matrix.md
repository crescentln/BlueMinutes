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

> Codex is used for bounded text analysis, chat, document questions, and
> structured outputs. Speech-to-text and external research must be configured
> separately.

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
| Codex subscription | Bounded text tasks except external research; never STT | Authorized text through Codex account | User's Codex subscription |

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

Provider runtime readiness is not external-processing authorization. Local
routes may become ready directly when installed. Codex and remote candidates
must additionally bind deployment environment, destination, retention, data
categories, organization policy, visible user authorization, and an approved
adapter through the existing `ModelRouteRequest` policy path. The implemented
OpenAI batch adapter consumes only that exact authorization; a ready connection
profile by itself cannot upload audio.

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
| External Research | Capable BYOK only | Off; Sensitive forbids |

The 0.4 application executes and revalidates the persisted Meeting Chat route
through Codex Assistant. The other text-task rows are saved routing preferences
for later dedicated executors; choosing them does not itself start processing.
Codex is ineligible for External Research because the isolated runtime disables
web, Apps, plugins, and MCP.

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

The deterministic three-state scope stack remains the resolver contract.
Current app-wide non-secret provider and task-route settings persist in a
private revisioned JSON repository under Application Support; credentials stay
in Keychain. `MeetingProfileV1` stores the exact selected STT intent without a
secret or one-time upload authorization, and each transcript job stores the
exact executable route snapshot. Reopen restores the provider/model intent but
never restores visible upload authorization.

The stack cannot be assembled from independent identity values and an unrelated
policy snapshot. `TaskRoutingSecurityContext` first validates the exact
`MeetingProfileV1 -> SensitivityLabelV1 -> AccessPolicyV1` graph, derives
`WorkspaceID` and `MeetingID` from that meeting, and requires the immutable
model-policy snapshot to match the graph without wider local, external, or
provider authority. The winning global/workspace/meeting profile origin remains
separate routing evidence. A later post-record route change controls the new
transcript job but does not rewrite the immutable meeting-start profile; a full
profile-supersession graph is an explicit residual design decision.

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
and credentials are independently observable. App-server process loss is typed
and explicitly reconnectable without restarting BlueMinutes. Configuration
reload restores non-secret provider/route records; missing Keychain material
produces repair state. A completed verified recording that has not yet entered
canonical processing is restored after app restart. No recovery path may
restart or discard an active meeting.
