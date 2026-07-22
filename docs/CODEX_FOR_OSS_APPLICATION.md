# Codex for Open Source Application Pack

Status: draft; public-repository gates complete; submit after the maintainer
verifies the private account fields and final live-form text
Last verified against the official form: 2026-07-22

The maintainer-selected public project name is `BlueMinutes`. Internal
compatibility identifiers continue to use `MeetingBuddy` where renaming would
create unnecessary migration or operational risk.

The primary requested program benefit is **six months of ChatGPT Pro, including
Codex**. The official form lists that subscription as a benefit for selected
maintainers rather than as an interest checkbox. API credits are a useful
additional request; Codex Security is not requested and trusted access is not a
prerequisite for the ChatGPT Pro benefit.

## Current official eligibility signals

The official program says maintainers of active open-source projects may apply
and reviews meaningful usage, broad adoption, clear ecosystem importance, and
evidence of active maintenance. The application form requires a public GitHub
profile and a public repository. Its three narrative fields each allow at most
500 characters. The Program Terms also require accurate and complete
information about the applicant, repository, and maintainer role; selection is
not guaranteed.

Official references:

- [Codex for Open Source](https://developers.openai.com/community/codex-for-oss)
- [Application form](https://openai.com/form/codex-for-oss/)
- [Program terms](https://learn.chatgpt.com/docs/codex-for-oss-terms)

BlueMinutes is now published at the public
[`crescentln/BlueMinutes`](https://github.com/crescentln/BlueMinutes)
repository. Signed-out page, raw-file, API, and anonymous Git checks resolve
public baseline `e621537`, and
[exact-main public CI run 29964705558](https://github.com/crescentln/BlueMinutes/actions/runs/29964705558)
passes.

## Current readiness scorecard

| Gate | Current status | Required before submission |
| --- | --- | --- |
| Public GitHub profile | Ready | Public API state and a signed-out HTTP request both succeeded; repeat the visual check immediately before submission. |
| Public GitHub repository | Ready | Public visibility, signed-out HTTP, unauthenticated API, and anonymous Git all resolve exact baseline `e621537`. |
| Open-source license and governance | Ready | Apache-2.0, notices, policies, templates, and community files are visible publicly. |
| Build and tests | Ready | [Public exact-main run 29964705558](https://github.com/crescentln/BlueMinutes/actions/runs/29964705558) passes the warning-as-error build, focused gates, and complete synthetic-safe suite. |
| Sensitive-data and secret boundary | Ready for the recorded baseline | Layered working-tree and reachable-history checks pass on `e621537`; repeat after later code changes. |
| Name and brand | Ready for source publication | BlueMinutes is selected, the preliminary collision screen and independence language are recorded, and no formal trademark clearance is claimed. |
| Demonstration | Optional strengthening | A synthetic or already-public demo can improve the application but is not an official form prerequisite. |
| Public maintenance evidence | Ready | Commit history, tests, Issues, Pull Requests, roadmap, and governance are public; contributor-sized Issues can strengthen the application later. |
| Form narratives | Draft complete | Recount in the live form and verify every factual statement. |
| Requested benefit | Six months of ChatGPT Pro with Codex, plus API credits | Leave Codex Security unselected; no trusted-access dependency remains. |

## Submission gate

The current official form requires a public GitHub profile, public repository,
valid ChatGPT-account email, maintainer role, OpenAI Organization ID, and
truthful answers. BlueMinutes should submit once those official fields and the
following repository-truth checks are complete:

- the GitHub profile is public;
- the applicant has a valid ChatGPT account, uses the account-associated email,
  and has the required OpenAI Organization ID ready for the form;
- the repository is public and resolves from signed-out and anonymous clients;
- Apache License 2.0 and third-party notices are visible;
- source builds from documented instructions and CI passes on `main`;
- no credential, signing material, private meeting data, internal document,
  transcript, briefing, user database, workspace, or log is present in the
  working tree or reachable history;
- the README objectively documents the project, source-only alpha status,
  current limitations, and independence from the United Nations, United
  Nations entities, and governments;
- the source-only alpha status, roadmap, and recent maintenance evidence are
  visible; and
- any screenshots or demo submitted with the application use synthetic or
  already-public material only.

A polished demo, contributor-sized Issues, and outside feedback would strengthen
the case but are not represented as official prerequisites and should not delay
an otherwise truthful application.

## Application strategy

BlueMinutes is new and pre-release, so this application must not imply broad
adoption or invent stars, downloads, users, testimonials, or institutional
support. The official program expressly invites maintainers to explain a
project's ecosystem importance when it does not neatly fit the usual adoption
signals. The strongest truthful case is therefore:

1. an underserved public-interest workflow grounded in firsthand
   multilateral-diplomacy expertise;
2. a clear distinction from generic speech-to-text tools;
3. concrete active-maintenance evidence, including the synthetic-safe test
   suite, CI, threat model, security remediation, and contributor governance;
4. reusable engineering patterns for privacy-sensitive, evidence-linked AI;
5. a credible solo-maintainer burden that Codex can materially reduce; and
6. strict separation from any United Nations or government endorsement.

See [Open-source readiness evidence](OPEN_SOURCE_READINESS.md) for the exact
repository proof supporting these statements.

## Form entries

### Role

Primary maintainer

### Why does this repository qualify?

485 characters; recount in the live form before submission and refresh the
test count if it has changed.

```text
BlueMinutes is an actively maintained public-interest macOS OSS project built from firsthand multilateral-diplomacy expertise. Unlike generic speech-to-text tools, it supports long multilingual meetings through reviewable transcripts, position analysis, and evidence-linked briefs. Its 248-test synthetic-safe suite, typed provenance, 100% segment-coverage gates, human review, local-first processing, and provider routing offer reusable patterns for privacy-sensitive, high-stakes AI.
```

### Interested in

- API credits for my project

The six-month ChatGPT Pro subscription is a stated benefit for selected
maintainers and has no separate checkbox in the current form. Leave Codex
Security unselected; select API credits as an additional benefit.

### How will you use API credits for your project?

483 characters; recount in the live form before submission.

```text
I will use credits for OSS maintenance: PR review, issue triage, security fixes, release checks, and regression evaluation with synthetic/public fixtures. Maintenance is unusually time- and token-intensive: BlueMinutes combines long-context multilingual AI, provenance, deterministic coverage, macOS integration, and provider routing. Future work will evaluate optional, policy-reviewed integrations with documented public UN data APIs. No confidential meeting material will be used.
```

### Anything else we should know?

477 characters; recount in the live form before submission.

```text
I am the solo maintainer. My work involves multilateral diplomacy in the UN ecosystem. Turning hours of multilingual meetings into accurate, reviewable briefs is a recurring pressure point for delegations, UN staff, and civil-society teams. BlueMinutes is independent—not an official UN or government product—and contains no confidential meeting data. Six months of ChatGPT Pro with Codex is the primary support I am seeking; API credits would complement it for OSS automation.
```

### Lower-disclosure alternative

449 characters; lower-disclosure alternative. Recount in the live form before
submission.

```text
I am the primary maintainer. BlueMinutes grew from firsthand experience with a recurring multilateral-diplomacy pressure point: small delegations and civil-society teams must follow hours-long multilingual meetings and produce accurate, evidence-linked briefs with limited staff. It is my independent personal OSS project—not an official UN or government product. Codex helps a domain expert without a large engineering team maintain it responsibly.
```

## Repository description

```text
Local-first open-source macOS workbench for evidence-linked transcription, translation, multilateral position analysis, and briefing generation.
```

Suggested GitHub topics:

```text
macos swift transcription multilingual meeting-notes local-first privacy provenance multilateral briefing ai-assistant
```

Avoid `united-nations`, agency names, or other topics that could imply official
affiliation.

## Final form preparation

Enter first name, last name, account-associated email, GitHub username,
repository URL, and OpenAI Organization ID directly in the form. Do not commit
those private account details to the repository. Immediately before submitting:

1. open every public URL in a signed-out browser session;
2. confirm the profile and repository are public and the applicant is visibly
   the primary maintainer;
3. replace the test count if the public CI result differs from 248;
4. recount all narrative fields in the live form;
5. confirm no wording implies adoption, endorsement, official UN status, or a
   currently implemented UN data API integration; and
6. save a private copy of the exact submitted text and submission date.

## Evidence to strengthen before submission

- Keep the reproducible build instructions and passing public CI current.
- Screenshots or a short demo using synthetic or public material.
- A roadmap, current milestone, and several well-defined GitHub Issues.
- Contribution, code-of-conduct, support, security, maintenance, backup, and
  release documentation.
- A documented threat model and evidence-integrity architecture.
- Golden tests using synthetic/public fixtures only.
- Documentation of local/provider routes and privacy controls.
- Examples that show evidence links, uncertainty, quarantine, and human review.
- A visible record of maintenance: meaningful commits, resolved Issues, and
  reviewed Pull Requests.
- Honest early-user feedback when available. Do not manufacture stars,
  downloads, usage numbers, or testimonials.

## Claims to avoid

Do not claim that everyone at the UN needs the project; that the UN, a
government, or OpenAI supports or endorses it; that open source guarantees
security; that thousands already use it; or that adoption is broad without
verifiable repository or usage evidence.

Prefer: “built from firsthand experience with a recurring workflow problem,”
“potential users include delegations, international-organization staff,
researchers, and civil-society teams,” and “open source enables independent
review of privacy, provenance, and model-routing decisions.”
