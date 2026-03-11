# TypeScript/JavaScript Template

Detect package manager from lock files:
- `bun.lockb` or `bun.lock` - use `bun`
- `yarn.lock` - use `yarn`
- `pnpm-lock.yaml` - use `pnpm`
- Otherwise - use `npm`

Detect test runner from `package.json` scripts (vitest, jest, etc.).

## Template (npm default)

```yaml
otto:
  api: 1
  tasks: [ci]
  envs:
    VERSION: "$(git describe --tags --always --dirty 2>/dev/null || echo 'dev')"

tasks:
  install:
    help: "Install dependencies"
    bash: |
      npm install

  lint:
    help: "Fix lint and formatting issues"
    before: [install]
    bash: |
      whitespace -r
      npx eslint --fix .
      npx prettier --write '**/*.{ts,tsx,js,jsx,json,css}'

  check:
    help: "Verify lint, types, and formatting"
    before: [install]
    bash: |
      npx eslint .
      npx tsc --noEmit
      npx prettier --check '**/*.{ts,tsx,js,jsx,json,css}'

  test:
    help: "Run tests"
    before: [install]
    bash: |
      npx vitest run

  cov:
    help: "Run tests with coverage"
    before: [install]
    bash: |
      npx vitest run --coverage

  ci:
    help: "Full CI pipeline"
    before: [lint, check, test, cov]
    bash: |
      echo "All CI checks passed!"

  build:
    help: "Build for production"
    before: [install]
    bash: |
      npm run build

  clean:
    help: "Clean build artifacts"
    bash: |
      rm -rf dist/ node_modules/ .next/ .turbo/ *.tsbuildinfo .tsbuildinfo
```

**Variations**:
- Substitute `bun`/`yarn`/`pnpm` commands where appropriate (e.g., `bun install`, `bun run build`, `bunx vitest run`)
- Adjust test runner command based on what's in `package.json` scripts
- If `biome.json` exists, use `npx biome check` instead of eslint + prettier
