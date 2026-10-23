# REST fallback

Without the AppGoat MCP server, call the API directly. Base URL `https://api.appgoat.ai/v1`,
header `x-api-key: $APPGOAT_API_KEY` (create a key at https://dash.appgoat.ai). Responses are
`{ "data": …, "meta": { "credits_used", "credits_remaining", "next_cursor", "usage"?, … } }`;
errors carry `error.code` and `error.hint`. `{app}` must be URL-encoded.

| MCP tool | REST call | Credits |
|---|---|---|
| `get_app` | `GET /apps/{app}?country=us&include=charts` | 1 (+1 per refresh) |
| `list_watches` | `GET /watches?kind=competitor_set&app={app}` (`meta.usage`: watched apps and keyword slots vs the plan) | 0 |
| `watch` (create) | `POST /watches` `{"kind": "competitor_set", "app", "competitors": [...], "countries": ["us"], "name"}` | 0 |
| `watch` (keyword) | `POST /watches` `{"kind": "keyword", "app", "terms": [...], "store", "countries": ["us"], "name", "settings": {"rank_move": 3}}` | 0 |
| `watch` (change) | `PATCH /watches/{id}` `{"competitors": [...]}` | 0 |
| `get_competitors` | `GET /apps/{app}/competitors?country=us&limit=10` | 1 |
| `get_events` | `GET /events?watch={id}&since=YYYY-MM-DD&limit=200` (next page: `&cursor=<meta.next_cursor>`) | 0 |
| `get_app_changes` | `GET /apps/{app}/changes?country=us&since=YYYY-MM-DD&limit=50` | 1 (+1 if refreshed) |
| `get_app_history` | `GET /apps/{app}/history?country=us&from=YYYY-MM-DD` | 1 |
| `get_app_keywords` | `GET /apps/{app}/keywords?country=us&max_rank=50&limit=200` | 1 |
| `get_reviews` | `GET /apps/{app}/reviews?country=us&since=YYYY-MM-DD&limit=100` | 1 per page |
| `get_insights` | `GET /apps/{app}/insights?country=us&since_days=30&versions=3` | 25 |
| `get_job` | `GET /jobs/{id}` | 0 |

Event types of a competitor watch: `new_version` (`payload.version`, `previous_version`,
`release_notes`), `metadata_change` (`payload.changes[] {field, old, new}`), `price_change`,
`featured`, `in_app_event`, `installs_milestone`, `rating_drop` (`rating`, `previous_rating`,
`drop`), `ratings_spike`, `review_spike`, `negative_review_spike` (`topic`, `sample[]`),
`chart_enter` / `chart_leave` (`chart`, `category`, `rank`). Keyword watch: `rank_change`
(`keyword`, `rank`, `previous_rank`) and `keyword_entrant`.

Change fields (`/changes`): version, release_notes, title, subtitle, description, screenshots, icon,
price, iap, iap_range, privacy, in_app_events, badges, featured, editors_choice, installs,
content_rating, developer.

```bash
APP=284882215; SINCE=$(date -u -d '7 days ago' +%F 2>/dev/null || date -u -v-7d +%F)
WATCH=$(curl -s -G -H "x-api-key: $APPGOAT_API_KEY" https://api.appgoat.ai/v1/watches \
  -d kind=competitor_set --data-urlencode "app=$APP" | jq -r '.data[0].id')
curl -s -G -H "x-api-key: $APPGOAT_API_KEY" https://api.appgoat.ai/v1/watches/$WATCH \
  | jq -r '.data.competitors[] | "\(.store) \(.app_id)"' | while read -r store id; do
    curl -s -G -H "x-api-key: $APPGOAT_API_KEY" "https://api.appgoat.ai/v1/apps/$id/changes" \
      -d store=$store -d country=us -d since=$SINCE -d limit=50 \
      | jq -r --arg id "$id" '.data[] | "\($id) \(.detected_at[0:10]) \(.field): \(.old|tostring|.[0:60]) → \(.new|tostring|.[0:60])"'
  done
```
