# ADR-0006: Inference Provider and Agent-Control Boundaries

Status: Accepted
Date: 2026-07-17
Decision owners: User and Codex
Applies from: Task 005B for inference and Task 009A for control

## Context

MeetingBuddy needs bounded model inference and may later expose controlled
operations to external agents. Combining those interfaces would allow a model
or agent to bypass domain validation, privacy policy, and storage services.

## Decision

- An Inference Provider performs one bounded transcription, translation,
  extraction, validation, or generation job.
- An Agent Control Adapter invokes typed, validated application commands.
- The two interfaces are separate trust boundaries and cannot call one another
  recursively by default.
- Providers consume only versioned semantic input packages and never query
  SQLite or receive arbitrary filesystem access.
- Automation adapters use the same application services, permissions,
  transactions, confirmations, and audits as the UI.
- Provider-specific SDK types do not enter the domain layer.
- Subscription-backed clients remain experimental, use official local clients
  only, and never expose or extract account credentials.

## Consequences

- Task 005B may add provider interfaces without creating CLI, MCP, or an HTTP
  server.
- Task 009A must prove a shared command layer and CLI before Task 009B adds MCP
  or experimental client adapters.
- Every job records origin and disallows recursive MeetingBuddy calls unless a
  separately reviewed workflow permits them.
- No local HTTP API is created without a concrete, separately approved client
  need.
