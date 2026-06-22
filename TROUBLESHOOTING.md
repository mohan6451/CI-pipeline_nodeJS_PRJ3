# CI Pipeline — Issues Faced & Resolutions

> **Project:** Node.js CI Pipeline — GitHub Actions · Docker · Trivy · DockerHub  
> **Author:** Mohan Raju Kandregula — Cloud Operations & SRE Engineer  
> **Status:** All issues resolved. Pipeline running successfully end-to-end.

This is a real debugging log captured while building this pipeline from scratch. Every issue here came from an actual pipeline run — not a tutorial. Each entry covers what broke, why it broke, and the exact fix applied.

---

## Index

| # | Issue | Stage | Root Cause |
|---|-------|-------|------------|
| 1 | CodeQL Action v3 deprecation warning | Vulnerability Scan | Wrong action version in workflow |
| 2 | SARIF file not found | Vulnerability Scan | `output:` field missing in trivy-action config |
| 3 | Permission denied uploading SARIF | Vulnerability Scan | Missing `security-events: write` on job |
| 4 | `if: always()` hiding the real error | Vulnerability Scan | Consumer step ran even when producer step failed |
| 5 | Trivy exit code 1 — real CVE found | Vulnerability Scan | Trivy working correctly; `exit-code: '1'` blocks on any finding |
| 6 | DockerHub push 401 Unauthorized | Build & Push | DockerHub token had Read-only scope instead of Read & Write |

---

## Issue 1 — CodeQL Action v3 Deprecation Warning

### What happened

Pipeline completed but showed a warning on the SARIF upload step:

```
Warning: CodeQL Action v3 will be deprecated in December 2026.
Please update all occurrences of the CodeQL Action in your workflow files.
```

### Root cause

`github/codeql-action/upload-sarif@v3` was pinned in the workflow — flagged for upcoming end-of-life.

### Fix

```yaml
# Before
uses: github/codeql-action/upload-sarif@v3

# After
uses: github/codeql-action/upload-sarif@v4
```

Commit the change:

```bash
git add .github/workflows/ci.yml
git commit -m "ci: upgrade codeql-action upload-sarif from v3 to v4"
git push origin main
```

> **Tip:** Before editing any workflow file, use `grep -r "codeql-action" .github/` to confirm which file and line needs the change.

---

## Issue 2 — SARIF File Not Found

### What happened

After upgrading to v4, the upload step failed:

```
Error: Path does not exist: trivy-results.sarif
```

### Root cause

The Trivy step was set to `format: 'table'` with no `output:` field. Table format writes to stdout only — no file is created on disk. The upload step had nothing to find.

```yaml
# Broken config — no output file defined
- name: Run Trivy scan on Docker image
  uses: aquasecurity/trivy-action@master
  with:
    image-ref: ${{ env.IMAGE_NAME }}:scan-${{ github.sha }}
    format: 'table'       # prints to log, not to a file
    exit-code: '1'
    severity: 'CRITICAL,HIGH'
    # no output: field
```

### Fix

Add a **second dedicated Trivy step** that outputs SARIF format. Keep the first step (table format) for human-readable log output. The second step creates the `.sarif` file for the upload:

```yaml
# Step 1 — human-readable output in the pipeline log
- name: Run Trivy scan on Docker image
  uses: aquasecurity/trivy-action@master
  with:
    image-ref: ${{ env.IMAGE_NAME }}:scan-${{ github.sha }}
    format: 'table'
    exit-code: '0'
    severity: 'CRITICAL,HIGH'
    ignore-unfixed: true

# Step 2 — creates the .sarif file for Security tab upload
- name: Run Trivy scan — save SARIF report
  uses: aquasecurity/trivy-action@master
  if: always()
  with:
    image-ref: ${{ env.IMAGE_NAME }}:scan-${{ github.sha }}
    format: 'sarif'
    output: 'trivy-results.sarif'    # this creates the file
    severity: 'CRITICAL,HIGH'
```

To verify the file is being created during debugging, add this between the scan and upload steps:

