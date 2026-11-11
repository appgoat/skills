---
name: apple-ads-launch
description: Sets up Apple Ads (Search Ads) search results campaigns for an app from scratch through the user's connected Apple Ads account - researches keywords (Apple's own suggestions and search popularity plus AppGoat keyword data), builds the standard Brand / Category / Competitor / Discovery structure with exact and Search Match ad groups, adds cross negatives so the campaigns don't bid against each other, and creates everything PAUSED for the user to review and enable. Every change is a dry run with a diff the user approves. Use when the user says "set up Apple Ads", "launch Search Ads for my app", "create Apple Ads campaigns", "start advertising on the App Store" or "which keywords should I bid on".
argument-hint: "<app> [country] [target_cpa]"
license: MIT
---

# Apple Ads launch

A first Apple Ads setup for one app in one or a few countries, with the structure most
successful search results accounts use:

| Campaign | Ad group | Match | Keywords | Purpose |
|---|---|---|---|---|
| Brand | Exact | EXACT | the app's name and misspellings | defend the brand, cheap installs |
| Category | Exact | EXACT | generic terms describing what the app does | the main volume |
| Competitor | Exact | EXACT | names of competing apps | conquest; usually pricier |
| Discovery | Search Match | Search Match on, no keywords | (Apple picks) | find new terms for the optimizer |

Each campaign gets the other campaigns' keywords as EXACT negatives, so a search triggers one
campaign only and the reports stay clean. Everything is created **PAUSED**; enabling is a separate
step that only a person can approve, so nothing spends until the user switches it on.

## When to use

- The user has an app on the App Store and connected their Apple Ads account in AppGoat
  (https://dash.appgoat.ai/connections, provider `apple_ads`). The app must be **linked** to the
  connection (connect with `apps: [<App Store id>]`, or link it later in the dashboard); apps
  without campaigns are not linked automatically.
- The Apple Ads account must be able to advertise the app (Apple Ads → Account Settings: the app's
  developer account linked, payment method set). Apple rejects campaigns otherwise.
- Not for optimizing running campaigns: use `apple-ads-optimizer` once there are 7–14 days of data.

## Inputs

- `app` (required): App Store id, URL or name of the user's app.
- `country` (optional): one or more storefronts, default `us`. Start with 1–3 countries that share
  a language; keywords are per language.
- `target_cpa` (optional): the most the user wants to pay per install. **Ask for it** and for a
  **total daily budget**. Without a target: suggest 1–3 × the app's monthly price for a subscription
  app, or 0.5–2 USD for a free app with ads, and get a yes.

Budget split of the total daily budget `B` (minimum 5 per campaign): Category 45%, Brand 15%,
Competitor 20%, Discovery 20%. Skip Competitor when the user doesn't want conquesting.

## Steps

Costs in AppGoat credits. Without the MCP, use the REST equivalents in [reference/api.md](reference/api.md).

1. `list_connections` {provider: "apple_ads"} - **0**. Pick an `active` connection whose linked
   apps include the app (`mode: actions` to create anything; `read_only` can only dry-run: say so).
   App not linked: ask the user to link it at https://dash.appgoat.ai/connections and stop.
2. `read_connection` {id, what: "ads", view: "campaigns"} - **1**. If the app already has campaigns,
   show them and ask whether to add the missing parts only (reuse names, skip existing campaigns).
3. `get_app` {app} - **1**: name, subtitle, category; `get_competitors` {app, country} - **1**: up to
   10 competitor names (keep the 5 most relevant).
4. Keyword research - **~10–30**:
   - `read_connection` {id, what: "ads", view: "suggestions", app, terms: [3–5 seed terms from the
     name / subtitle / category], countries} - **1**: Apple's suggestions for this app.
   - `get_app_keywords` {app, country} - **1** (terms the app already ranks for organically).
   - `read_connection` {id, what: "ads", view: "popularity", terms: [≤ 100 candidates], countries} -
     **1**: Apple's own popularity 1–100. Terms missing from the result have very low volume.
   - Optional for the top 20 category terms: `keyword_research` {terms, store: "apple", country} -
     **1 per term** for difficulty and the top apps (drop terms where the top apps do something else).
5. Build the plan (no calls): keyword lists per campaign (rules below), bids, budgets, negatives.
   Show it to the user as the plan table (see Output format) and get a yes before creating anything.
6. Create, in order, each as a dry run with `playbook: "apple-ads-launch"`, then `apply_action`
   after the user approved the plan - **0 per dry run, 1 per applied action**:
   1. `propose_action` {type: "ads.campaign.create", connection, params: {app, name:
      "<App> - Brand - <CC>", countries: ["US"], daily_budget, max_daily_budget: <B>}} → apply →
      the result's `campaign.id`. Same for Category, Competitor, Discovery.
   2. Per campaign `ads.adgroup.create` {campaign_id, name: "Exact" (Discovery: "Search Match"),
      default_bid, search_match: false (Discovery: true)} → apply → `ad_group.id`.
   3. `ads.keyword.add` {campaign_id, ad_group_id, keywords: [{text, match_type: "EXACT", bid}]}
      for Brand, Category and Competitor (≤ 200 per action).
   4. Cross negatives at campaign level: `ads.negative.add` {campaign_id, keywords: [{text,
      match_type: "EXACT"}]}: Discovery gets every keyword of the other three; Category gets the
      brand terms; Competitor gets the brand terms.
   Read the diff of each step before applying: a blocking check (a duplicate name, a storefront the
   app is not in) stops that item; fix the params and propose again.
7. Show the summary (see Output format) with the campaign ids. To go live the user enables each
   campaign: `propose_action` {type: "ads.campaign.update", params: {campaign_id, status:
   "ENABLED"}}. This is marked "can raise ad spend" and only a person can approve it: give the user
   the approve links (or they enable it in Apple Ads). Never try to approve it as the agent.
8. Suggest a check-in after 7 days with `apple-ads-optimizer`.

Budget: **~15–40 credits** for research + 1 per applied action (about 10–15 for a full setup).

## Keyword and bid rules

- **Brand:** the app name, the name without spaces, common misspellings, "<name> app". 3–10 terms.
- **Category:** generic terms that describe what the app does and that the user would be happy to
  win: Apple suggestions + popularity ≥ 20, plus the app's organic ranking terms that match its
  core use. 20–80 terms. Drop terms about another product, a different meaning, jobs, "free"
  piracy-style queries or a feature the app lacks.
- **Competitor:** names of the 3–8 most relevant competitors (popularity ≥ 10). Only with the user's
  agreement; never use a competitor's trademark in your own ad text (search results ads use the
  App Store listing, so this is about keywords only).
