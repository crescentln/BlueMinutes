# ADR-0010: Task 006A Local Analysis Route

Status: Accepted; Task 006A is accepted and frozen
Date: 2026-07-18
Decision owners: Codex under the user's Task 006A authorization
Applies from: Task 006A

## Context

Task 006A requires one approved analysis route before any real analysis-provider
implementation or call. The route must create bounded, structured diplomatic
extractions without granting outbound meeting-data authority, adding a model
dependency, or weakening the accepted macOS 15 no-external-processing posture.

The selected Xcode 26.6 SDK contains Apple's `FoundationModels` framework. On
the current macOS 26 validation host, `SystemLanguageModel.default` reports
`available` and supports the English and Simplified Chinese validation locales.
Apple documents this model as on-device and suited to bounded extraction and
classification with guided structured generation rather than world knowledge
or advanced reasoning.

## Decision

- On macOS 26 or later, use `SystemLanguageModel.default` only when its runtime
  availability and requested locale checks pass.
- The route is local-device only. MeetingBuddy authorizes no server, Private
  Cloud Compute, cloud, URLSession, or other outbound analysis adapter in Task
  006A and initiates no model download.
- Each call receives only one bounded, versioned semantic package containing
  the eligible reviewed transcript or translation segment, exact speaker and
  capacity context, and opaque evidence identifiers needed for that segment.
  It receives no database handle, workspace root, or arbitrary file path.
- Use `FoundationModels` guided generation to obtain a small provider DTO.
  Provider output is candidate data only: application-owned deterministic
  validation must enforce the claim taxonomy, exact evidence, actor/capacity,
  reservation/condition semantics, classification inheritance, and complete
  segment coverage before any semantic revision is persisted or published.
  Delegation cards are produced by a deterministic bounded aggregation over
  those already validated claims and their exact evidence revisions; the model
  does not receive a second aggregation or synthesis pass.
- Use a fresh bounded session for each eligible segment. Disable tool calling
  and external retrieval. Protected diplomatic rules are application-owned
  instructions; transcript, translation, document, and metadata text remains
  explicitly delimited untrusted source data.
- Reuse the accepted `ModelPolicyRouter`. The route records local-device
  destination, no provider retention, exact bounded data categories, host OS
  model version, prompt-module versions, visible user authorization, and the
  policy decision in job history and the analysis coverage ledger.
  `noProviderRetention` describes the provider boundary; accepted derived
  revisions and route evidence remain durable inside the local workspace under
  MeetingBuddy's storage and recovery policy.
- Require the visible **Analyze Locally** action for each bounded run. On macOS
  15 through 25, or whenever the model, locale, or policy route is unavailable,
  automatic creation is unavailable and nothing is sent elsewhere. Existing
  local intelligence remains inspectable and correctable. A deterministic
  provider fake remains test-only and is not a production fallback.
- Model output can never assert historical policy change. Task 006A stores only
  an explicit comparison state that remains unknown or insufficient evidence;
  Task 010 owns historical-change conclusions.
- Apple can update the on-device model with the operating system. Record the
  exact host OS version and adapter contract, and rerun the Task 006A Golden
  evaluation before treating a new host model as validated.

## Rejected alternatives

- A cloud or API provider is rejected because Task 006A grants no outbound
  destination, retention contract, credential, or transmission authority.
- A bundled third-party local model is deferred because this task does not
  authorize its dependency, license, model-size, update, signing, or packaging
  lifecycle.
- A deterministic fake alone is insufficient as a production route.
- Free-form JSON or prose output is rejected because structural conformance
  alone cannot enforce evidence or diplomatic claim rules.
- Tool calling, web retrieval, and autonomous multi-step political assessment
  are outside Task 006A.

## Consequences

- Automatic analysis requires macOS 26+, an eligible Apple Intelligence device,
  enabled and ready model assets, a supported locale, and an allowed local
  policy route. Otherwise the UI explains that automatic creation is
  unavailable while preserving review of existing local results.
- Framework-specific types remain inside `MeetingBuddyAI`; domain and
  application contracts remain provider-neutral.
- The on-device model is used only for bounded extraction. Deterministic
  application validation, immutable persistence, evidence links, user review,
  and fail-closed coverage remain authoritative.
- No dependency, credential, network implementation, entitlement, telemetry,
  capture authority, or external retention policy is added.
- ADR-0011 resolves the Task 006B review boundary without authorizing an
  independent reviewing provider; deterministic validation and manual review
  remain authoritative.

## Validation required before Task 006A completion

- Compile-time guided-generation schema validation under the selected Xcode.
- Runtime availability and locale checks with an explicit unavailable fallback.
- Provider-fake tests for malformed, unsupported, invented, omitted,
  duplicated, and evidence-mismatched output.
- One opt-in on-device run using only project-authored synthetic fixture
  `task006a-live-synthetic-diplomatic-001@1`, SHA-256
  `d220ba7046fb638853b24cc0eaf31b477576f1a4b0b4be6ab297a5f19ed49898`.
- Source scans confirming no new network implementation, credential, model
  artifact, dependency, or entitlement change.
- Full Golden, coverage, migration/rollback, and stale-propagation gates.

## References

- [Meet the Foundation Models framework](https://developer.apple.com/videos/play/wwdc2025/286/)
- [SystemLanguageModel](https://developer.apple.com/documentation/FoundationModels/SystemLanguageModel?language=_8)
- [Generate Swift data structures with guided generation](https://developer.apple.com/documentation/foundationmodels/generating-swift-data-structures-with-guided-generation?changes=_1)
