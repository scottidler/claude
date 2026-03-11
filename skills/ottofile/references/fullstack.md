# Full-Stack Template

Combines a Python backend with a JS/TS frontend. The frontend directory defaults to `web/` but can be overridden with `--frontend-dir`. Replace `{{FRONTEND_DIR}}` and `{{PACKAGE_NAME}}` in the template.

## Dual-target pattern

Most tasks touch both backend and frontend. They share a common params block and routing logic, stored in `bash/dual-target-params.yml` and `bash/dual-target-routing.sh`. Inline these where you see the `{{inline:...}}` markers below.

## Template

```yaml
otto:
  api: 1
  tasks: [ci]
  envs:
    VERSION: "$(git describe --tags --always --dirty 2>/dev/null || echo 'dev')"
    GIT_SHA: "$(git rev-parse --short HEAD 2>/dev/null || echo 'unknown')"

tasks:
  dev:
    help: "Install dependencies (-b backend, -f frontend, default both)"
    {{inline:bash/dual-target-params.yml}}
    bash: |
      {{inline:bash/dual-target-routing.sh}}
      if [ "${run_backend}" = "true" ]; then
        echo "Installing backend dependencies..."
        uv sync --all-extras
      fi
      if [ "${run_frontend}" = "true" ]; then
        echo "Installing frontend dependencies..."
        cd {{FRONTEND_DIR}} && npm install
      fi

  lint:
    help: "Run linters with auto-fix (-b backend, -f frontend, default both)"
    {{inline:bash/dual-target-params.yml}}
    bash: |
      {{inline:bash/dual-target-routing.sh}}
      whitespace -r
      if [ "${run_backend}" = "true" ]; then
        echo "Linting backend..."
        uv run ruff format .
        uv run ruff check --fix .
      fi
      if [ "${run_frontend}" = "true" ]; then
        echo "Linting frontend..."
        (cd {{FRONTEND_DIR}} && npm run lint)
      fi

  check:
    help: "Run all quality checks (-b backend, -f frontend, default both)"
    {{inline:bash/dual-target-params.yml}}
    bash: |
      {{inline:bash/dual-target-routing.sh}}
      exit_code=0
      if [ "${run_backend}" = "true" ]; then
        echo "=== Checking backend format ==="
        uv run ruff format --check . || exit_code=$?
        echo ""
        echo "=== Running backend ruff check ==="
        uv run ruff check . || exit_code=$?
        echo ""
        echo "=== Running backend mypy ==="
        uv run mypy {{PACKAGE_NAME}}/ || exit_code=$?
      fi
      if [ "${run_frontend}" = "true" ]; then
        echo "=== Type checking frontend ==="
        (cd {{FRONTEND_DIR}} && npx tsc --noEmit) || exit_code=$?
        echo ""
        echo "=== Format checking frontend ==="
        (cd {{FRONTEND_DIR}} && npx prettier --check 'src/**/*.{ts,tsx,js,jsx,json,css}') || exit_code=$?
      fi
      [ $exit_code -ne 0 ] && exit $exit_code || true

  test:
    help: "Run tests (-b backend, -f frontend, default both)"
    {{inline:bash/dual-target-params.yml}}
    bash: |
      {{inline:bash/dual-target-routing.sh}}
      exit_code=0
      if [ "${run_backend}" = "true" ]; then
        echo "Testing backend..."
        uv run pytest || exit_code=$?
      fi
      if [ "${run_frontend}" = "true" ]; then
        echo "Testing frontend..."
        (cd {{FRONTEND_DIR}} && npm run test) || exit_code=$?
      fi
      [ $exit_code -ne 0 ] && exit $exit_code || true

  cov:
    help: "Run tests with coverage (-b backend, -f frontend, default both)"
    {{inline:bash/dual-target-params.yml}}
    bash: |
      {{inline:bash/dual-target-routing.sh}}
      exit_code=0
      if [ "${run_backend}" = "true" ]; then
        echo "Backend coverage..."
        uv run pytest --cov={{PACKAGE_NAME}} --cov-report=term-missing --cov-report=html || exit_code=$?
        echo ""
        echo "Coverage report: htmlcov/index.html"
      fi
      if [ "${run_frontend}" = "true" ]; then
        echo "Frontend tests..."
        (cd {{FRONTEND_DIR}} && npm run test) || exit_code=$?
      fi
      [ $exit_code -ne 0 ] && exit $exit_code || true

  ci:
    help: "Full CI pipeline (lint + check + test in parallel)"
    before: [lint, check, test]
    bash: |
      echo "All CI checks passed!"

  build:
    help: "Build for production (-b backend, -f frontend, default both)"
    {{inline:bash/dual-target-params.yml}}
    bash: |
      {{inline:bash/dual-target-routing.sh}}
      exit_code=0
      if [ "${run_backend}" = "true" ]; then
        echo "Building backend..."
        docker compose build || exit_code=$?
      fi
      if [ "${run_frontend}" = "true" ]; then
        echo "Building frontend..."
        (cd {{FRONTEND_DIR}} && npm run build) || exit_code=$?
      fi
      [ $exit_code -ne 0 ] && exit $exit_code || true

  run:
    help: "Start development server"
    before: [dev]
    bash: |
      uv run uvicorn {{PACKAGE_NAME}}.main:app --reload --host 0.0.0.0 --port 8000

  up:
    help: "Start services with docker compose"
    bash: |
      docker compose up --build -d

  down:
    help: "Stop docker compose services"
    bash: |
      docker compose down

  logs:
    help: "Follow service logs"
    bash: |
      docker compose logs -f

  clean:
    help: "Clean all artifacts (-b backend, -f frontend, --docker for docker, default all)"
    {{inline:bash/dual-target-params.yml}}
    params:
      --docker:
        default: false
        help: Clean Docker volumes and containers
    bash: |
      {{inline:bash/dual-target-routing.sh}}
      run_docker=false
      if [ "${backend}" = "false" ] && [ "${frontend}" = "false" ] && [ "${docker}" = "false" ]; then
        run_backend=true; run_frontend=true; run_docker=true
      else
        [ "${docker}" = "true" ] && run_docker=true
      fi
      if [ "${run_backend}" = "true" ]; then
        rm -rf build/ dist/ .venv/ .mypy_cache/ .pytest_cache/ .ruff_cache/ htmlcov/
        rm -rf *.egg-info .coverage
        find . -name '__pycache__' -type d -exec rm -rf {} + 2>/dev/null || true
        find . -name '*.pyc' -delete 2>/dev/null || true
      fi
      if [ "${run_frontend}" = "true" ]; then
        cd {{FRONTEND_DIR}} && rm -rf dist/ node_modules/ .vite/
      fi
      if [ "${run_docker}" = "true" ]; then
        docker compose down -v --remove-orphans
      fi
```

**Variations**:
- If Docker Compose is not present, omit `up`, `down`, `logs` tasks
- If the frontend uses `yarn` or `bun` instead of `npm`, substitute accordingly
- If the project has database migrations (alembic), add `db` tasks
