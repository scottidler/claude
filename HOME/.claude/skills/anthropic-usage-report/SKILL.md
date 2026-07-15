---
name: anthropic-usage-report
description: Pull Claude Enterprise Analytics API token usage and cost data (per-user, per-model, 5m/1h prompt cache tokens, org-wide totals) into a JSON or CSV file via the bundled pull-usage-report.py script. Use when the user asks to pull/export/report Tatari's (or any Claude Enterprise org's) Claude token usage, per-user Claude spend, enterprise usage report, cache hit tokens, or wants org-wide Claude cost/usage data as JSON/CSV — trigger even on vague phrasing like "how much are we spending on Claude" or "who's using Claude the most", not just requests that name the API or "per-user" explicitly. Also builds the interactive per-user usage-archetype dashboard from that data: k-means clustering of users into usage archetypes, then a data-driven HTML report published to marquee — trigger this whenever the user wants to cluster/segment Claude users, identify usage archetypes or personas, find power users, or build/publish the Claude usage dashboard, even on vague phrasing like "break our Claude users into groups" or "make the usage report". Requires an Analytics API key (owner-created, env var ANTHROPIC_ENTERPRISE_SPEND_REPORTING_API_KEY by default) — NOT a regular Console API key or Admin API key.
---

# Anthropic Enterprise Usage Report

Pulls data from the **Claude Enterprise Analytics API** (`https://api.anthropic.com/v1/organizations/analytics/*`) — org-wide engagement, per-user token usage, and cost data for Claude Enterprise organizations. This is a distinct API and key type from the regular Admin API — see `references/api-notes.md` for the full disambiguation if asked, or if a request comes back `403`/`401` in a way that suggests a key-type mismatch (also lists the valid `--group-by` dimensions per report type).

## Prerequisite

An Analytics API key (owner-created in claude.ai → Organization settings → API, `read:analytics` scope) must be set in an env var — default `ANTHROPIC_ENTERPRISE_SPEND_REPORTING_API_KEY`. **Never print or log this key's value.** If the env var isn't set, tell the user which var name is expected — don't guess or paste in a key.

## Running the script

The script has no external deps to resolve, so run it directly from this skill's own directory (or invoke it by its full bundled path if the current cwd is a different project):

```bash
python3 pull-usage-report.py [options]
```

No dependencies to install — stdlib only (`urllib`), works with a bare `python3`.

### Common invocations

Per-user token usage (default), last 30 days, JSON, broken down by model:

```bash
python3 pull-usage-report.py
```

Per-user usage as CSV, last 90 days:

```bash
python3 pull-usage-report.py --days 90 --format csv
```

Org-wide (not per-user) cost report for a specific range:

```bash
python3 pull-usage-report.py --report cost --start 2026-06-01T00:00:00Z --end 2026-07-01T00:00:00Z
```

Per-user cost, grouped by model and product:

```bash
python3 pull-usage-report.py --report user-cost --group-by model --group-by product --format csv
```

### Flags

| Flag | Default | Notes |
|---|---|---|
| `--report` | `user-usage` | `user-usage` (per-user tokens), `usage` (org-wide tokens), `user-cost`, `cost` |
| `--start` / `--end` | last `--days` → now | ISO 8601, e.g. `2026-06-01T00:00:00Z` |
| `--days` | 30 | Used only when `--start` is omitted |
| `--chunk-days` | 30 | Splits large ranges into multiple paginated requests, sidestepping any range-too-large API error |
| `--bucket-width` | `1d` | `1m` / `1h` / `1d` — usage reports only |
| `--group-by` | `model` | Repeatable — see `references/api-notes.md` for the full valid dimension list per report type |
| `--product` | (none) | Repeatable filter, e.g. `chat`, `claude_code` |
| `--format` | `json` | `json` or `csv` (CSV flattens nested fields like `cache_creation.ephemeral_5m_input_tokens` with dot-joined column names) |
| `--output` | auto-named in cwd | e.g. `enterprise-user-usage-2026-06-01-2026-07-01.json` |
| `--api-key-env` | `ANTHROPIC_ENTERPRISE_SPEND_REPORTING_API_KEY` | Override if the key lives under a different var name |
| `--limit` | 1000 (`user-usage`/`user-cost`); bucket-width cap (`usage`/`cost` — 31 for `1d`, 168 for `1h`, 1440 for `1m`) | Page size per paginated request. `usage`/`cost` are hard-capped server-side by bucket width — the script clamps automatically and warns on stderr if you pass a higher value explicitly |

