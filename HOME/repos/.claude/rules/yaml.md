---
alwaysApply: false
paths: "**/*.yml, **/*.yaml"
---

# YAML File Extensions

- Prefer `.yml` over `.yaml` for all YAML files
- Use `.yaml` only when a third-party tool requires it (e.g., some tools strictly require `.yaml`) or when there is a strong established convention (e.g., GitHub Actions uses `.yml`, Kubernetes manifests commonly use `.yaml`)
- When in doubt, use `.yml`

# YAML Structure: Prefer Keyed Maps Over Lists of Dicts

When a collection of named items could be written as either a list-of-dicts or a map-keyed-by-name, always prefer the keyed-map form.

**Wrong (list-of-dicts):**
```yaml
filters:
  - name: tier1
    labels: [urgent]
    ttl: 7d
  - name: tier2
    labels: [normal]
    ttl: 14d
```

**Right (map keyed by name):**
```yaml
filters:
  tier1:
    labels: [urgent]
    ttl: 7d
  tier2:
    labels: [normal]
    ttl: 14d
```

## Why

- No redundant `name` field — the key IS the name
- O(1) lookup by name; no need to search a list
- Duplicate names become a parse error, not a silent bug
- Maps directly to idiomatic Rust/Python: when deserializing, the key becomes the `name` field on the struct/class via serde `flatten` or a `HashMap<String, T>`

## Rust deserialization pattern

```rust
// Config file uses keyed-map form; serde reconstructs name from the key
#[derive(Deserialize)]
struct Filter {
    labels: Vec<String>,
    ttl: String,
}

// In the parent struct:
filters: HashMap<String, Filter>

// To get a Filter with its name attached, iterate:
for (name, filter) in &config.filters { ... }
```

## Python deserialization pattern

```python
# Config file uses keyed-map form
filters: dict[str, Filter]  # key = name, value = properties

@dataclass
class Filter:
    labels: list[str]
    ttl: str
```

## Exceptions

- When ordering matters and the order is not implied by the keys (use a list, but add a comment explaining why)
- When a third-party schema requires list form (Kubernetes, GitHub Actions, etc.)
- When items genuinely have no natural unique name/identifier
