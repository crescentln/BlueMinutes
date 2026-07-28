# URL and UN Ingestion Design

## Current authorized path

BlueMinutes currently accepts one exact visible `https://webtv.un.org/...` URL
for metadata inspection. The application:

- normalizes and binds authorization to the exact visible URL;
- permits only the reviewed host/path boundary;
- fetches bounded HTML metadata;
- treats page text as untrusted data;
- does not download media;
- does not scrape arbitrary hosts;
- does not treat page text as instructions; and
- consumes authorization after the attempt.

This is implemented by the UN Web TV contracts, media source, and
`UNWebTVMetadataView`. ADR-0013 remains binding.

## UN Web TV media

Metadata success does not grant rights or a stable media API. Before adding
media ingestion, verify:

- an official supported endpoint or user-provided local file;
- rights and terms for the intended content;
- redirect, host, MIME, size, duration, and content-integrity checks;
- bounded streaming to application-owned staging;
- cancellation and partial-file cleanup;
- exact source URL and digest provenance; and
- no execution of page-provided commands or filenames.

Absent that evidence, the safe path is metadata plus user-selected local media.

## UN transcripts and official records

UN automatic transcript, BlueMinutes local/remote STT, and an official meeting
record are separate source types:

- **UN automatic transcript:** machine source, retained verbatim;
- **BlueMinutes STT:** derived from exact canonical audio and route snapshot;
- **official record:** authoritative document source, not assumed verbatim
  speech;
- **human edits:** new local revision with editor provenance.

The app may compare them but never overwrite one with another.

## ODS PV/SR and documents

Official PV/SR documents require a dedicated source adapter with exact document
symbol, language, revision/publication metadata, HTTPS allowlist, MIME/size
limits, digest, and terms review. Document authority does not retroactively
change transcript provenance.

## Generic URL

Generic URL detection remains P2. If implemented, a parser may suggest
candidates but cannot:

- bypass the host allowlist;
- execute scripts or commands from content;
- choose an authenticated/private resource silently;
- download unbounded media;
- infer legal authorization; or
- pass a whole page to a model by default.

AI-assisted detection operates on bounded sanitized metadata and returns a
proposal requiring visible user confirmation.

## YouTube and downloaders

No downloader or external executable is approved. Adding one requires license,
signature, sandbox, update, subprocess, rights, size, and rollback review under
ADR-0008.
