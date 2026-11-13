# Validation surfaces — catalogue

A **surface** is a place where a change is set up, observed working, or leaves a trace. The architect names the surfaces a change touches; the scout finds a route to each. Routes are examples: any command or tool that reaches the surface counts, and a surface missing from this list follows the same rule.

## Setup: what must be true before a check means anything

| Surface | Gives | Example routes |
|---|---|---|
| runtime | the app and its services running locally | dev server, compose file, a local function runner |
| test data | a known starting state and a login | seed script, fixtures, a test-account tool |
| flags and config | the change switched on, env vars present | flag CLI or API, env file check |
| time | states that only appear later (renewal, expiry) | clock control, time travel in the test-data tool |

## Observe: where the change shows

| Surface | Proves | Example routes |
|---|---|---|
| browser | the page works and looks right | browser CLI or MCP, a browser test runner |
| emulator | the mobile screen works (emulator or simulator) | `adb`, `xcrun simctl`, a mobile UI runner |
| cli | commands, builds, unit tests, types, lint | the repo's own scripts |
| api | endpoints answer correctly | `curl`, the project's client |
| database | the right rows are written, migrations apply | query client, migration dry-run |
| logs | nothing failed quietly | app logs, browser console, error tracker |

## Outbound: what the change sends out

| Surface | Proves | Example routes |
|---|---|---|
| tracking | the right events fire with the right properties | data layer read, tag preview, network capture |
| messages | email, SMS or push is sent and renders | local mail catcher, sandbox workspace |
| integrations | third-party calls and webhooks are correct | vendor sandbox, mock server, request capture |
| jobs | background work runs and finishes | job runner, queue inspector, manual trigger |
| pipelines | data models build and their tests pass | a build on a dev dataset, a query dry-run |
| content | a CMS change renders | draft preview |

## Quality: bars the change must still clear

| Surface | Proves | Example routes |
|---|---|---|
| visual | the build matches the approved prototype | screenshot diff |
| a11y and performance | no regression | accessibility and performance audits |
| security | no secret or vulnerable dependency added | secret scan, dependency audit |
| ci | what passes here passes in CI | the CI job run locally, a review environment |
| evidence | a record a reviewer can trust | screenshots, recordings, before/after captures |
