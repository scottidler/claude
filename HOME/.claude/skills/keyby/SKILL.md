---
name: keyby
description: Transform YAML/JSON lists-of-maps into maps keyed by a field (keyBy), or the inverse (unkey). Use when restructuring data between list and map forms.
---

# keyBy / unkey

Structural transformations between list-of-maps and keyed-map forms in YAML or JSON files.

## keyBy (key promotion)

Convert a list of maps into a map keyed by a designated field, removing that field from each entry.

### Usage

```
/keyby <file> [field]        # default field: "name"
/keyby config.yml name       # keyBy the "name" field
```

### Steps

1. Read the target file
2. Identify the list to transform (ask user if ambiguous)
3. For each item in the list, extract the value of the key field
4. Validate uniqueness of key values - abort if duplicates found
5. Rewrite the list as a map: key = extracted value, value = remaining fields
6. Write the updated file

### Before / After

```yaml
# before
filters:
  - name: tier1
    labels: [urgent]
    ttl: { read: keep }
  - name: tier2
    labels: [important]
    ttl: { read: 14d }

# after
filters:
  tier1:
    labels: [urgent]
    ttl: { read: keep }
  tier2:
    labels: [important]
    ttl: { read: 14d }
```

## unkey (map-to-list expansion)

Inverse of keyBy. Flatten a map back into a list by injecting the key as a named field.

### Usage

```
/keyby --reverse <file> [field]   # unkey, injecting key as "name"
```

### Before / After

```yaml
# before
filters:
  tier1:
    labels: [urgent]

# after
filters:
  - name: tier1
    labels: [urgent]
```

## Rules

- Key field values MUST be unique; abort and report if duplicates exist
- Preserve all other fields, ordering, and comments where possible
- Support nested paths (e.g., `spec.containers`) when the user specifies them
- Works on YAML and JSON files
