# Which Anthropic reporting API is this?

Anthropic has two separate org-level reporting APIs. Don't confuse them.

| | Admin API (Usage & Cost) | Claude Enterprise Analytics API |
|---|---|---|
| Endpoint base | `/v1/organizations/usage_report/*`, `/cost_report` | `/v1/organizations/analytics/*` |
| Key type | Admin API key (`sk-ant-admin01-...`) | Analytics API key (opaque) |
| Created where | Claude Console → Settings → Admin keys | claude.ai → Organization settings → API |
| Who can create | Organization admin | **Primary owner only** |
| Breakdown | Per API key / workspace | **Per individual user** (`actor.user_id`/`email`/`name`) |
| Covers | Claude Platform (developer API) usage/cost | Claude Enterprise (claude.ai) engagement, adoption, usage, cost across chat/Claude Code/Cowork/etc. |

This skill's script (`pull-usage-report.py`) targets the **Analytics API** — it's the only one of the two that breaks usage down per enterprise user, which is what "enterprise report key" and "per every enterprise user" point to.

The two APIs' keys are **not interchangeable** — an Admin key 403s on `/analytics/*` and vice versa.

## Endpoints used

- `GET /v1/organizations/analytics/user_usage_report` — per-user token usage over time
- `GET /v1/organizations/analytics/usage_report` — org-wide token usage over time
- `GET /v1/organizations/analytics/user_cost_report` — per-user cost over time
- `GET /v1/organizations/analytics/cost_report` — org-wide cost over time
- `GET /v1/organizations/analytics/summaries` — org-level active-user summaries (not wired into the script)
- `GET /v1/organizations/analytics/users` — per-user activity/adoption, not token counts (not wired into the script)

## Auth

```
x-api-key: <analytics key>
anthropic-version: 2023-06-01
```

## Token fields on usage reports

- `uncached_input_tokens`
- `output_tokens`
- `cache_creation.ephemeral_5m_input_tokens`
- `cache_creation.ephemeral_1h_input_tokens`
- `cache_read_input_tokens`
- `total_tokens` (per-user endpoint only)

## Pagination

Cursor-based (`has_more` / `next_page`). **Cursors are bound to the exact query that issued them** — changing any filter/group_by/date-range param mid-sequence while reusing an old cursor returns 400. The script always issues a fresh cursor chain per date window, so this doesn't come up in normal use.

**`limit` is hard-capped for `usage`/`cost` (confirmed by live testing 2026-07, undocumented by Anthropic):** these two org-wide, time-bucketed endpoints reject `limit` above the bucket-width's max bucket count — `31` for `bucket_width=1d`, `168` for `1h`, `1440` for `1m` — with `HTTP 400 invalid_request_error: "limit must be at most 31 for bucket_width=\"1d\""`. This applies even to `cost_report`, which never accepts `bucket_width` as a request param — it buckets daily server-side regardless, so the `1d`/31 cap always applies there. `user-usage`/`user-cost` are **not** subject to this — they return one row per user for the whole queried window (not one row per bucket), so a `limit` of 1000+ works fine. The script auto-clamps and warns on stderr rather than erroring.

## Response shape: bucketed vs. flat

Confirmed by live testing 2026-07 — not documented by Anthropic:

- **`user-usage` / `user-cost`**: each item in `data[]` is already a flat row — one per user, with token/cost fields directly on it.
- **`usage` / `cost`**: each item in `data[]` is a **time-bucket wrapper** — `{starting_at, ending_at, results: [...]}` — where `results[]` holds the actual per-group (e.g. per-model) breakdown rows. The top-level item is *not* itself a usable data row. The bundled script expands `results[]` into flat rows (merging in the bucket's `starting_at`/`ending_at`) so JSON and CSV output are consistent across all four report types — don't skip this expansion if reimplementing against these two endpoints directly.

## Rate limit

60 requests/minute **per organization** (not per key), shared across all `/analytics/*` endpoints.

## Valid `group_by` dimensions

- `model` — supported on all four report types
- `product` — chat, claude_code, cowork, office_agent, claude_in_chrome, claude_design
- `rbac_group_id` — team-level rollups (accepts tagged `rbac_group_...` IDs or bare UUIDs)
- `token_type` — usage reports only: `uncached_input_tokens`, `output_tokens`, `cache_creation.ephemeral_5m_input_tokens`, `cache_creation.ephemeral_1h_input_tokens`, `cache_read_input_tokens`
- `inference_geo` — `global`, `us`, `not_available`
- `speed` — `standard`, `fast` (requires the `fast-mode-2026-02-01` beta header, not sent by the bundled script)
- `description` — cost endpoints only; response then includes parsed `model`/`inference_geo` fields