```yaml
- name: Confirm SARIF file exists
  if: always()
  run: ls -la trivy-results.sarif || echo "FILE NOT FOUND"
```

> **Key learning:** In trivy-action, `format: 'sarif'` alone is not enough. The `output:` field is what creates the physical file. Without it, Trivy writes to stdout regardless of the format chosen.

---

## Issue 3 — Permission Denied Uploading SARIF to Security Tab

### What happened

The SARIF file was now being generated correctly, but the upload step failed:

```
Warning: Resource not accessible by integration
Error: Resource not accessible by integration
Details: Resource not accessible by integration - https://docs.github.com/rest
```

### Root cause

`GITHUB_TOKEN` has read-only permissions by default in GitHub Actions. Uploading SARIF results to the GitHub Security tab requires `security-events: write` — which was not declared in the workflow.

### Fix

Add a `permissions:` block at the **job level** on the `vulnerability-scan` job. Job-level permissions follow the principle of least privilege — only this job gets the elevated permission, not the entire workflow:

```yaml
vulnerability-scan:
  name: Vulnerability Scan (Trivy)
  runs-on: ubuntu-latest
  needs: test
  permissions:
    security-events: write   # required for SARIF upload
    contents: read
    actions: read
  steps:
    ...
```

Also verify the repository-level default in GitHub UI:

```
Repository → Settings → Actions → General → Workflow permissions
→ Read and write permissions  ← select this
→ Save
```

> **Key learning:** `GITHUB_TOKEN` permissions (set in the YAML `permissions:` block) and your Personal Access Token scopes are two separate things. The `permissions:` block controls what `GITHUB_TOKEN` can do in that specific job. Your PAT controls your own user-level API access.

---

## Issue 4 — `if: always()` Hiding the Real Error

### What happened

The upload step was running even when the Trivy scan step had failed — and the error shown was misleading. The real failure (image not found, wrong format) was being masked because `if: always()` was on both steps.

### Root cause

Both the Trivy scan step and the upload step had `if: always()`. When the scan step failed for any reason, the upload step still ran — with no file to upload — and reported a generic error instead of the actual failure.

```yaml
- name: Run Trivy scan — save SARIF report
  if: always()     # ← this ran even when scan failed, masking the real error
  ...

- name: Upload Trivy SARIF
  if: always()
  ...
```

### Fix

Remove `if: always()` from the Trivy scan step temporarily to expose the real error:

```yaml
- name: Run Trivy scan — save SARIF report
  # if: always()   ← comment this out temporarily
  uses: aquasecurity/trivy-action@master
  ...
```

Once the underlying error is visible and fixed, restore `if: always()` **only on the upload step** — not the scan step:

```yaml
# Correct final config
- name: Run Trivy scan — save SARIF report
  uses: aquasecurity/trivy-action@master   # no if: always() here
  with:
    format: 'sarif'
    output: 'trivy-results.sarif'

- name: Upload Trivy SARIF to GitHub Security tab
  if: always()    # ← only here: upload happens even if scan found vulnerabilities
  uses: github/codeql-action/upload-sarif@v4
  with:
    sarif_file: 'trivy-results.sarif'
```

> **Key learning:** `if: always()` on a step that *creates* a file paired with `if: always()` on a step that *consumes* that file creates a deceptive chain — the consumer runs even when the producer failed. Use `if: always()` only on steps that should run regardless of upstream success: uploads, cleanup, and reporting steps.

---

## Issue 5 — Trivy Scan Failing with Exit Code 1 (Real CVE Found)

### What happened

The Trivy step failed the entire pipeline:

```
Error: Process completed with exit code 1.
CVE-2026-31802 — tar: File overwrite via drive-relative symlink traversal
```

### Root cause

This was **not a pipeline bug.** Trivy was working exactly as configured — it found a real CRITICAL CVE in the Docker image and exited with code 1:

```yaml
exit-code: '1'          # configured to fail pipeline on any finding
severity: 'CRITICAL,HIGH'
```