The script paginates automatically (`has_more` / `next_page`) and prints only the record count + output path — never the API key or raw headers.

## Data notes

- Usage/cost data can lag up to ~24h and revise for up to ~30 days as late events reconcile. For stable historical totals, query ranges ending 30+ days ago.
- `user-usage` / `user-cost` return one row per org member (`actor.user_id` / `actor.email` / `actor.name`), filtered to seat users only.
- `usage` / `cost` (org-wide) return one row per **time bucket**, each holding a nested `results[]` array of per-group breakdown rows (e.g. per model) — the script auto-expands these into flat per-group rows carrying that bucket's `starting_at`/`ending_at`, so row counts and CSV columns come out uniform across all four report types. This nested shape is undocumented by Anthropic; confirmed by live testing 2026-07.
- Amount fields on cost endpoints are decimal-string cents (e.g. `"41280.000000"` = $412.80) — the script writes them through as-is; divide by 100 for dollars when analyzing.
- Rate limit is 60 req/min **per organization**, not per key — the script sleeps briefly between paginated pages.
- Large `user-usage`/`user-cost` pulls intermittently drop the connection mid-body with a transient `http.client.IncompleteRead` (reproducible on the bigger 30-day org-wide pulls, not a one-off). `fetch_page` retries up to `MAX_RETRIES` (5) with exponential backoff on `IncompleteRead`/`ConnectionError`/`TimeoutError`/`URLError`; a real `HTTPError` (4xx/5xx) is not retried and surfaces immediately.

## Archetype report pipeline

The scripts below turn a raw pull into the interactive usage-archetype dashboard (the kind published to marquee). Each stage is standalone and reusable; the one non-mechanical step is naming the archetypes.

1. **Pull** — `python3 pull-usage-report.py --report user-usage --group-by model --group-by product` → raw per-user/per-model/per-product rows (`enterprise-user-usage-*.json`).
2. **Aggregate** — `python3 aggregate-users.py <raw.json> user-summaries.json` → one summary row per user with derived cache/token/product ratios.
3. **Cluster** — `uv run cluster-archetypes.py user-summaries.json clustered-users.json` → k-means over the ratio features (sweeps `--k-min`..`--k-max`, picks by silhouette), adding a `cluster` id and 2D PCA coords per user, plus `cluster_centroids`/`cluster_sizes`/`feature_names`. This is the only stage run with `uv run` (not `python3`): it needs numpy/scikit-learn, which uv provisions into an ephemeral venv — every other stage is stdlib-only.
4. **Describe & name** *(judgment step)* — `python3 describe-clusters.py clustered-users.json` prints each cluster's size, centroid (in real feature units), and heaviest members. Read that, then author an **archetypes JSON** — a list of `{cluster, name, color, definition}` (see `archetypes.example.json`; `color` is one of `blue`/`aqua`/`yellow`/`green`/`violet`/`red`/`magenta`/`orange` — the template's 8-slot validated categorical palette, so target **k ≤ 8** unless you add a slot to the template's CSS `:root` vars + `COLOR_VAR` map). Naming from centroids is analytical, so it is an authored input, never re-derived.
5. **Build page data** — `python3 build-page-data.py --clustered clustered-users.json --archetypes archetypes.json --raw <raw.json> --output page-data.json` → one compact JSON blob (`meta`, exact org-level `aggregates`, the authored `archetypes`, and compact per-user `users` rows including the per-model breakdown).
6. **Embed & publish** — substitute the page-data JSON for the `__PAGE_DATA__` placeholder in `archetype-report-template.html` (first replace every `<` in the JSON with its JSON unicode escape — a backslash followed by `u003c` — which `JSON.parse` decodes back to `<` and which can never form a `</script>` that breaks out of the tag; do NOT use the HTML entity `&lt;`, which a raw-text `<script>` element does not decode and which would corrupt any literal `<` in the data), then publish the result via `marquee:publish` (or `marquee:replace` to update an existing report). The template is fully data-driven — every tab (Overview, Archetypes, By model, By product, By volume tier, All users) renders from the embedded blob, nothing is hardcoded.

Validate the rendered HTML in headless Chrome before publishing (`google-chrome --headless=new --no-sandbox --dump-dom` and confirm the panels populated), and verify the *served* copy with `marquee:read` after publishing — a plain fetch of a marquee URL returns the Okta login page, not the post.
