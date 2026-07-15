#!/usr/bin/env python3
"""Build the page-data JSON that the archetype report template embeds.

Consumes the output of cluster-archetypes.py (per-user rows with cluster +
PCA coords) plus an analyst-authored archetypes file (names/definitions/colors
keyed by cluster index), and emits a single compact JSON blob:

  - meta         : date range, totals, k / silhouette
  - aggregates   : exact org-level rollups (by model, by product, cache/output
                   efficiency, and volume concentration) computed here so the
                   template never has to recompute weighted ratios in JS
  - archetypes   : the authored list, passed through verbatim
  - users        : one compact record per user (short keys to keep the blob
                   small when embedded), including the full per-model breakdown

Naming archetypes from centroids is a judgment step, so the archetype list is
an INPUT, not derived here. Run describe-clusters.py against the clustered
JSON to read the centroids, then author the archetypes file. Stdlib only.
"""
import argparse
import json
import sys
from collections import Counter


def load_archetypes(path):
    archetypes = json.load(open(path))
    required = {"cluster", "name", "color", "definition"}
    for a in archetypes:
        missing = required - a.keys()
        if missing:
            raise SystemExit(f"archetype {a.get('name', a)!r} missing keys: {sorted(missing)}")
    return archetypes


def build_aggregates(users):
    total_tokens = sum(u["total_tokens"] for u in users)
    total = total_tokens or 1

    by_model = Counter()
    by_product = Counter()
    cache_read = 0
    cache_creation = 0
    output = 0
    uncached = 0
    for u in users:
        for m, t in u.get("models", {}).items():
            by_model[m] += t
        for p, t in u.get("products", {}).items():
            by_product[p] += t
        cache_read += u.get("cache_read_input_tokens", 0)
        cache_creation += u.get("cache_creation_1h", 0) + u.get("cache_creation_5m", 0)
        output += u.get("output_tokens", 0)
        uncached += u.get("uncached_input_tokens", 0)

    # Volume concentration: what share of all tokens the heaviest users account
    # for. Sorted desc so the cumulative walk answers "top N% of users hold what
    # share of tokens".
    sorted_tt = sorted((u["total_tokens"] for u in users), reverse=True)
    n = len(sorted_tt)

    def top_share(frac):
        k = max(1, round(n * frac))
        return sum(sorted_tt[:k]) / total

    concentration = [
        {"label": "Top 1%", "users": max(1, round(n * 0.01)), "share": top_share(0.01)},
        {"label": "Top 5%", "users": max(1, round(n * 0.05)), "share": top_share(0.05)},
        {"label": "Top 10%", "users": max(1, round(n * 0.10)), "share": top_share(0.10)},
        {"label": "Top 25%", "users": max(1, round(n * 0.25)), "share": top_share(0.25)},
    ]

    return {
        "byModel": [{"model": m, "tokens": t} for m, t in by_model.most_common() if t > 0],
        "byProduct": [{"product": p, "tokens": t} for p, t in by_product.most_common() if t > 0],
        "cacheReadRatio": cache_read / total,
        "cacheCreationRatio": cache_creation / total,
        "outputRatio": output / total,
        "uncachedRatio": uncached / total,
        "tokensPerRequest": total_tokens / sum(u["requests"] for u in users)
        if sum(u["requests"] for u in users)
        else 0,
        "concentration": concentration,
    }


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--clustered", required=True, help="cluster-archetypes.py output JSON")
    p.add_argument("--archetypes", required=True, help="analyst-authored archetypes JSON (list of {cluster,name,color,definition})")
    p.add_argument("--raw", help="raw pull-usage-report.py JSON, used only to derive the date range (falls back to clustered file if omitted)")
    p.add_argument("--output", required=True, help="output page-data JSON path")
    args = p.parse_args()

    clustered = json.load(open(args.clustered))
    archetypes = load_archetypes(args.archetypes)

    if args.raw:
        raw = json.load(open(args.raw))
        date_start = min(r["starting_at"] for r in raw)[:10]
        date_end = max(r["ending_at"] for r in raw)[:10]
    else:
        date_start = date_end = None

    clustered_users = clustered["users"]

    users = []
    for u in clustered_users:
        users.append(
            {
                "n": u["name"],
                "e": u["email"],
                "tt": u["total_tokens"],
                "req": u["requests"],
                "da": u["days_active"],
                "crr": round(u["cache_read_ratio"], 4),
                "ccr": round(u["cache_creation_ratio"], 4),
                "c1h": round(u["cache_1h_share"], 4),
                "outr": round(u["output_ratio"], 4),
                "dp": u["dominant_product"],
                "dps": round(u["dominant_product_share"], 4),
                "dm": u["dominant_model"],
                "products": dict(u["products"]),
                "models": dict(u.get("models", {})),
                "cl": u["cluster"],
                "x": round(u["pca_x"], 4),
                "y": round(u["pca_y"], 4),
            }
        )

    page_data = {
        "meta": {
            "dateStart": date_start,
            "dateEnd": date_end,
            "totalUsers": len(users),
            "totalTokens": sum(u["tt"] for u in users),
            "totalRequests": sum(u["req"] for u in users),
            "k": clustered["k"],
            "silhouette": round(clustered["silhouette"], 4),
        },
        "aggregates": build_aggregates(clustered_users),
        "archetypes": archetypes,
        "users": users,
    }

    with open(args.output, "w") as f:
        json.dump(page_data, f, separators=(",", ":"))

    m = page_data["meta"]
    print(
        f"users={m['totalUsers']} total_tokens={m['totalTokens']} "
        f"total_requests={m['totalRequests']} -> {args.output}",
        file=sys.stderr,
    )


if __name__ == "__main__":
    main()
