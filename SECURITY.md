# Security Policy

## Supported versions

The project is currently an internal alpha. Security fixes are applied to the
latest `main` revision only. No public binary release is supported yet.

## Reporting a vulnerability

Do not open a public Issue for a vulnerability or include sensitive meeting
material, credentials, exploit payloads containing private data, or user
workspace contents in a report.

Use GitHub's private vulnerability reporting or a private Security Advisory
for this repository when available. If that channel is unavailable, contact
the primary maintainer through the GitHub profile without including sensitive
details, and request a private reporting channel.

Include only the minimum safe information needed to reproduce the issue:

- affected commit or version;
- affected component and security boundary;
- impact and realistic preconditions;
- synthetic reproduction steps or a minimal proof of concept;
- whether credentials, user data, evidence lineage, or persistent storage may
  be affected;
- suggested mitigation, if known.

You should receive an acknowledgement within seven calendar days. Timelines
for validation, remediation, and disclosure depend on severity, reproducibility,
and maintainer capacity. Please allow coordinated remediation before public
disclosure.

## Project security boundaries

- Meeting content is local by default and leaves the device only through an
  explicitly approved route.
- Secrets belong in macOS Keychain and are never stored in source control,
  ordinary configuration, telemetry, or task logs.
- AI providers operate behind application-owned interfaces and never query
  database tables directly.
- Provider output is untrusted. Coverage omissions require independent
  application verification, and derived analysis/briefing content requires the
  applicable explicit human review before consequential use.
- Persistent writes are confined to the selected workspace through the Storage
  Service; long-running operations use the Task Manager.
- Telemetry is disabled by default and cannot contain meeting or transcript
  content, credentials, titles, filenames, or identifiable meeting metadata.

See `docs/SECURITY_PRIVACY.md` and `docs/THREAT_MODEL.md` for the detailed
model. Open source enables review; it does not guarantee that the software is
secure or appropriate for classified, legally privileged, or otherwise
restricted material.

## Public test data

Security reports, tests, CI, screenshots, and demonstrations must use synthetic,
anonymized, explicitly licensed, or already-public fixtures. Never submit real
diplomatic records or user workspaces to this repository.
