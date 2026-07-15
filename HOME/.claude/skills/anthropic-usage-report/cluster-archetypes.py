#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = ["numpy", "scikit-learn"]
# ///
"""Cluster per-user usage summaries into archetypes.

The feature set is deliberately balanced across SEVEN axis families so that no
single one dominates the space (an earlier version was half product-share, which
collapsed every Claude Code user into one undifferentiated blob):

  intensity     log total tokens, log avg-daily tokens
  session depth log tokens/request, 1h-cache share (long agentic sessions vs
                short ephemeral turns)
  cadence       days active / 30
  working style cache-read ratio (reuse), cache-creation ratio (churn),
                output ratio (generate vs consume)
  product mix   share of tokens on code / chat / cowork / design
  model tier    share of tokens on opus / sonnet / haiku / fable -- the axis
                that separates deep-frontier coders from throughput/automation
                and sonnet-first coders

Run with `uv run cluster-archetypes.py` -- uv provisions numpy/scikit-learn into
an ephemeral venv, nothing touches the system interpreter.
"""
import argparse
import json
import sys

import numpy as np
from sklearn.cluster import KMeans
from sklearn.decomposition import PCA
from sklearn.metrics import silhouette_score
from sklearn.preprocessing import StandardScaler

PRODUCT_BUCKETS = ["chat", "claude_code", "cowork", "claude_design"]
MODEL_FAMILIES = ["opus", "sonnet", "haiku", "fable"]

FEATURE_NAMES = [
    "log_total_tokens",
    "log_tokens_per_request",
    "log_avg_daily_tokens",
    "days_active_frac",
    "cache_read_ratio",
    "cache_creation_ratio",
    "cache_1h_share",
    "output_ratio",
    "share_chat",
    "share_claude_code",
    "share_cowork",
    "share_claude_design",
    "share_opus",
    "share_sonnet",
    "share_haiku",
    "share_fable",
]


def product_share(u, name):
    total = u["total_tokens"] or 1
    return u["products"].get(name, 0) / total


def model_family(name):
    for fam in MODEL_FAMILIES:
        if fam in name:
            return fam
    return "other"


def model_share(u, fam):
    total = u["total_tokens"] or 1
    return sum(t for m, t in u.get("models", {}).items() if model_family(m) == fam) / total


def build_features(users):
    rows = []
    for u in users:
        rows.append(
            [
                np.log10(max(u["total_tokens"], 1)),
                np.log10(max(u["tokens_per_request"], 1)),
                np.log10(max(u["avg_daily_tokens"], 1)),
                u["days_active"] / 30.0,
                u["cache_read_ratio"],
                u["cache_creation_ratio"],
                u["cache_1h_share"],
                u["output_ratio"],
                product_share(u, "chat"),
                product_share(u, "claude_code"),
                product_share(u, "cowork"),
                product_share(u, "claude_design"),
                model_share(u, "opus"),
                model_share(u, "sonnet"),
                model_share(u, "haiku"),
                model_share(u, "fable"),
            ]
        )
    return np.array(rows)


def main():
    p = argparse.ArgumentParser()
    p.add_argument("input")
    p.add_argument("output")
    # default range stays within the report template's 8-slot color palette;
    # raise --k-max only if you also add palette slots (see SKILL.md step 4)
    p.add_argument("--k-min", type=int, default=6)
    p.add_argument("--k-max", type=int, default=8)
    p.add_argument("--seed", type=int, default=42)
    args = p.parse_args()

    users = json.load(open(args.input))
    X = build_features(users)

    scaler = StandardScaler()
    Xs = scaler.fit_transform(X)

    best_k, best_score, best_labels, best_model = None, -2, None, None
    for k in range(args.k_min, args.k_max + 1):
        km = KMeans(n_clusters=k, n_init=25, random_state=args.seed)
        labels = km.fit_predict(Xs)
        score = silhouette_score(Xs, labels)
        print(f"k={k} silhouette={score:.4f}", file=sys.stderr)
        if score > best_score:
            best_k, best_score, best_labels, best_model = k, score, labels, km

    print(f"Chosen k={best_k} (silhouette={best_score:.4f})", file=sys.stderr)

    pca = PCA(n_components=2, random_state=args.seed)
    coords = pca.fit_transform(Xs)

    # Cluster centroids in ORIGINAL (unstandardized) feature space -- easier
    # to reason about and name archetypes from real ratios, not z-scores.
    centroids_raw = []
    for k in range(best_k):
        mask = best_labels == k
        centroids_raw.append(X[mask].mean(axis=0).tolist())

    for i, u in enumerate(users):
        u["cluster"] = int(best_labels[i])
        u["pca_x"] = float(coords[i, 0])
        u["pca_y"] = float(coords[i, 1])

    out = {
        "k": best_k,
        "silhouette": best_score,
        "feature_names": FEATURE_NAMES,
        "cluster_centroids": centroids_raw,
        "cluster_sizes": [int((best_labels == k).sum()) for k in range(best_k)],
        "users": users,
    }
    with open(args.output, "w") as f:
        json.dump(out, f, indent=2)

    print(f"Wrote {len(users)} clustered users (k={best_k}) -> {args.output}", file=sys.stderr)


if __name__ == "__main__":
    main()
