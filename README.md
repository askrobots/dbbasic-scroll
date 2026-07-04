# DBBASIC Scroll

Scroll is the operator console for the [DBBASIC Object Server](https://github.com/askrobots/dbbasic-object-server) — a native Flutter app for the humans in a system where humans and AI agents build side by side.

The object server runs small versioned Python objects that serve as pages, APIs, workers, and forms, with records, schemas, identity, permissions, and a full audit trail behind a narrow admin surface. AI agents operate that surface over MCP; Scroll is the window you watch and steer it through.

## What it does

- **Objects** — browse, read, edit, run, and roll back live Python objects; watch execution logs and version history.
- **Collections & Records** — records browse/create/edit/delete with forms **generated from the schema form contract**: enum → dropdown, relation → record picker, date → date picker, required/defaults/validation rendered from the schema, nothing hardcoded.
- **Schemas** — inspect fields and versions, replace schemas, roll back to any version.
- **Identity** — users, accounts, sessions; set/remove passwords; email + password sign-in that mints a server session (no pasted deployment tokens required).
- **Changes** — the unified audit trail: every source, record, schema, file, and package change with actor and correlation id. When an AI agent builds something over MCP, this is where you watch it happen.
- **Stations, Daemon, Permissions, Files, Packages, API Explorer** — live server health and metrics, scheduler/queue state, permission policy, object file storage, package installs, and a raw request console with presets for the whole admin surface.

## Getting started

1. Run an [object server](https://github.com/askrobots/dbbasic-object-server) (local or remote).
2. `flutter run -d macos` (or build: `flutter build macos --release`).
3. Connect: enter your server URL, then either paste a deployment admin token or sign in with email + password.

Optional dev convenience: copy `.env.example` to `.env` to pre-fill the Connect screen. `.env` is gitignored — never commit it.

## Notes

- Admin screens honor the server's capability flags — anything the server hasn't enabled (source writes, package installs, backups) renders locked instead of pretending.
- Sessions expire server-side; Scroll detects the rejection and prompts you to sign in again.
- The optional Platform URL adds askrobots.com collections (contacts, tasks, invoices) alongside the object server.

Built almost entirely by AI agents coordinating over a shared feed, reviewed and driven by a human operator. The audit trail isn't a feature we added — it's how this app itself was built.

## License

MIT
