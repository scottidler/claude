---
name: markitdown
description: Extract clean markdown content from web pages and documents using markitdown CLI. Use instead of WebFetch when the user provides a URL to read or analyze, for online documentation, articles, blog posts, or any standard web page.
---

# MarkItDown

Use markitdown CLI to convert web pages and documents to clean markdown. Alternative to defuddle and Jina Reader.

Installed via pipx.

## Usage

Convert a URL to markdown:

```bash
markitdown <url>
```

Convert a local file:

```bash
markitdown document.pdf
markitdown spreadsheet.xlsx
markitdown presentation.pptx
```

Pipe output:

```bash
markitdown <url> | head -100
```

## Supported formats

- Web pages (HTML)
- PDF, DOCX, XLSX, PPTX
- Images (with OCR)
- Audio (with transcription)
- CSV, JSON, XML
