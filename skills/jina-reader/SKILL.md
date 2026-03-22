---
name: jina-reader
description: Extract clean markdown content from web pages using Jina Reader API. Use instead of WebFetch when the user provides a URL to read or analyze, for online documentation, articles, blog posts, or any standard web page.
---

# Jina Reader

Use Jina Reader API to extract clean markdown from any web page. No installation or auth required - just prefix the URL.

## Usage

Fetch clean markdown via curl:

```bash
curl -s "https://r.jina.ai/<URL>"
```

Example:

```bash
curl -s "https://r.jina.ai/https://supabase.com/docs/guides/getting-started/mcp"
```

Save to file:

```bash
curl -s "https://r.jina.ai/<URL>" -o content.md
```

## Notes

- No API key needed for basic usage
- Returns clean markdown with clutter removed
- Works with any public URL
- Rate limited on free tier - use sparingly for bulk operations
