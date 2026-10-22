# AppGoat playbooks

Open-source [Agent Skills](https://agentskills.io) for App Store and Google Play work, backed by
live store data from the [AppGoat](https://appgoat.ai) MCP server: apps, reviews, keyword ranks,
charts, competitors and listing changes for both stores.

> Intended home: `github.com/appgoat/skills` (not published yet).

| Playbook | What it does | Credits per run |
|---|---|---|
| [`app-audit-lite`](skills/app-audit-lite/SKILL.md) | Quick audit of one app: listing, ratings trend, complaints, keyword ranks, competitors, prioritized fixes | ~25–40 |
| [`find-app-ideas`](skills/find-app-ideas/SKILL.md) | Underserved niches: high search demand, weak incumbents, a complaint to build on | ~150–250 |
| [`aso-keywords-metadata-rewrite`](skills/aso-keywords-metadata-rewrite/SKILL.md) | Keyword research and a title / subtitle / keyword field / description rewrite within store limits | ~40–80 |
| [`reviews-to-github-issues`](skills/reviews-to-github-issues/SKILL.md) | Negative reviews → one deduplicated GitHub issue per problem, new reviews as comments | ~2–10 |

The free plan has 250 credits a month plus a free first audit; see [appgoat.ai/pricing](https://appgoat.ai/pricing).
Every tool result shows `credits_used` and `credits_remaining`.

Each skill folder has a `SKILL.md` (when to use, exact tool calls with their cost, decision rules,
output format, and an **Automate it** section with a GitHub Action and a Claude Code routine), a
`reference/api.md` with the REST equivalents, and helper scripts where useful.

## Requirements

- An AppGoat account ([dash.appgoat.ai](https://dash.appgoat.ai)). The hosted MCP server is
  `https://api.appgoat.ai/mcp` (OAuth sign-in, or an `x-api-key` header). Local alternative:
  `npx -y @appgoat/mcp` with `APPGOAT_API_KEY` set.
- `reviews-to-github-issues`: the [GitHub CLI](https://cli.github.com) (`gh auth login`) or the GitHub MCP server.
- Scripts run with `python3` and `bash`; no other dependencies.

## Install

### Claude Code

As a plugin (skills + the AppGoat MCP server in one step):

```text
/plugin marketplace add appgoat/skills
/plugin install appgoat-playbooks@appgoat
```

Then run `/mcp` to sign in to AppGoat. Use a playbook by asking for it ("audit my app
https://apps.apple.com/…") or by name, e.g. `/app-audit-lite https://apps.apple.com/us/app/id284882215 us`.

Manual alternative:

```bash
git clone https://github.com/appgoat/skills /tmp/appgoat-skills
cp -r /tmp/appgoat-skills/skills/* ~/.claude/skills/     # or .claude/skills/ in a project
claude mcp add --transport http appgoat https://api.appgoat.ai/mcp
```

### Claude.ai and Claude Desktop

1. Add the connector: Settings → Connectors → Add custom connector → URL `https://api.appgoat.ai/mcp`.
2. Add the skills: zip each skill folder (`cd skills && zip -r app-audit-lite.zip app-audit-lite`)
   and upload it in Settings → Capabilities → Skills.

Without uploading skills, the playbooks are also available as **prompts** of the AppGoat connector
(the "+" menu → AppGoat) and through its `list_playbooks` tool.

### Cursor

1. Add the MCP server to `.cursor/mcp.json` (or the global config):

   ```json
   { "mcpServers": { "appgoat": { "url": "https://api.appgoat.ai/mcp" } } }
   ```

2. Use the playbooks as MCP prompts (type `/` in the chat), or copy a `SKILL.md` into
   `.cursor/rules/<name>.mdc` to make it a rule the agent can apply.

### ChatGPT

Enable developer mode (Settings → Apps & Connectors → Advanced), add a connector with the URL
`https://api.appgoat.ai/mcp` and sign in. ChatGPT does not load skill folders: ask it to "use the
AppGoat list_playbooks tool and run the reviews-to-github-issues playbook", which returns the
playbook text from the server.

### Other agents

Any agent that reads Agent Skills (a folder with `SKILL.md`) can use these folders as is. Any MCP
client gets the same playbooks as prompts from the AppGoat server.

## Automate

Every playbook ends with an **Automate it** section:

- a GitHub Action (`anthropics/claude-code-action@v1`) that installs these skills, starts the AppGoat
  MCP server with `APPGOAT_API_KEY` from repository secrets, and runs the playbook on a schedule;
- a Claude Code routine prompt to paste into `/schedule`.

Add the repository secrets `ANTHROPIC_API_KEY` and `APPGOAT_API_KEY` first.

### On events

Instead of a schedule, a playbook can run when AppGoat sees something happen. Create a **watch**
(`POST /v1/watches`, free) on an app, competitors or keywords; significant changes become **events**
(`new_version`, `metadata_change`, `rating_drop`, `negative_review_spike`, `rank_change`, …). Events
reach an agent in two ways:

- **GitHub Action:** a `kind: github` webhook (`POST /v1/webhooks`, paid plans) makes AppGoat call
  `repository_dispatch` with `event_type: appgoat.<type>` and the event as `client_payload`; a
  workflow `on: repository_dispatch` runs the playbook with Claude Code.
- **Claude Code routine:** `/schedule` or `/loop` polls `GET /v1/events` (MCP `get_events`, free, every
  plan) with `since=` and runs the playbook when something new shows up.

| Playbook | Event recipes |
|---|---|
| `reviews-to-github-issues` | [`events/`](skills/reviews-to-github-issues/events/README.md): `negative_review_spike`, `review_spike`, `rating_drop` → workflow [`appgoat-events.yml`](skills/reviews-to-github-issues/events/appgoat-events.yml), polling routine with [`poll_events.sh`](skills/reviews-to-github-issues/scripts/poll_events.sh) |

Events and deliveries cost no credits; the playbook run they start costs what it costs on a schedule.

## Layout

```
.claude-plugin/marketplace.json   Claude Code marketplace: plugin "appgoat-playbooks" (skills + MCP server)
.mcp.json                         AppGoat MCP server for clients that read project MCP config
skills/<name>/SKILL.md            the playbook (frontmatter: name, description, argument-hint)
skills/<name>/reference/api.md    REST fallback for the tool calls
skills/<name>/scripts/            helpers (python3 / bash)
skills/<name>/events/             event recipes: a repository_dispatch workflow and polling routines
```

The AppGoat MCP server bundles these playbooks as MCP prompts at build time. Prompt arguments come
from `argument-hint` (`<x>` required, `[x]` optional), and the **Automate it** section is left out
of the prompt text.

## Contributing

Keep the section order (`When to use`, `Inputs`, `Steps`, `Decision rules`, `Output format`,
`Automate it` last), state the credit cost of every call, and test scripts with `python3` / `bash`.

## License

MIT
