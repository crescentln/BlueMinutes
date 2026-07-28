# Data Provenance, Storage, and Migration

## Semantic chain

```text
SourceAsset revision
  -> canonical audio plan and coverage
  -> raw machine transcript revision
  -> human-corrected transcript revision
  -> translation revision
  -> evidence-linked analysis revisions
  -> human-confirmed claims
  -> briefing section revisions
  -> final export bound to exact revisions
```

Original speech, machine transcription, human correction, translation, model
inference, and human-confirmed facts retain distinct provenance. Active
pointers may advance, but published semantic revisions are immutable.
Dependency edges mark downstream objects stale rather than silently rewriting
them.

## Provider and route evidence

Existing job and coverage contracts already record `ProviderMetadata`,
`ModelRouteDecision`, exact data categories, classification, destination,
retention, and policy revision references.

The v4 routing snapshot adds product-level task, selected capability, provider,
model, data route, cost owner, and scope. Composition must translate that
snapshot into the existing model-policy request; it must not bypass the
application router.

Codex thread identifiers and conversation state are not semantic evidence by
themselves. A Codex-derived claim must still enter the typed validation and
human-confirmation path with exact bounded input references.

## Workspace structure

The accepted workspace keeps:

- SQLite metadata and immutable revision/audit records;
- managed source/audio/derived files;
- task-owned temporary/checkpoint directories;
- exports;
- backups and Workspace Trash.

Providers never query SQLite or receive arbitrary workspace paths. Application
services retrieve bounded values. Credentials remain outside the workspace in
macOS Keychain.

## Official and automatic transcript sources

Future UN automatic transcripts and official records are independent immutable
source assets with explicit authority/type labels. A local STT transcript is a
third derivation. None may overwrite another; UI comparison and selection
create exact references.

## Migration plan

The current schema is v10. The foundation contracts do not change it.
Persisting routing profiles, meeting snapshots, Codex thread metadata, or
official-transcript source types requires an ordered v11 migration with:

1. verified v10 backup and rollback anchor;
2. additive tables/columns and fail-closed defaults;
3. no fabricated provider setting or external authority;
4. supported-v10 migration tests;
5. interrupted-migration recovery;
6. cold-copy rollback reopen; and
7. immutable payload byte comparison before/after.

Unknown provider capability or route values must remain unavailable until a
newer application understands them.
