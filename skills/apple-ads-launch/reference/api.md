# REST fallback

Without the AppGoat MCP server, call the API directly. Base URL `https://api.appgoat.ai/v1`,
header `x-api-key: $APPGOAT_API_KEY` (create a key at https://dash.appgoat.ai). Responses are
`{ "data": …, "meta": { "credits_used", "credits_remaining", … } }`; errors are
`{ "error": { "code", "message", "hint", "approve_url"? } }` - read `hint`.

| MCP tool | REST call |
|---|---|
| `list_connections` | `GET /connections?provider=apple_ads` (free) |
| `read_connection` view=campaigns | `GET /connections/{id}/ads?view=campaigns` |
| `read_connection` view=suggestions | `GET /connections/{id}/ads?view=suggestions&app=<adam id>&terms=a,b&countries=us` |
| `read_connection` view=popularity | `GET /connections/{id}/ads?view=popularity&terms=a,b&countries=us` |
| `get_app` / `get_competitors` / `get_app_keywords` | `GET /apps/{app}`, `GET /apps/{app}/competitors`, `GET /apps/{app}/keywords` |
| `keyword_research` | `GET /keywords?qs=term1,term2&store=apple&country=us` |
| `propose_action` | `POST /actions` with `"dry_run": true, "source": "playbook:apple-ads-launch"` (free) |
| `apply_action` | `POST /actions/{id}/approve` (1 credit when applied) |

Action params:

- `apple_ads.campaign.create` `{ app, name, countries: ["US"], daily_budget, placement?: "APPSTORE_SEARCH_RESULTS", max_daily_budget? }`
  → result `{ campaign: { id, status: "PAUSED", … } }`. Manual CPT, in the ad account's currency; always PAUSED.
- `apple_ads.adgroup.create` `{ campaign_id, name, default_bid, search_match?: false, status?: "ENABLED", start_time? }` → `{ ad_group: { id, … } }`.
- `apple_ads.keyword.add` `{ campaign_id, ad_group_id, keywords: [{ text, match_type: "EXACT", bid? }] }` (≤ 200).
- `apple_ads.negative.add` `{ campaign_id, ad_group_id?, keywords: [{ text, match_type: "EXACT" }] }`.
- `apple_ads.campaign.update` `{ campaign_id, status?: "ENABLED"|"PAUSED", daily_budget?, countries?, name? }`.

Actions that can raise spend (enabling, a higher budget or bid, new countries, Search Match on)
have `diff.spend_increase: true`. They are approved like any action: `POST /actions/{id}/approve`
with an API key applies them when the org lets agents approve, otherwise it returns 403 with the
`approve_url` for a person. Enabling a campaign is never auto-applied by approval rules.

```bash
CON=con_…
# Create the category campaign (dry run), then approve it
ID=$(curl -s -H "x-api-key: $APPGOAT_API_KEY" -H "content-type: application/json" https://api.appgoat.ai/v1/actions \
  -d '{"type":"apple_ads.campaign.create","connection":"'$CON'","dry_run":true,"source":"playbook:apple-ads-launch",
       "params":{"app":"6831596058","name":"Hush - Category - US","countries":["US"],"daily_budget":15,"max_daily_budget":30}}' | jq -r .data.id)
curl -s -X POST -H "x-api-key: $APPGOAT_API_KEY" "https://api.appgoat.ai/v1/actions/$ID/approve" | jq '.data.result.campaign.id'
```
