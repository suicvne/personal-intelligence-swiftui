# Intel (SwiftUI)

A small macOS app for [personal-intelligence](../personal-intelligence). It shows what the `intel` CLI
shows, through the HTTP API that intel's background service serves. It is deliberately small:

| Screen | Mirrors | You can |
|---|---|---|
| **Brief** | `intel brief` | mark observations seen, dismiss them, or mark them not useful |
| **Activity** | `intel events` | see what changed lately, by day: commits, notes and issues, and what intel learned (runs of similar changes fold into one row); open a note or an issue |
| **Proposals** | `intel proposals`, `intel proposal show/approve/reject` | approve or reject, **correct a proposal before approving it** (predicate, subject/object, type, name…), decide a whole group |
| **Tasks** | `intel tasks` | open the note or the issue, propose GitLab issues for a note's backlog |
| **Goals** | `intel goal list/add/state` | see goals by priority, with their target dates, what each prioritizes and when that last had activity, and their reminders; add one (statement, priority, target date, what it prioritizes); change its priority, date or what it prioritizes; mark it achieved, abandon or reactivate it |
| **Entities** | `intel entity list/show/add/rename/alias/status/describe/merge`, `intel relationship add/confirm/reject/end` | browse names, identifiers, file properties, relationships, activity; add an entity; rename it, add or remove names, set its status or description, relate it to another, merge a duplicate into it |
| **Ask** | `intel ask` | ask a question, see what the model looks up ("Looking up records changed on 2026-10-24…") and watch the answer being written (Esc stops it), open the cited notes, commits and issues |
| **Sources** | `intel source list/add/enable/disable`, `intel sync --source` | see each source's records, last sync and its error; add a folder of notes, a git repository or GitLab projects; enable, disable or sync one |

Settings (⌘,) also picks the model intel uses, from the models its LLM endpoint offers (like
`intel llm use`). Decisions, mentions and secrets (`intel secret set`) stay in the CLI.

## Run it

Requirements: macOS 14+, Xcode (or the Swift toolchain), and intel's background service running
(`intel service install` in the personal-intelligence repo).

```bash
scripts/build_app.sh && open build/Intel.app      # builds build/Intel.app; copy it to /Applications to keep it
# or: open this folder in Xcode and run the "Intel" scheme
```

On first launch the app asks for the API token. Click **Use the token of the intel on this Mac**
(it runs `intel api token`), or paste the output of `intel api token`. The token is stored in your
login Keychain; the server URL defaults to `http://127.0.0.1:8765`. If you ever host intel on another
machine, point Settings (⌘,) at that machine and use its token.

Shortcuts: ⌘R refresh, ⇧⌘S sync now, ⌘↩ approve, ⌘⌫ reject.

## Layout

```
Package.swift
Sources/IntelKit/            no UI, unit-tested
  api_models.swift           the API's JSON as Codable structs (mirrors intel/api.py)
  intel_client.swift         one async method per route; errors carry the server's message
  server_sent_events.swift   the event-stream parser for streaming routes (/api/ask/stream)
  connection_settings.swift  server URL (UserDefaults) + token (Keychain)
  formatting.swift           dates and links
  activity_feed.swift        the Activity screen's grouping: by day, similar changes folded into runs
Sources/Intel/               the SwiftUI app
  intel_app.swift            entry point, menus
  app_model.swift            shared state: connection, status, refresh signal
  content_view.swift         sidebar with counts, status footer, problem banner
  brief_screen.swift  activity_screen.swift  proposals_screen.swift  tasks_screen.swift  goals_screen.swift
  entities_screen.swift
  entity_editing.swift       adding and correcting entities (the sheets the Entities screen opens)
  ask_screen.swift  sources_screen.swift
  settings_view.swift  shared_views.swift
  debug_snapshot.swift       INTEL_SNAPSHOT=<dir>: save every screen and its layout numbers, then quit
Tests/IntelKitTests/
  decoding_tests.swift       decodes a real sample of every API response (Samples/), streamed ones too
  activity_feed_tests.swift  how the Activity screen groups and folds events
  live_tests.swift           optional: decodes your running intel's real data
Resources/AppIcon.icon       the app icon, an Icon Composer document (edit it in Icon Composer, in Xcode's
                             Developer Tools); it follows macOS 26's Default/Dark/Clear/Tinted icon styles
scripts/build_app.sh         release build -> build/Intel.app (icon compiled by actool, ad-hoc signed)
```

## Tests

```bash
swift test                                              # decoding tests against captured samples
INTEL_LIVE_TOKEN=$(intel api token) swift test --filter Live   # also against your running intel
```

The samples come from personal-intelligence's test suite (a fake world, never your data). After
changing the API, refresh them so the decoding tests keep both sides in step:

```bash
cd ../personal-intelligence
INTEL_EXPORT_SAMPLES=../personal-intelligence-swiftui/Tests/IntelKitTests/Samples \
    .venv/bin/python -m pytest tests/test_server.py -k sample
```

## Checking layout without a screen recording

`INTEL_SNAPSHOT=/tmp/intel-shots build/Intel.app/Contents/MacOS/Intel` opens the app, shows each
screen, saves `Brief.png`, `Proposals.png`, … plus `layout.txt` (where the title bar, the window
buttons and each scroll area sit, in points), then quits. The app draws its own window, so no
permission is needed, but translucent materials come out flat.

## Conventions

PascalCase for types and methods (`IntelClient.Proposals()`, `ProposalsScreen.Load()`), snake_case file
names, camelCase properties. SwiftUI's required names (`body`) stay as they are.
