## Verdict

Phase 4 is implemented. All three success criteria pass, verified by reading `src/mcp.rs`, `src/mcp/tools.rs`, `src/mcp/tests.rs` and running the suite (228 passed, 0 failed).

Caveat on evidence: the working tree is **post-Phase-5**. `src/mcp.rs:13-15` and `src/mcp.rs:155-166` differ from the Phase 4 diff (`is_no_match` was a `Display` string match at diff line 188-190; it is now a typed downcast). Most per-tool tests in `src/mcp/tests.rs:359-658` are Phase 5 additions, not in this diff.

## Success criteria

| Criterion | Result | Evidence |
|---|---|---|
| `tools/list` returns all 16 tools, non-empty descriptions | pass | 16 `#[tool]` methods in one `#[tool_router]` block, `src/mcp.rs:508-796`; asserted by `tool_router_registers_all_sixteen_tools_with_descriptions`, `src/mcp/tests.rs:118-152` (passes). Verified via `router.list_all()`, not a live `initialize` handshake. |
| `person_lookup {person:"scott"}` == `persona whois scott --json` | pass (record), envelope differs | `person_lookup_result` `src/mcp.rs:229-244` uses the same `resolve_people` path as `whois::run` `src/commands/whois.rs:21`; test `src/mcp/tests.rs:159-192` asserts record equality. `whois --json` single-match emits a bare object (`src/output.rs:173`); the tool emits a 1-element array. |
| No-match → `CallToolResult::error`, not empty success, not `McpError` | pass | `no_match_error` `src/mcp.rs:170-174`, routed by `resolve_or_recover` `src/mcp.rs:179-190`; test `src/mcp/tests.rs:194-218`. |
| Request structs in `src/mcp/tools.rs` with `JsonSchema` + per-field `schemars(description)` | pass | `src/mcp/tools.rs:74-1241` (11 structs + `GroupBy`), every field annotated. |
| Single-target multi-match → `disambiguation_error` | pass | `require_single` `src/mcp.rs:195-206`, `disambiguation_error` `src/mcp.rs:211-225`; applied only to `chain`/`manager`/`github_username` (`src/mcp.rs:292, 343, 362`); test `src/mcp/tests.rs:237-258`. |
| Per-tool DEBUG entry logs with params | pass | `src/mcp.rs:516, 528, 551, 577, 600, 622, 644, 666, 679, 714, 726, 749, 766, 775, 784, 793`. |
| `McpError` reserved for malformed input / internal | partial — see D1 | `invalid_params` for bad month `src/mcp.rs:447-448`; but all API errors → `internal_error` `src/mcp.rs:73-76`. |
| `headcount` is one tool with a `group_by` enum | pass | `src/mcp.rs:712-717`, `GroupBy` `src/mcp/tools.rs:1186-1219`. |
| Four narrow `list_*` tools | pass | `src/mcp.rs:515, 774, 783, 792`. |

## Deviations

**D1. Mid-session Persona 401 returns a protocol `McpError`, not a tool-level error.** — unacceptable (spec violation, not yet fixed)
Doc, "Other edge cases": a 401 is "returned as a `CallToolResult::error` for that one call". `PersonaClient` maps 401 to a plain eyre error (`src/api/mod.rs:73-75`), which every tool funnels through `query_err` → `McpError::internal_error` (`src/mcp.rs:73-76`). The transport does stay alive (that half of the doc's "relay per-call, keep the transport up" holds), but the LLM gets a protocol error instead of a readable, re-callable result. No test covers this path.

**D2. `is_no_match` shipped as a `Display` string match in this phase.** — was unacceptable, now fixed
Phase 4 diff line 188-190: `err.to_string().contains("No employee found")`. The doc's example code (doc:224) assumed `resolve_people` returns `Ok(vec![])`; it actually returns `Err` (`src/api/resolve.rs:145-157`), so a seam was needed — but the string check is the footgun `rust.md` forbids. Phase 5 replaced it with a typed `NoMatch` downcast (`src/mcp.rs:164-166`, `src/api/resolve.rs:14-25`), and all `resolve_people` zero-match paths are typed (`resolve.rs:93, 153`); the untyped `eyre!` at `resolve.rs:119` is in `single_result`, reachable only via `resolve_person`, which the MCP never calls.

**D3. `manager` and `github_username` return `ManagerResult`/`GithubResult`, not the doc's `Employee` / "username string(s)".** — acceptable
`src/mcp.rs:347, 366` call `manager_info` (`src/commands/manager.rs:18-24`) and `github_info` (`src/commands/github.rs:18-24`). This matches what `persona manager --json` / `persona github --json` emit, which is the stronger consistency constraint.

**D4. `reports` returns a flat `Vec<Employee>`, not a tree.** — acceptable
`src/mcp.rs:265-276` drops the `(depth, is_manager)` tuple fields. Identical to the CLI's JSON branch (`src/output.rs:263-266`), so depth is table-only there too. Doc table said "org tree"; the doc's own Data Model (doc:142) says person tools return `Vec<Employee>`.

**D5. `hired.from` is optional (default `2000-01-01`); doc table lists it required.** — acceptable
`src/mcp.rs:733`, `src/mcp/tools.rs:1224`. Mirrors `cli.rs:204` (`default_value = "2000-01-01"`).

**D6. `okta_issuer` field + `run_blocking_with_token` added beyond the doc's struct/bridge spec.** — acceptable
`src/mcp.rs:51, 92-121`. The doc requires `whoami` to hit Okta userinfo with the same token (doc:283-285) but its struct definition (doc:171-178) omits the issuer; this is the minimum needed to satisfy it. Self-disclosed at `src/mcp.rs:78-84`.

**D7. Two `commands::` helpers widened to `pub(crate)`.** — acceptable
`src/commands/reports.rs:114`, `src/commands/teammates.rs:59`. Directly serves the doc's "tools call one layer below `commands::*::run()`" (doc:56-57) and reuses rather than duplicates.

**D8. `reports.depth` is `Option<usize>`; the CLI uses `NonZeroUsize`.** — acceptable, minor
`src/mcp/tools.rs:1091` vs `src/cli.rs:122`. `depth: 0` is schema-legal and yields root-only (`src/commands/reports.rs:163`) rather than a validation error. No crash.

**D9. `anniversaries` skips the CLI's `sort_employees` pre-pass.** — acceptable, minor
`src/mcp.rs:453` vs `src/commands/anniversaries.rs:118`. `filter_anniversaries` sorts by tenure desc / name asc internally (`anniversaries.rs:55`); only exact ties on both keys could order differently from the CLI.
