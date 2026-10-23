# Intel (SwiftUI)

A small macOS app for [personal-intelligence](../personal-intelligence). It shows what the `intel` CLI
shows, through the HTTP API that intel's background service serves. It is deliberately small:

| Screen | Mirrors | You can |
|---|---|---|
| **Brief** | `intel brief` | mark observations seen, dismiss them, or mark them not useful |
| **Proposals** | `intel proposals`, `intel proposal show/approve/reject` | approve or reject, **correct a proposal before approving it** (predicate, subject/object, type, name…), decide a whole group |
| **Tasks** | `intel tasks` | open the note or the issue, propose GitLab issues for a note's backlog |
| **Entities** | `intel entity list/show` | browse names, identifiers, file properties, relationships, activity |
| **Ask** | `intel ask` | ask a question and watch the answer being written (Esc stops it), open the cited notes, commits and issues |

Settings (⌘,) also picks the model intel uses, from the models its LLM endpoint offers (like
`intel llm use`). Everything else (renames, merges, sources, decisions, goals) stays in the CLI.

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
Sources/Intel/               the SwiftUI app
  intel_app.swift            entry point, menus
  app_model.swift            shared state: connection, status, refresh signal
  content_view.swift         sidebar with counts, status footer, problem banner
  brief_screen.swift  proposals_screen.swift  tasks_screen.swift  entities_screen.swift  ask_screen.swift
  settings_view.swift  shared_views.swift
  debug_snapshot.swift       INTEL_SNAPSHOT=<dir>: save every screen and its layout numbers, then quit
Tests/IntelKitTests/
  decoding_tests.swift       decodes a real sample of every API response (Samples/), streamed ones too
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
