#!/usr/bin/env python3
"""Aggregate per-user-per-model-per-product-per-day usage rows into one
summary record per user, with derived cache/token/product ratios used for
archetype clustering. Stdlib only.
"""
import argparse
import collections
import json
import math
import sys


def main():
    p = argparse.ArgumentParser()
    p.add_argument("input")
    p.add_argument("output")
    args = p.parse_args()

    rows = json.load(open(args.input))

    by_user = {}
    for r in rows:
        actor = r["actor"]
        uid = actor["user_id"]
        u = by_user.setdefault(
            uid,
            {
                "user_id": uid,
                "name": actor["name"],
                "email": actor["email"],
                "total_tokens": 0,
                "uncached_input_tokens": 0,
                "output_tokens": 0,
                "cache_read_input_tokens": 0,
                "cache_creation_1h": 0,
                "cache_creation_5m": 0,
                "requests": 0,
                "days": set(),
                "products": collections.Counter(),
                "models": collections.Counter(),
            },
        )
        total = r.get("total_tokens")
        if total is None:
            total = (
                r.get("uncached_input_tokens", 0)
                + r.get("output_tokens", 0)
                + r.get("cache_read_input_tokens", 0)
                + r.get("cache_creation", {}).get("ephemeral_1h_input_tokens", 0)
                + r.get("cache_creation", {}).get("ephemeral_5m_input_tokens", 0)
            )
        u["total_tokens"] += total
        u["uncached_input_tokens"] += r.get("uncached_input_tokens", 0)
        u["output_tokens"] += r.get("output_tokens", 0)
        u["cache_read_input_tokens"] += r.get("cache_read_input_tokens", 0)
        u["cache_creation_1h"] += r.get("cache_creation", {}).get(
            "ephemeral_1h_input_tokens", 0
        )
        u["cache_creation_5m"] += r.get("cache_creation", {}).get(
            "ephemeral_5m_input_tokens", 0
        )
        u["requests"] += r.get("requests", 0)
        u["days"].add(r["starting_at"][:10])
        u["products"][r.get("product") or "unknown"] += total
        u["models"][r["model"]] += total

    summaries = []
    for u in by_user.values():
        total = u["total_tokens"] or 1  # guard div-by-zero; total==0 users excluded below
        cache_creation_total = u["cache_creation_1h"] + u["cache_creation_5m"]
        dominant_product, dominant_product_tokens = (
            u["products"].most_common(1)[0] if u["products"] else ("unknown", 0)
        )
        dominant_model, dominant_model_tokens = (
            u["models"].most_common(1)[0] if u["models"] else ("unknown", 0)
        )

        # Shannon entropy over product token share, normalized to [0, 1] by
        # log(num categories actually observed org-wide) -- a diversity score,
        # not just a raw count, so a user split 50/50 across 2 products scores
        # higher than one split 90/10 across 2 products.
        product_shares = [v / total for v in u["products"].values() if v > 0]
        product_entropy = -sum(s * math.log(s) for s in product_shares if s > 0)

        summaries.append(
            {
                "user_id": u["user_id"],
                "name": u["name"],
                "email": u["email"],
                "total_tokens": u["total_tokens"],
                "requests": u["requests"],
                "days_active": len(u["days"]),
                "cache_read_input_tokens": u["cache_read_input_tokens"],
                "cache_creation_1h": u["cache_creation_1h"],
                "cache_creation_5m": u["cache_creation_5m"],
                "output_tokens": u["output_tokens"],
                "uncached_input_tokens": u["uncached_input_tokens"],
                "products": dict(u["products"]),
                "models": dict(u["models"]),
                "dominant_product": dominant_product,
                "dominant_product_share": dominant_product_tokens / total,
                "dominant_model": dominant_model,
                "model_diversity": len(u["models"]),
                "product_diversity": len(u["products"]),
                "product_entropy": product_entropy,
                # --- ratios used as clustering features ---
                "cache_read_ratio": u["cache_read_input_tokens"] / total,
                "cache_creation_ratio": cache_creation_total / total,
                "cache_1h_share": (
                    u["cache_creation_1h"] / cache_creation_total
                    if cache_creation_total > 0
                    else 0.0
                ),
                "output_ratio": u["output_tokens"] / total,
                "uncached_ratio": u["uncached_input_tokens"] / total,
                "tokens_per_request": total / u["requests"] if u["requests"] else 0,
                "avg_daily_tokens": total / len(u["days"]) if u["days"] else 0,
            }
        )

    summaries.sort(key=lambda s: -s["total_tokens"])
    with open(args.output, "w") as f:
        json.dump(summaries, f, indent=2)

    print(f"Aggregated {len(rows)} rows into {len(summaries)} users -> {args.output}", file=sys.stderr)


if __name__ == "__main__":
    main()
