#!/usr/bin/env python3
"""Print a readable per-cluster report from cluster-archetypes.py output.

This is what a human/agent reads to *name* the archetypes: it lays out each
cluster's size, centroid (in original feature units, not z-scores), and a few
representative members, so you can write the archetypes JSON that
build-page-data.py consumes. Stdlib only.
"""
import argparse
import json
import sys


def fmt(name, value):
    # ratio-like features print as percentages; log/volume features as-is
    if name.startswith("share_") or name.endswith("_ratio") or name.endswith("_share"):
        return f"{value * 100:5.1f}%"
    return f"{value:8.3f}"


def main():
    p = argparse.ArgumentParser()
    p.add_argument("clustered", help="cluster-archetypes.py output JSON")
    p.add_argument("--members", type=int, default=3, help="representative members to show per cluster (default: 3)")
    args = p.parse_args()

    data = json.load(open(args.clustered))
    feature_names = data["feature_names"]
    centroids = data["cluster_centroids"]
    sizes = data["cluster_sizes"]
    users = data["users"]

    print(f"k={data['k']}  silhouette={data['silhouette']:.4f}  users={len(users)}\n")

    order = sorted(range(len(sizes)), key=lambda c: -sizes[c])
    for c in order:
        members = sorted(
            (u for u in users if u["cluster"] == c),
            key=lambda u: -u["total_tokens"],
        )
        print(f"── cluster {c}  ({sizes[c]} users) " + "─" * 30)
        for name, val in zip(feature_names, centroids[c]):
            print(f"    {name:22s} {fmt(name, val)}")
        top = members[: args.members]
        print(f"    top {len(top)} by tokens:")
        for u in top:
            print(
                f"      {u['name'][:28]:28s} {u['total_tokens'] / 1e9:6.2f}B  "
                f"dom={u['dominant_product']} ({u['dominant_product_share'] * 100:.0f}%)  "
                f"model={u['dominant_model']}"
            )
        print()


if __name__ == "__main__":
    main()
