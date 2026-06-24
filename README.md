# CI Pipeline — Node.js · GitHub Actions · Docker · Trivy · DockerHub

> **Part 1 of 2 — Continuous Integration**
> Part 2 (CD — ArgoCD + Kubernetes deployment) lives in the [CD-pipeline_for_nodeJS_PRJ3](https://github.com/mohan6451/CD-pipeline_for_nodeJS_PRJ3) repository.

![CI Pipeline](https://img.shields.io/badge/CI-GitHub%20Actions-2088FF?logo=github-actions&logoColor=white)
![Node.js](https://img.shields.io/badge/Node.js-20%20LTS-339933?logo=node.js&logoColor=white)
![Docker](https://img.shields.io/badge/Docker-Multi--stage-2496ED?logo=docker&logoColor=white)
![Trivy](https://img.shields.io/badge/Security-Trivy-1904DA?logo=aquasecurity&logoColor=white)
![DockerHub](https://img.shields.io/badge/Registry-DockerHub-2496ED?logo=docker&logoColor=white)
![Jest](https://img.shields.io/badge/Tests-Jest%20%2B%20Supertest-C21325?logo=jest&logoColor=white)

---

## What This Repository Does

Every push to `main` triggers a 4-job GitHub Actions pipeline that:

1. Detects how the run was triggered (push, PR, or manual with environment selection)
2. Runs unit tests with coverage report
3. Builds the Docker image and scans it for vulnerabilities — **before it touches the registry**
4. Pushes the verified image to DockerHub and writes the new image tag into the CD manifests repo

The CD side (ArgoCD + Kubernetes) picks up from that final step. This repo is only responsible for getting a tested, scanned, and tagged image into the registry.

---

## Pipeline Flow

```
git push / pull_request / workflow_dispatch
              │
              ▼
  ┌─────────────────────┐
  │  JOB 0 — Trigger    │  Logs whether run is automatic or manual
  └─────────────────────┘  (manual: engineer picks PRD / STG / UAT / PLT)

              │ (runs in parallel with JOB 0)
              ▼
  ┌─────────────────────┐
  │  JOB 1 — Unit Tests │  Jest + Supertest, Node.js 20, coverage artifact
  └────────┬────────────┘
           │ needs: test
           │  PASS ──────────────┐
           │  FAIL → stops here  │
                                 ▼
              ┌──────────────────────────────┐
              │  JOB 2 — Vulnerability Scan  │  Trivy on Docker image
              │          (Trivy)             │  SARIF → GitHub Security tab
              └──────────────┬───────────────┘
                             │ needs: [test, vulnerability-scan]
                             │  PASS ──────────────┐
                             │  FAIL → stops here  │
                                                   ▼
                             ┌─────────────────────────────────┐
                             │  JOB 3 — Build & Push           │
                             │  • Docker Buildx                │
                             │  • Push :latest + :<git-sha>    │
                             │  • Update deployment.yaml in    │
                             │    CD manifests repo (GitOps)   │
                             └─────────────────────────────────┘
                                          │
                                          ▼
                              CD pipeline takes over
                              (ArgoCD auto-syncs K8s)
```

**Gate rule:** Job 3 only runs if *both* Job 1 and Job 2 pass. An image with failing tests or unresolved CVEs never reaches DockerHub.

---

## Repository Structure

```
nodejs-app/
├── app/
│   ├── server.js           # Express app — endpoints: / and /health
│   ├── server.test.js      # Jest + Supertest — 3 test suites
│   └── package.json        # Express 4, Jest 29, Supertest 6
├── Dockerfile              # Multi-stage build (builder → production)
├── .dockerignore           # Excludes node_modules, .git, terraform, coverage
├── .gitignore
└── .github/
    └── workflows/
        └── ci.yml          # The full pipeline definition
```

---

## Job Details

### Job 0 — Trigger Info

```yaml
on:
  push:            { branches: [main] }
  pull_request:    { branches: [main] }
  workflow_dispatch:
    inputs:
      environment: { options: [PRD, STG, uat, plt], default: STG }
```

Supports three trigger modes. `workflow_dispatch` allows a manual run where the engineer selects the target deployment environment. The trigger job logs whether the run is automated or manual — useful for audit trails in multi-environment setups.

---

### Job 1 — Unit Tests

**What runs:** `jest --coverage --forceExit` against three test suites.

| Test Suite     | Assertion |
|----------------|-----------|
| `GET /`        | 200 · `message: "Hello from Node.js!"` · `version: "1.0.0"` |
| `GET /health`  | 200 · `status: "healthy"` |
| `GET /unknown` | 404 |

**Coverage report** is uploaded as a downloadable pipeline artifact (`coverage-report`) so it's accessible from the Actions tab without needing to run tests locally.

npm cache is keyed on `app/package.json`, so repeat runs skip re-downloading packages — faster feedback loops.

---

### Job 2 — Vulnerability Scan (Trivy)

This job builds the Docker image inside the runner and scans it — **the image is never pushed to the registry until this job passes**.

Trivy runs twice on the same image:

| Run | Format | Purpose |
|-----|--------|---------|
| First | `table` | Human-readable output visible directly in the pipeline log |
| Second | `sarif` | Machine-readable, uploaded to **GitHub → Security → Code scanning** tab |

**Scope:** `CRITICAL` and `HIGH` CVEs only. `ignore-unfixed: true` filters out CVEs that have no available patch yet — avoids noise from issues the team cannot act on.

The `security-events: write` permission on this job is required for the SARIF upload to the Security tab to succeed.

---

### Job 3 — Build, Push & Manifest Update

**Docker build:**
- Uses `docker/setup-buildx-action` for efficient builds
- GitHub Actions layer cache (`cache-from: type=gha`) speeds up repeat builds by reusing unchanged layers

**Two image tags are pushed to DockerHub:**

| Tag | Purpose |
|-----|---------|
| `:latest` | Always points to the most recent successful build |
| `:<git-sha>` | Immutable — used for traceability, rollback, and CD deployment |

**GitOps handoff:**  
The job clones the CD manifests repo (`CD-pipeline_for_nodeJS_PRJ3`) using a scoped PAT, updates the image tag in `deployment.yaml` via `sed`, and pushes the commit back. The CD pipeline (ArgoCD) detects this change and handles the rest. The CI pipeline's responsibility ends here.

---

## Dockerfile — Multi-Stage Build

```
Stage 1: builder (node:20-alpine)
  └── Installs production dependencies only (--omit=dev)
  └── Keeps build tools out of the final image

Stage 2: production (node:20-alpine)
  └── Creates non-root user (appuser / appgroup)
  └── Copies node_modules from builder stage
  └── Copies app source
  └── Sets file ownership to appuser
  └── Runs as appuser — never root
  └── HEALTHCHECK on /health endpoint every 30s
```

The final image is small (Alpine base, no dev dependencies, no build tools) and runs without root privileges — both are standard container security requirements in production environments.

---

## Application Endpoints

| Endpoint   | Status | Response |
|------------|--------|----------|
| `/`        | 200    | `{ message, version, environment }` |
| `/health`  | 200    | `{ status: "healthy", uptime: <seconds> }` |
| (any other)| 404    | Express default |

The `/health` endpoint is used by both the Docker `HEALTHCHECK` directive and Kubernetes liveness/readiness probes on the CD side.

---

## GitHub Secrets

| Secret | What it does |
|--------|-------------|
| `DOCKERHUB_USERNAME` | DockerHub login — used to name the image (`username/nodejs-app`) |
| `DOCKERHUB_TOKEN` | DockerHub access token — never use your account password |
| `MANIFEST_REPO_TOKEN` | GitHub PAT (classic, `repo` scope) — lets the CI bot push to the CD manifests repo |

> Secrets are encrypted by GitHub and injected as environment variables at runtime. They never appear in logs.

**Create DockerHub token:** DockerHub → Account Settings → Security → New Access Token

**Create GitHub PAT:** GitHub → Settings → Developer Settings → Personal Access Tokens → Tokens (classic) → `repo` scope

---

## Running Locally

```bash
git clone https://github.com/mohan6451/nodejs-app.git
cd nodejs-app/app

npm install

# Run tests
npm test

# Start the server
npm start
# → http://localhost:3000

# Build Docker image
cd ..
docker build -t nodejs-app:local .

# Run container
docker run -p 3000:3000 nodejs-app:local

# Verify endpoints
curl http://localhost:3000/
curl http://localhost:3000/health
```

---

## What Comes Next — Part 2 (CD)

This repo hands off a verified Docker image and an updated `deployment.yaml`. The CD side handles:

- ArgoCD watching the manifests repo and auto-syncing on every tag change
- Kubernetes rolling update on an AWS EC2 cluster (provisioned via Terraform)
- Zero-downtime deployment using `RollingUpdate` strategy

→ [CD-pipeline_for_nodeJS_PRJ3](https://github.com/mohan6451/CD-pipeline_for_nodeJS_PRJ3)

---

## Tech Stack

| Tool | Role |
|------|------|
| Node.js 20 + Express | Application runtime |
| Jest 29 + Supertest | Unit testing and API assertions |
| Docker (multi-stage, Alpine) | Containerisation |
| Trivy (Aqua Security) | Container image vulnerability scanning |
| GitHub Actions | CI pipeline automation |
| DockerHub | Container image registry |

---

Note: Adding the reference doc. to the repo that will be helpful while working with GitHub actions. 

---
## Author

**Mohan** — Cloud Operations & SRE Engineer  
[GitHub](https://github.com/mohan6451) · [LinkedIn](https://linkedin.com/in/mohanrajuk)

> Part 1 of a two-part CI/CD portfolio project. The CI pipeline (this repo) is fully implemented and tested. The CD pipeline (ArgoCD + Kubernetes) is linked above.
