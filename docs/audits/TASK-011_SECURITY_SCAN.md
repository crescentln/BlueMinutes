# Task 011 Security Scan Summary

Scan ID: `ec5ba727-af63-4f1a-bd8c-feb3001ed3a2`
Mode: standard repository scan
Target revision: `2a0d7fe7ac8ab10d125f3c65b6606238e4df9343` plus the captured worktree snapshot
Target snapshot: `codex-security-snapshot/v1:sha256:a51062c31c5b5ac3a3a2f15574ad59cb810cc19e1ff0eb680c49a9d231f9d0a7`
Status: sealed, validated, indexed, and complete

## Coverage and reconciliation

- 134 production/configuration worklist rows
- 134 completion receipts
- 29 raw candidates
- 29 validation reports and candidate ledgers
- 29 attack-path reports
- 25 canonical candidates after true-duplicate reconciliation
- 7 reportable findings after attacker-boundary and severity-policy review
- Severity: 4 medium, 3 low; no critical or high finding

The scan inventoried 130 production Swift files plus `Package.swift`, two
configuration entries, and one script entry. Tests and governing documents
were consulted as validation and threat-model evidence rather than counted as
primary production attack-surface rows.

## Reportable findings

| Priority | Finding | Task 011 status |
|---|---|---|
| P2 / medium | Structurally valid analysis output can become active evidence-linked intelligence without semantic entailment. | Open; architectural grounding/quarantine is required. |
| P2 / medium | Source-key-only briefing validation can activate fabricated text with valid provenance keys. | Open; generic grounding or human confirmation is required. |
| P2 / medium | Provider-only `nonSubstantive` can omit eligible analysis segments while coverage publishes. | Open; exact-segment evidence plus independent/human confirmation is required. |
| P2 / medium | Provider-only `noSpeech` can omit spoken chunks while transcript coverage publishes. | Open; independent acoustic/human confirmation is required. |
| P3 / low | Canonical chunk planning had no duration limit before allocation. | Mitigated in the post-scan Task 011 working tree with a three-hour limit and boundary tests; follow-up scan required. |
| P3 / low | Audio-track enumeration had no application cardinality limit. | Mitigated in the post-scan Task 011 working tree with a 32-track limit before per-track loading; follow-up scan required. |
| P3 / low | Blocked HTML cleanup repeatedly rescanned a bounded one-megabyte string. | Mitigated in the post-scan Task 011 working tree with monotonic cleanup and a regression fixture; follow-up scan required. |

## Rejected and retained hardening candidates

Same-user workspace symlink/path races, verified-URL replacement races, and
recovery-artifact identity swaps were suppressed because they require equal
local workspace authority and did not establish additional privilege,
confidentiality, execution, or network authority. Ordinary crash/corruption
and aggregate-recovery issues were also not promoted as security findings.

They were not discarded from engineering review. Task 011 adds three defense-in-
depth correctness controls discovered in that review:

- managed intake stops before writing beyond the inspected byte ceiling;
- recording restore rejects outcomes that still require reconciliation; and
- blocked HTML with an unclosed `script`, `style`, `template`, or `noscript`
  element now fails closed as parser drift instead of exposing the remainder as
  visible metadata.

Descriptor-bound no-follow filesystem APIs, bounded recovery batches, and
aggregate recovery-artifact budgets remain future defense-in-depth work.

The sealed scan retains a traceability limitation: validation and reconciled
candidate ledgers preserve more rows as reportable/surviving than the final
seven policy-selected findings, while the final stage does not emit one
explicit suppression receipt per omitted candidate. This does not change the
seven-findings result under the current equal-authority, single-user threat
model. A follow-up scan must record per-candidate counterevidence and reopen
conditions, especially if shared/network/external workspaces, multi-user ACLs,
helpers/daemons, remote wrapping, broader entitlements, or unequal sandbox
reachability are introduced.

## Method limitation and Trusted Access

The host declined display of some weaponized reproducer wording and showed a
Trusted Access message. Trusted Access was not required to continue the
project. Validation proceeded with static source-to-sink analysis, existing
deterministic tests, bounded non-weaponized fixtures, canonical deduplication,
and attack-path review. No exploit payload, destructive race harness, real
meeting content, user workspace, credential, or external target was used.

The display restriction is a method constraint, not counterevidence. The four
medium control gaps are deterministic after structurally valid provider output;
model-specific inducibility remains an explicitly unmeasured factor.

## Release consequence

The scan does not support external beta or release-candidate classification.
`INTERNAL ALPHA` is permitted only for local synthetic/non-sensitive evaluation
with human review of all derived intelligence. Before external release:

1. remediate all four medium evidence-integrity findings;
2. accept and commit the Task 011 changes under explicit user authority;
3. run a security diff/follow-up scan against that exact accepted revision; and
4. bind closure records to regression evidence and the new scan occurrence IDs.

The sealed scan remains immutable. Post-scan working-tree fixes do not alter or
silently close its findings.
