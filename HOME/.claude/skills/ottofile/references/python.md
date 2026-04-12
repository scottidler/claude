# Python Templates

Detect the package name from `pyproject.toml` (`[project].name` or `[tool.poetry].name`), converting hyphens to underscores for the import name. Replace `{{PACKAGE_NAME}}` in templates below.

Detect package manager: `uv` if `uv.lock` exists or `[tool.uv]` is in pyproject.toml. If `poetry.lock` exists, it's a legacy poetry project - use `uv` anyway but note the migration. Poetry is legacy; all new projects should use `uv`.

## Package (`python-package`)

```yaml
otto:
  api: 1
  tasks: [ci]
  envs:
    VERSION: "$(git describe --tags --always --dirty 2>/dev/null || echo 'dev')"

tasks:
  lint:
    help: "Run whitespace and ruff linting with auto-fix"
    bash: |
      whitespace -r
      uv run ruff format .
      uv run ruff check --fix .

  check:
    help: "Run all quality checks (format, lint, type check)"
    bash: |
      echo "=== Checking format ==="
      uv run ruff format --check .
      echo ""
      echo "=== Running ruff check ==="
      uv run ruff check .
      echo ""
      echo "=== Running mypy type check ==="
      uv run mypy {{PACKAGE_NAME}}

  test:
    help: "Run all tests"
    bash: |
      uv run pytest -v

  cov:
    help: "Run tests with coverage"
    bash: |
      uv run pytest --cov={{PACKAGE_NAME}} --cov-report=term-missing --cov-report=html
      echo ""
      echo "Coverage report: htmlcov/index.html"

  ci:
    help: "Full CI pipeline (lint + check + test in parallel)"
    before: [lint, check, test]
    bash: |
      echo "All CI checks passed!"

  install:
    help: "Install dependencies with uv"
    bash: |
      uv sync --all-groups

  build:
    help: "Build package distribution"
    bash: |
      uv build

  publish:
    help: "Publish package"
    bash: |
      uv publish

  clean:
    help: "Clean build artifacts"
    bash: |
      rm -rf .venv/ .pytest_cache/ .mypy_cache/ .ruff_cache/ htmlcov/ dist/ build/ *.egg-info/
      find . -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true
```

---

## Service (`python-service`)

Extends the package template with these additions/changes:

- Add `GIT_SHA` env var
- Add `dev` task and `before: [dev]` dependency on lint, check, test, cov, run
- Split tests into `unit`/`integ` if `tests/unit/` exists, otherwise keep just `test`
- Add `run` task for the dev server
- Remove `build`/`publish`/`install` (services are deployed, not packaged)

```yaml
otto:
  api: 1
  tasks: [ci]
  envs:
    VERSION: "$(git describe --tags --always --dirty 2>/dev/null || echo 'dev')"
    GIT_SHA: "$(git rev-parse --short HEAD 2>/dev/null || echo 'unknown')"

tasks:
  dev:
    help: "Install dependencies"
    bash: |
      uv sync

  lint:
    help: "Run whitespace and ruff linting with auto-fix"
    before: [dev]
    bash: |
      whitespace -r
      uv run ruff format .
      uv run ruff check --fix .

  check:
    help: "Run all quality checks (format, lint, type check)"
    before: [dev]
    bash: |
      echo "=== Checking format ==="
      uv run ruff format --check .
      echo ""
      echo "=== Running ruff check ==="
      uv run ruff check .
      echo ""
      echo "=== Running mypy type check ==="
      uv run mypy {{PACKAGE_NAME}}

  unit:
    help: "Run unit tests"
    before: [dev]
    bash: |
      uv run pytest tests/unit

  integ:
    help: "Run integration tests"
    before: [dev]
    bash: |
      uv run pytest tests/integration

  test:
    help: "Run all tests"
    before: [dev]
    bash: |
      uv run pytest

  cov:
    help: "Run tests with coverage"
    before: [dev]
    bash: |
      uv run pytest --cov={{PACKAGE_NAME}} --cov-report=term-missing --cov-report=html
      echo ""
      echo "Coverage report: htmlcov/index.html"

  ci:
    help: "Full CI pipeline (lint + check + unit + integ in parallel)"
    before: [lint, check, unit, integ]
    bash: |
      echo "All CI checks passed!"

  run:
    help: "Start development server with auto-reload"
    before: [dev]
    bash: |
      uv run uvicorn {{PACKAGE_NAME}}.main:app --reload --host 0.0.0.0 --port 8000

  clean:
    help: "Clean build artifacts and caches"
    bash: |
      rm -rf build/ dist/ .venv/ .mypy_cache/ .pytest_cache/ .ruff_cache/ htmlcov/
      rm -rf *.egg-info .coverage
      find . -name '__pycache__' -type d -exec rm -rf {} + 2>/dev/null || true
      find . -name '*.pyc' -delete 2>/dev/null || true
```

**Variations**:
- If `tests/unit/` doesn't exist, omit `unit` and `integ`; keep just `test`. Change ci to `before: [lint, check, test]`
- If the service uses a different entrypoint (not `uvicorn`), adjust `run` accordingly
- If `.pre-commit-config.yaml` exists, `lint` can delegate to `uv run pre-commit run --all-files --show-diff-on-failure` after `whitespace -r`