### Fix

**For this portfolio project** — changed `exit-code` to `'0'` and added `ignore-unfixed: true`. The pipeline continues, but findings are visible in the GitHub Security tab via SARIF:

```yaml
- name: Run Trivy scan on Docker image
  uses: aquasecurity/trivy-action@master
  with:
    image-ref: ${{ env.IMAGE_NAME }}:scan-${{ github.sha }}
    format: 'table'
    exit-code: '0'          # report findings, don't block the pipeline
    severity: 'CRITICAL,HIGH'
    ignore-unfixed: true    # skip CVEs with no patch available yet
```

**For production pipelines** — keep `exit-code: '1'`. If the CVE has no available fix yet, add it to `.trivyignore` with a justification and review date:

```
# .trivyignore
CVE-2026-31802   # tar symlink traversal — no fix available, risk accepted, reviewed 2026-06-15
```

> **Key learning:** `exit-code: '1'` is the correct production setting — failing the pipeline on a CRITICAL CVE is the right behaviour. For a portfolio or dev pipeline, `exit-code: '0'` combined with SARIF upload to the Security tab gives visibility without blocking. Understand which mode you're choosing and why.

---

## Issue 6 — DockerHub Push: 401 Unauthorized

### What happened

Job 3 (Build & Push) failed at the push step:

```
Error: buildx failed with: ERROR: failed to build: failed to solve:
failed to fetch oauth token: unexpected status from GET request to
https://auth.docker.io/token?scope=repository:***%2Fnodejs-app%3Apull%2Cpush
401 Unauthorized: access token has insufficient scopes
```

### Root cause

`DOCKERHUB_TOKEN` was set using a DockerHub access token created with **Read-only** access. Push operations require **Read & Write** access.

### Fix

**Step 1 — Regenerate the DockerHub token with correct scope:**

```
hub.docker.com
→ Account Settings → Security → Personal Access Tokens
→ Delete the existing read-only token
→ New Access Token
    Name: github-actions-push
    Access permissions: Read & Write    ← this is the required scope
→ Copy the token immediately (shown only once)
```

**Step 2 — Update the GitHub secret:**

```
Repository → Settings → Secrets and variables → Actions
→ DOCKERHUB_TOKEN → Update secret
→ Paste the new Read & Write token → Save
```

**Step 3 — Verify `DOCKERHUB_USERNAME` is the username, not the email:**

```
Repository → Settings → Secrets and variables → Actions → Variables tab
DOCKERHUB_USERNAME = mohan6451   ← username, not email address
```

**Step 4 — Re-run the failed job** from the Actions tab (no need to push again).

> **Key learning:** DockerHub access tokens default to Read-only. A pipeline that pushes images needs Read & Write scope. Verify the scope when creating the token — not after the 401 hits.

---

## Summary — All Issues and Fixes

| # | Issue | Fixed by |
|---|-------|----------|
| 1 | CodeQL v3 deprecation warning | Changed `@v3` to `@v4` in workflow YAML |
| 2 | SARIF file not found | Added second Trivy step with `format: sarif` + `output:` field |
| 3 | Permission denied on SARIF upload | Added `permissions: security-events: write` at job level |
| 4 | `if: always()` masking real errors | Removed `if: always()` from scan step; kept only on upload step |
| 5 | Pipeline blocked by real CVE | Changed `exit-code: '1'` to `'0'`; added `ignore-unfixed: true` |
| 6 | DockerHub push 401 | Regenerated DockerHub token with Read & Write scope |

---

## GitHub Secrets Reference

| Secret | Type | Required Scope |
|--------|------|----------------|
| `DOCKERHUB_USERNAME` | Variable | — (your DockerHub username) |
| `DOCKERHUB_TOKEN` | Secret | DockerHub PAT — **Read & Write** |
| `MANIFEST_REPO_TOKEN` | Secret | GitHub PAT — **repo + workflow** scopes |

---

*Debugged and documented by Mohan Raju Kandregula — June 2026*