- **Default / keyword bid** (max CPT): start at `target_cpa × expected conversion rate`, with a
  conversion rate of 0.5 for Brand, 0.3 for Category, 0.15 for Competitor and 0.25 for Discovery.
  Round to 0.05 and keep within 0.20–5.00 (in the account currency). Category terms with
  popularity ≥ 60 get +20%, terms below 20 get −20%.
- **Daily budget per campaign** from the split above. Each daily budget must be at least 10 × its
  ad group default bid so the campaign can get enough taps a day; if not, reduce the number of
  campaigns (drop Competitor first) rather than the bids.
- Names: `<App> - <Brand|Category|Competitor|Discovery> - <CC>` (CC = the first country, or `INTL`).

## Output format

Plan (step 5):

```markdown
# Apple Ads launch: <App> (<countries>) - target CPA <T> <cur>, daily budget <B> <cur>

| Campaign | Daily budget | Ad group | Default bid | Keywords |
|---|---|---|---|---|
| Hush - Brand - US | 5.00 | Exact | 1.25 | hush, hush app, hush prayer (3) |
| Hush - Category - US | 15.00 | Exact | 0.75 | prayer app, daily prayer, bible verse (42) |
| Hush - Competitor - US | 5.00 | Exact | 0.40 | hallow, abide, pray.com (6) |
| Hush - Discovery - US | 5.00 | Search Match | 0.60 | (Search Match) |

Negatives: Discovery excludes all 51 keywords above; Category and Competitor exclude the brand terms.
All campaigns are created PAUSED. Reply "create it" or tell me what to change.
```

Final summary (step 7): the created campaigns with ids and status PAUSED, the keyword and negative
counts, any item that was blocked and why, the enable links, and "Run apple-ads-optimizer in 7 days."
Credits used: <sum>.

## Automate it

A launch is a one-off: run it in a chat so the user reviews the plan. Automate the weekly
follow-up with the `apple-ads-optimizer` playbook's GitHub Action or routine instead.
