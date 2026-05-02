# JOURNEY.md — Agent Session Log

This file is **append-only**. Every Claude Code session must add an entry before making any edits. Entries are immutable once written. This log provides non-repudiation for all agent actions.

## 2026-05-02 — Sync dead-code removal from template-builder PR #50

**Agent:** Claude Code (claude-opus-4-7), session `claude/resume-pr46-clone10-9Y10M`
**Trigger:** Sync of [template-builder PR #50](https://github.com/edri2or/autonomous-agent-template-builder/pull/50). Removes the two always-empty `inject_secret` lines for `github-app-id` (`vars.GITHUB_APP_ID`) and `github-app-private-key` (`secrets.GITHUB_APP_PRIVATE_KEY`) from Phase 1, plus the corresponding header-comment entries and dry-run echoes.

**Empirical proof (from PR #50 work):**

GitHub forbids both Variables and Secrets named with the `GITHUB_*` prefix:

```text
PUT /actions/variables/GITHUB_*  → HTTP 422 "Variable names must not start with GITHUB_."
PUT /actions/secrets/GITHUB_*    → HTTP 422 "Secret names must not start with GITHUB_."
```

So the two expressions always evaluated to empty string, `inject_secret` skip-on-empty no-op'd, and the lines did nothing. The Cloud Run receiver writes the three `github-app-*` secrets directly via Secret Manager API in Phase 4 (`src/bootstrap-receiver/main.py:268-273`). Phase ordering (`needs: [generate-and-inject-secrets]`) ensured the dead Phase-1 inject ran first and skipped, then Phase 4 wrote the real values — coincidentally correct, structurally misleading.

**Why a separate sync to this repo:** `bootstrap.yml`'s receiver-image build comes from this repo's source (same reasoning as PRs #1, #2 — manifest fix + `APP_INSTALLATION_ID` rename).

**Fix scope (all in `.github/workflows/bootstrap.yml`):**

- Header `# GitHub SECRETS`: remove `GITHUB_APP_PRIVATE_KEY` row.
- Header `# GitHub VARIABLES`: remove `GITHUB_APP_ID` row.
- Phase 1 inject block: remove the two dead `inject_secret` lines, replace with 3-line guard comment pointing at Phase 4.
- Phase 1 skip-on-empty comment: update example from `github-app-*` to `vars.APP_INSTALLATION_ID` (the only remaining empty-on-first-run secret).
- Phase 1 dry-run echo: remove the two stale lines, add 1 clarifying line.

Net diff: −2 inject lines, −2 dry-run echoes, −2 header entries, +explanatory comments (consolidated per /simplify pass on the upstream PR).

**Behavior unchanged at runtime** — receiver still writes; the inject lines were always no-ops.

---

## 2026-05-02 — Sync `APP_INSTALLATION_ID` rename from template-builder PR #49

**Agent:** Claude Code (claude-opus-4-7), session `claude/resume-pr46-clone10-9Y10M`
**Trigger:** Sync of [template-builder PR #49](https://github.com/edri2or/autonomous-agent-template-builder/pull/49) into clone-10. Same `bootstrap.yml`-builds-from-clone reasoning as the manifest fix sync (PR #1): the `inject_secret` line at `bootstrap.yml:171` runs from clone-10's source, so the variable name has to live here.

**Fix scope (identical to template-builder PR #49):**

- `.github/workflows/bootstrap.yml`: header comment (line 21), `vars.APP_INSTALLATION_ID` reference (line 171), step-summary prose (line 814).
- `CLAUDE.md`: forbidden-outputs exception (line 66) — `vars.GITHUB_APP_INSTALLATION_ID` → `vars.APP_INSTALLATION_ID` with rationale.
- `docs/runbooks/bootstrap.md`: 3 runbook references (lines 105, 120, 384).

**Behavior on clone-10:**

`APP_INSTALLATION_ID = 128886047` already set on this repo (verified HTTP 201 from `POST /actions/variables`). Re-dispatching `bootstrap.yml` after this PR merges will let Phase 1's `inject_secret` line read the variable and write `github-app-installation-id` to clone-10 Secret Manager.

---

## 2026-05-02 — Sync receiver manifest fix from template-builder PR #47

**Agent:** Claude Code (claude-opus-4-7), session `claude/resume-pr46-clone10-9Y10M`
**Trigger:** Phase 4 v11 (run [`25249207559`](https://github.com/edri2or/autonomous-agent-test-clone-10/actions/runs/25249207559)) deployed the Cloud Run receiver, but the operator's first browser click hit `github.com/organizations/edri2or/settings/apps/new` and GitHub's manifest validator returned **Invalid GitHub App configuration** with two errors: `Default events unsupported: installation` + `Default events are not supported by permissions: installation`. The 10-min secret-poll timed out and the receiver was torn down (verified via `actions/runs/.../jobs` API: `Tear down Cloud Run receiver: success`, `if: always() && check-secrets.outputs.exists == 'false'`).

**Root cause:** `src/bootstrap-receiver/main.py:133` listed `"installation"` in `default_events`. `installation/*` are App-lifecycle events delivered automatically to every GitHub App regardless of subscription — they are not valid in `default_events` and there is no corresponding permission key.

**Fix:** sync of [template-builder PR #47](https://github.com/edri2or/autonomous-agent-template-builder/pull/47) (already merged). 1-line change + 5-line guard comment quoting the exact GitHub error text.

**Why a separate sync to this repo:** `bootstrap.yml` builds the Cloud Run receiver image from this repo's source, so the fix has to live on clone-10's own main for the next Phase 4 v12 dispatch to render a valid manifest.

**Behavior unchanged at runtime** — installation lifecycle events still fire (they are auto-delivered, not opt-in via `default_events`).

**Next step:** dispatch `bootstrap.yml` after this PR merges. Operator's 2 clicks should now land secrets within the 10-min poll window. Closing entry will record run ID + secret-write confirmations + R-04/R-06/R-08/R-09 real-runtime status.

---

## 2026-05-01 — Path D simplify pass: gcloud filter syntax fix + de-duplication

**Agent:** Claude Code (claude-opus-4-7), session `claude/path-d-simplify-fixes`
**Trigger:** /simplify command on the just-merged PR #43 (Path D). Three parallel doc-review agents (reuse, quality, efficiency) flagged issues.

**Critical fix:**

- Invalid gcloud filter syntax `--filter='name~^github-app-id$'` in two locations (CLAUDE.md hot path + bootstrap.md Path D detection heuristic). The `~` operator is not supported by `gcloud secrets list`; the command would have failed if a fresh session ran it. Replaced with the documented substring filter `--filter='name:github-app-id'`.

**Other simplifications:**

- Path D §sequence step 4(a): replaced inline `@BotFather /newbot` restatement with cross-link to existing §1f (which already documents the procedure end-to-end).
- Path D §sequence step 3: removed redundant "(See [R-07] for rationale and the lifecycle test.)" double-reference; condensed to a single inline link.
- `provision-new-clone.yml` Step Summary: trimmed from a 5-step echo of Path D §sequence to a one-paragraph hand-off pointing at the runbook. The Step Summary is a teaser, not a reference; the runbook owns the procedure.

**Skipped findings (deferred or false-positive):**

- Hardcoded `'edri2or/autonomous-agent-template-builder'` repo name in clone-detection heuristic. A `vars.IS_CLONE` flag would be more robust but requires workflow changes; deferred.
- "Path D length 48 lines could be 46" — marginal, trim deferred.
- "Editorial framing in the previous JOURNEY entry" — append-only contract prevents editing the prior entry; future entries factored this guidance in.

**Net diff:** −8 lines (16 deletions, 8 insertions). All lint/test green.

---

## 2026-05-01 — Path D: Post-Provisioning Activation runbook (closes Phase E half-bridge)

**Agent:** Claude Code (claude-opus-4-7), session `claude/path-d-post-provisioning-activation`
**Trigger:** post-Phase-E forensic audit by the operator. Phase E (PR #36-#42, merged earlier today) made clone provisioning autonomous, but a fresh Claude session opened on a freshly-provisioned clone (e.g., `autonomous-agent-test-clone-9`) would find `GCP_WORKLOAD_IDENTITY_PROVIDER` set and proceed to "full autonomy" without realizing activation (R-04 Telegram, R-07 GitHub App, R-10 Linear) is still pending. There was no document ordering the activation steps, no defined "clone activated" success state, and no pointer from CLAUDE.md session-start to a clone-side runbook.

**Net consequence diagnosed:** Phase E was a half-bridge — provisioning solved, activation undocumented for fresh sessions.

**Actions taken (docs-only PR):**

- `docs/runbooks/bootstrap.md` — added "Path D — Post-Provisioning Activation" section. Trigger condition + clone-detection heuristic + 5-step sequence (set Variables → dispatch bootstrap.yml → R-07 2-click → R-04 decision → R-10 pool/silo decision) + success criteria checklist.
- `CLAUDE.md` — extended Session-start verification ritual with step 4: clone-side detection (heuristic on `github.repository`) directing to Path D before runtime tasks.
- `.github/workflows/provision-new-clone.yml` — beefed up the Step Summary from a one-line "next step" pointer to a numbered hand-off into Path D.

**No code changes.** All underlying mechanisms (`bootstrap.yml` Phase 4 `github-app-registration` job, `src/bootstrap-receiver/main.py` Cloud Run service, R-04/R-07/R-10 risk-register prose) already exist; this PR documents how to USE them in sequence on the clone side.

**Out of scope:**

- Automating R-04/R-07/R-10 — vendor floors per ADR-0007 §"Honest scope amendment".
- Running activation end-to-end against `autonomous-agent-test-clone-9` (it was a Phase E provisioning proof, not an intended runtime clone).
- Cleaning up GitHub repos `autonomous-agent-test-clone-2` through `-8` (litter — disposition deferred to operator).

---

## 2026-05-01 — Phase E CI-WIF residual: end-to-end validated (clone-009)

**Agent:** Claude Code (claude-opus-4-7), session `claude/phase-e-final-truth-docs`
**Status:** Phase E (ADR-0012) autonomous multi-clone provisioning **VALIDATED end-to-end** via `provision-new-clone.yml` run 25232896833. clone-009 (`autonomous-agent-test-clone-9` / `or-test-clone-009`, project number 834936625872) fully provisioned with billing, bucket, WIF pool, runtime SA, all 9 project-level SA roles, and all 6 GitHub Variables on the new repo.

**Final §E.1 procedure:** see ADR-0012 §E.1 (authoritative, including the three iterations that led to the measured-correct version) and `docs/runbooks/bootstrap.md` Path C (executable commands).

The measured insight that broke the impasse: GCP's `roles/billing.admin` at the org level only propagates to billing accounts "owned by or transferred to" the organization. The operator's billing account was created from `edri2or@gmail.com` before the Workspace `or-infra.com` existed, so it remained gmail-owned. Workspace-admin org-level billing IAM did NOT propagate. Only the gmail account could grant SA-level billing roles. The user's recognition of the dual-account topology was the diagnostic key.

**Bug fixes shipped during the iteration:** PR #36 (probe + ADR-0007 honesty), PR #37 (cloudbilling enable), PR #38 (stderr capture), PR #39 (bucket retry — buggy), PR #40 (exit-code fix + explicit bucket IAM + 150s retry), PR #41 (cleanup-test-clones.yml).

**Provision attempts and outcomes:**

| Run ID | Clone | Stop point | Cause |
|---|---|---|---|
| 25222544260 | clone-2 | gh-admin-token retrieval | §E.1 PAT not yet stored |
| 25229742757 | clone-2 retry | billing link | Org-level billing.user insufficient |
| 25231079638 | clone-3 | billing link | Same |
| 25231164108 | clone-4 | billing link | Eventual-consistency hypothesis falsified |
| 25231278194 | clone-5 | billing link | Surfaced precise IAM_PERMISSION_DENIED on billingAccounts |
| 25232188659 | clone-6 | line 213 bucket versioning | Q-Path GcsApiError race (after operator gmail-account grant unblocked billing) |
| 25232328369 | clone-7 | line 213 (silent) | Exit-code bug (`if !` → $?=0) |
| 25232584846 | clone-8 | billing link | Billing quota cap (>5 linked-projects/h on the account) |
| **25232896833** | **clone-9** | **success** | **End-to-end validated** ✅ |

Clone-001 (Q-Path) and clone-009 (Phase E) retained for non-repudiation per ADR-0009. Clones 002-008 deleted via `cleanup-test-clones.yml` to free billing quota; the GitHub repos `autonomous-agent-test-clone-2` through `-8` remain (namespace litter, no compute cost), disposition deferred.

---

## 2026-05-01 — Phase E CI-WIF residual: measured root-cause + targeted fix

**Agent:** Claude Code (claude-opus-4-7), session `claude/fix-ci-wif-cloudbilling-api`
**Trigger:** PR #36 (the diagnostic probe + honesty amendment) merged. Probe `probe-clone-state.yml` dispatched on main against `or-test-clone-002`. Annotations queried via `/check-runs/{id}/annotations`.

**Measured findings (run 25230782320, annotations dump):**

| Probe | Annotation | Verdict |
|---|---|---|
| `PROJECT_EXISTS` | `669590244579 ACTIVE 667201164106 folder` | ✓ Project created OK |
| `SA_ROLES_ON_PROJECT` | `roles/owner` | ✓ SA inherits owner — **previous "SA-creator-no-auto-owner" hypothesis was WRONG** |
| `BUCKET_MISSING` | `gs://or-test-clone-002-tfstate not found: 404` | ✗ grant-autonomy.sh did not reach step 2 |
| `WIF_POOL_MISSING` | `NOT_FOUND` | ✗ Did not reach step 5 |
| `SERVICE_ACCOUNTS_ON_PROJECT` | `(empty)` | ✗ Did not reach step 3 |
| `BILLING_PROBE_FAIL` | `API [cloudbilling.googleapis.com] not enabled on project [974960215714]` | **← the actual bug** |
| `APIS_ENABLED` (first 12) | `analyticshub, bigquery, …, dataform, dataplex, …` | Only GCP defaults — none of grant-autonomy.sh's iam/secretmanager/storage/run/artifactregistry |

**Root cause (now MEASURED, not hypothesized):**

Project number `974960215714` = `or-infra-templet-admin` (the SA's home project, also the `SECRETS_SOURCE_PROJECT` in CI-WIF mode). When `gcloud billing projects link or-test-clone-002 --billing-account=...` runs, the Cloud Billing API call is routed through the consumer project — the SA's home project — which does NOT have `cloudbilling.googleapis.com` enabled. So step 0's billing link in `tools/grant-autonomy.sh:104` fails with "API not enabled" → `set -e` → exits → bucket/SA/WIF never created.

Q-Path (Cloud Shell mode, 2026-05-01T15:43–15:47) did not surface this because Cloud Shell's gcloud uses a different consumer-project default for billing API calls — typically a billing-quota-project pre-configured by Cloud Shell itself.

**Hypotheses that were wrong (corrected here for posterity):**

1. ❌ "SA-creator-no-auto-owner — fix is folder-level owner on factory folder." Falsified by probe annotation `SA_ROLES_ON_PROJECT: roles/owner`. The SA DOES inherit owner from `gcloud projects create`. This hypothesis was scrubbed from CLAUDE.md / ADR-0007 in PR #36 before being measured-against.
2. ❌ "Step 1 (enable APIs) failed because SA lacks `serviceUsage` on new project." Same falsification — owner includes serviceUsage. The script never even got to step 1.

**Fix (one-line addition to `tools/grant-autonomy.sh` ~line 144):**

```bash
if [ "${CI_MODE}" = "true" ]; then
  gcloud services enable cloudbilling.googleapis.com \
    --project="${SECRETS_SOURCE_PROJECT}" --quiet
fi
```

Placed BEFORE the `gcloud billing projects link` call. Idempotent — `services enable` is a no-op if already enabled. Cloud-Shell mode is unaffected (`CI_MODE` defaults to `false` outside CI). The `or-infra-templet-admin` project will have `cloudbilling.googleapis.com` enabled after the first CI-WIF dispatch; subsequent dispatches will see it already enabled.

**Verification plan:**

1. PR this fix.
2. Merge.
3. Dispatch `provision-new-clone.yml` with NEW IDs (`new_repo_name=autonomous-agent-test-clone-3`, `new_project_id=or-test-clone-003`) — both fresh, no idempotency edge cases with the partial state of `or-test-clone-002`.
4. Read annotations on completion. With the new ERR trap in grant-autonomy.sh (line+command on failure), any further failure surfaces precisely.
5. On success: validate via `probe-clone-state.yml` against `or-test-clone-003` (expect bucket + WIF pool + SA all present).

**The partial state of `or-test-clone-002`:** project exists, billing not linked, no resources beyond owner-IAM. Disposition deferred. It can either be cleaned up (`gcloud projects delete or-test-clone-002`) or completed by a re-run of grant-autonomy.sh against it (idempotent). No urgency — silo isolation is intact (it doesn't pollute or-infra-templet-admin's 36 secrets).

---

## 2026-05-01 — Honest-autonomy doc amendment + Phase E CI-WIF residual investigation

**Agent:** Claude Code (claude-opus-4-7), session `claude/honest-autonomy-and-ci-wif-fix`
**Trigger:** Operator audit. After Phase E PR #35 merged earlier today and the post-merge `provision-new-clone.yml` dispatch for `autonomous-agent-test-clone-2` failed at step 7 (`Run grant-autonomy.sh` in CI-WIF mode), the agent surfaced operator-Cloud-Shell asks for diagnostics — drift from the Inviolable Autonomy Contract. Operator stopped the snowball with a forensic demand: "What is the goal? Prove every claim and stop asking compounding questions."

**Root-cause findings from forensic audit (this session, two parallel Explore agents):**

1. **`CLAUDE.md:17-19` framing contradicts `CLAUDE.md:156` HITL-row-9 + `ADR-0007:18-21`.** Lines 17-19 promise "Forever / no clicks / no `gcloud` commands"; lines 18-21 of the same ADR list two irreducibly-human vendor floors (GCP handshake, GitHub App 2-click). Every session in JOURNEY.md (8 distinct "last operator action" claims today alone) misquoted the rhetoric and ignored the clauses. The contract was **not** broken by the residuals — it was broken by the framing. **Fix:** rewrite CLAUDE.md and ADR-0007 with explicit three-scope language (1: GCP one-time, 2: §E.1 one-time-global, 3: per-clone vendor floors) and an honest table of vendor floors.

2. **`docs/runbooks/bootstrap.md:29-31` §E.1 sub-step 1 prescribed `gcloud billing accounts add-iam-policy-binding` (account-level).** Operator (with `roles/billing.admin` at org level) lacks `billing.accounts.setIamPolicy` on the specific billing account — IAM_PERMISSION_DENIED. The working pattern, visible in the org IAM dump, is **org-level** `roles/billing.user` (the SAs `claude-admin-sa` + `terraform-sa` have it that way). Operator pivoted to org-level binding mid-session and it worked. **Fix:** runbook + ADR-0012 §E.1 corrected to org-level.

3. **GCP gotcha for §E.1: SA-created projects don't reliably auto-inherit `roles/owner`.** When the runtime SA `github-actions-runner@or-infra-templet-admin` (with org-level `projectCreator`) creates `or-test-clone-002`, it does NOT necessarily get `roles/owner` on the new project — Q-Path worked because `edriorp38@or-infra.com` (the Cloud Shell user) has folder-admin everywhere; CI-WIF mode does not have that inheritance. **Hypothesis** (not yet verified — see "Pivot to diagnostic probe" below): grant-autonomy.sh step 1 (`gcloud services enable ... --project=NEW`) failed because the SA lacks `serviceUsage` on the new project. Likely fix: add folder-level `roles/owner` (or specific narrower roles) on the SA at folder `667201164106`, so all projects under the factory folder inherit ownership for the SA.

4. **Logs are inaccessible from this sandbox.** GitHub API `/actions/runs/{id}/logs` and `/actions/jobs/{id}/logs` both return 302 to `productionresultssa14.blob.core.windows.net` and `results-receiver.actions.githubusercontent.com` respectively. The local proxy returns HTTP 403 "Host not in allowlist" for both. Documented limitation since session start, not a regression. The blob hosts are not in the harness allowlist.

**Pivot to diagnostic probe (chosen over fix-by-guessing):** Rather than push the §E.1 folder-binding hypothesis as a fix, this session FIRST modifies `grant-autonomy.sh` to emit `::error::` workflow annotations on every gcloud failure (annotations ARE accessible via `/check-runs/{id}/annotations`), THEN re-dispatches, reads the actual error, and only then makes a targeted fix. This breaks the "fixing without measuring" pattern the operator called out.

**Actions in this PR (doc-only honesty + diagnostic probe):**
- `CLAUDE.md` — replaced "Forever / no clicks" framing with three-scope honesty table.
- `docs/adr/0007-inviolable-autonomy-contract.md` — added "Honest scope amendment" section reconciling the original §1 with §18.
- (in progress) `docs/runbooks/bootstrap.md` Path C §E.1 sub-step 1 — corrected to org-level `billing.user`; added folder-level owner binding documentation as the SA-creator-no-auto-owner workaround.
- (in progress) `docs/adr/0012-github-driven-clone-provisioning.md` §E.1 — same correction.
- (deferred to follow-up commits before PR opens) `tools/grant-autonomy.sh` — add `::error::` annotation emission for diagnostic visibility on next CI-WIF run.

**Out of scope:** the actual CI-WIF root cause is still hypothesis-grade. The diagnostic probe will measure it on the next dispatch. No more fix-by-guess in this session.

---

## 2026-05-01 — ADR-0012 (ADR-0011 Phase E) — GitHub-driven clone provisioning

**Agent:** Claude Code (claude-opus-4-7), session `claude/adr-0012-phase-e-github-driven-clone`
**Trigger:** Q-Path JOURNEY entry (immediately below) handed this session the implementation of `docs/plans/adr-0012-phase-e-github-driven-clone.md`. The plan is self-contained and was marked READY TO IMPLEMENT.

**Goal:** Lift per-clone provisioning trigger surface from Cloud Shell (current ADR-0011 §1 path) to a GitHub `workflow_dispatch` on this template-builder repo. After Phase E lands, a future clone is bootstrapped via one workflow run with no operator hands at the keyboard for that clone (the operator's only contributions are §E.1 one-time global pre-grants performed once, ever).

**Actions taken:**

- Created branch `claude/adr-0012-phase-e-github-driven-clone` (operator-confirmed override of harness default).
- `tools/grant-autonomy.sh` — three small changes per source plan §E.2:
  1. Added `CI_MODE="${CI:-false}"` documentation marker after `set -euo pipefail`.
  2. Decoupled secret-source from project-target: introduced `SECRETS_SOURCE_PROJECT="${SECRETS_SOURCE_PROJECT:-${GCP_PROJECT_ID}}"` and changed `sync()` to read `gcloud secrets versions access` from `${SECRETS_SOURCE_PROJECT}`. Operator-Cloud-Shell mode unchanged (defaults to new project); CI mode points it at `or-infra-templet-admin` where the platform tokens already live.
  3. Split the bucket `if ! describe; then create; update --versioning; fi` block into two independent idempotent gates (Q-Path GcsApiError eventual-consistency race fix).
- `.github/workflows/provision-new-clone.yml` (NEW) — workflow_dispatch with inputs (`new_repo_name`, `new_project_id`, `parent_folder_id`, `billing_account_id`, `github_owner`). Steps: WIF auth → setup-gcloud → fetch `gh-admin-token` from Secret Manager → `gh api .../generate` to clone the template into a new repo → `bash tools/grant-autonomy.sh` end-to-end against the new project (CI mode) → step summary.
- `docs/adr/0012-github-driven-clone-provisioning.md` (NEW MADR) — Status Accepted. Cites ADR-0007/ADR-0010/ADR-0011 §1 + the Q-Path JOURNEY entry as the binding proof.
- `docs/risk-register.md` — appended R-11 ("Runtime SA org-level role expansion — blast radius mitigated by repo-scoped WIF"). R-10 was already taken by Linear vendor-blocked silo isolation; ADR-0012 risk landed at R-11.
- `README.md`, `CLAUDE.md`, `docs/runbooks/bootstrap.md` — small reconciliation edits documenting the GitHub-driven path (ADR-0012) above the existing Cloud-Shell path.

**Validation (pre-merge expectation):** doc-lint, markdown-invariants, lychee `--offline`, OPA/Conftest — all expected green. No anchors renamed. New ADR-0012 satisfies the policy gate for infra change.

**Operator one-time setup (§E.1) — required before post-merge dispatch validation, NOT before PR landing:**

1. Bind `roles/resourcemanager.projectCreator` + `roles/resourcemanager.organizationViewer` on org `905978345393` to `github-actions-runner@or-infra-templet-admin.iam.gserviceaccount.com`.
2. Bind `roles/billing.user` on billing account `014D0F-AC8E0F-5A7EE7` to the same SA.
3. Store a PAT (`repo + workflow + admin:org` scopes; preferably fine-grained scoped to `edri2or` org) as `gh-admin-token` in `or-infra-templet-admin` GCP Secret Manager.
4. (Already done in Q-Path) `is_template=true` on the source repo.

These four pre-grants are the **last** operator touches for the entire org's clone-provisioning lifecycle.

**Out of scope:** Cloudflare per-clone domains (Phase B, shipped), Telegram per-clone bot (Phase D, vendor-floor deferred), Linear per-clone workspace (vendor-blocked), bootstrap.yml Phase 2 terraform-apply chicken-egg (separate ADR follow-up).

**Next-session task:** Once §E.1 operator pre-grants are confirmed, dispatch `provision-new-clone.yml` with `new_repo_name=autonomous-agent-test-clone-2`, `new_project_id=or-test-clone-002`. Verify zero spillover into `or-infra-templet-admin` (still 36 secrets, unchanged) and that all three clones operate independently.

---

## 2026-05-01 — ADR-0011 §1 live validation (Q-Path) — silo isolation proven end-to-end

**Agent:** Claude Code (claude-opus-4-7), session `claude/q-path-validation-and-phase-e-plan`
**Trigger:** Post Phase D merge — operator asked whether ADR-0011 §1 (auto-create per-clone GCP project via `tools/grant-autonomy.sh`) actually works in production. Live validation executed.

**Operator side (Cloud Shell, ~5 min):** created the test clone repo and ran the new auto-create flow.

```bash
# 1. Enable Template flag on source repo (one-time per source template)
gh api -X PATCH repos/edri2or/autonomous-agent-template-builder -F is_template=true

# 2. Create the test clone via gh CLI
gh repo create edri2or/autonomous-agent-test-clone \
  --template edri2or/autonomous-agent-template-builder --public

# 3. Run grant-autonomy.sh with the new ADR-0011 §1 env vars
export GH_TOKEN='...'                                  # PAT, repo+workflow+admin:org
export GITHUB_REPO=edri2or/autonomous-agent-test-clone
export GCP_PROJECT_ID=or-test-clone-001
export GCP_PARENT_FOLDER=667201164106                  # operator's "factory" folder
export GCP_BILLING_ACCOUNT=014D0F-AC8E0F-5A7EE7
bash tools/grant-autonomy.sh
```

**Result:** `✅ AUTONOMY GRANTED` for the new clone. Live values captured:

| Resource | Value (from live verification 2026-05-01T15:47Z) |
|----------|-----|
| GCP project | `or-test-clone-001` (project number `995534842856`) |
| Parent | folder `667201164106` ("factory") under org `905978345393` (or-infra.com) |
| Created | `2026-05-01T15:43:26.445Z` (ACTIVE) |
| Billing | `billingAccounts/014D0F-AC8E0F-5A7EE7` (enabled) |
| WIF pool | `projects/995534842856/locations/global/workloadIdentityPools/github` (ACTIVE) |
| WIF provider attribute condition | `assertion.repository == 'edri2or/autonomous-agent-test-clone'` |
| Runtime SA | `github-actions-runner@or-test-clone-001.iam.gserviceaccount.com` |
| TF state bucket | `or-test-clone-001-tfstate` (US-CENTRAL1) |
| GitHub Variables on new repo | 6 vars all referencing `or-test-clone-001`/`995534842856` (no leakage to old project) |
| Secrets in new project | **0** (operator hasn't pre-populated; bootstrap.yml Phase 1 will mint n8n + openrouter at first dispatch) |
| Secrets in old `or-infra-templet-admin` | **36** (unchanged — proves zero cross-pollination) |

**What this proves end-to-end (not just in code review):**

1. **Auto-create works.** `gcloud projects create --folder=...` and `gcloud billing projects link` ran successfully under the operator's already-existing org-level pre-grants (`projectCreator`, `billing.user`). No new operator action required beyond what ADR-0011 §1 documented.
2. **WIF is repo-scoped.** The new provider's `attributeCondition` literally references the new repo's slug — a token from `template-builder` cannot impersonate `test-clone`'s SA, and vice versa. Project-level isolation enforced by GCP.
3. **GitHub Variables on the new repo are independent.** All 6 vars (`GCP_PROJECT_ID`, `GCP_REGION`, `GCP_WORKLOAD_IDENTITY_PROVIDER`, `GCP_SERVICE_ACCOUNT_EMAIL`, `TF_STATE_BUCKET`, `N8N_OWNER_EMAIL`) point exclusively at the new project. Future workflow runs on `test-clone` route to `or-test-clone-001`'s Secret Manager.
4. **Secret namespace boundary holds.** New project: 0 secrets. Old project: still 36. Kebab-case canon (ADR-0006) didn't collide because the projects are GCP-IAM-isolated.
5. **The "single permitted operator action per clone" contract (ADR-0007) is intact.** One `bash tools/grant-autonomy.sh` per clone, plus the prior org-level pre-grants which the operator had already (no new grants needed for this run).

**Two minor latent issues surfaced (out of scope of this ADR — tracked for follow-up):**

1. **`is_template` flag was off on the source repo.** First attempt at `gh repo create --template` failed: *"is not a template repository"*. Fix: `gh api -X PATCH repos/.../template-builder -F is_template=true`. ADR-0011 §1 didn't document this prerequisite. **Follow-up:** add this to the `docs/adr/0011-silo-isolation-pattern.md` §1 implementation note + README HITL. The fix is operator-API (no UI click), one-time global, and we capture it in this PR's docs.

2. **`gs://*-tfstate` versioning update flake.** First attempt at `gcloud storage buckets update gs://or-test-clone-001-tfstate --versioning` returned `GcsApiError('')` immediately after bucket creation (eventual-consistency race). The bucket itself was created fine. After a 5-second sleep, the update succeeded. Re-run of `grant-autonomy.sh` skipped the create+update block (bucket exists), so versioning was set independently. **Follow-up:** in `tools/grant-autonomy.sh:75-86`, split the `if ! describe; then create; update; fi` block into separate idempotent calls — `create-if-missing` and `update-versioning-always` — so the versioning step is naturally retry-safe. Documented in the Phase E plan file as a piggy-back fix.

**Documents added in this PR (no code changes — pure docs + planning):**

- `docs/JOURNEY.md` — this entry.
- `docs/plans/adr-0012-phase-e-github-driven-clone.md` (NEW) — full Phase E implementation plan: new `provision-new-clone.yml` workflow + grant-autonomy.sh CI-mode + GH PAT in GCP Secret Manager + ADR-0012 supersession. Designed so a fresh Claude Code session can pick it up cold and execute it.
- `docs/bootstrap-state.md` — addendum section "Test clone for ADR-0011 §1 validation" with the live snapshot above.

**Next-session task (handoff):**

> **Implement Phase E per `docs/plans/adr-0012-phase-e-github-driven-clone.md`.** That document is self-contained — it cites this Q-Path entry as proof that §1 works, lists exact files to modify, exact pre-grants the operator needs to add (one-time SA org-level grant + PAT in GCP Secret Manager), and the `provision-new-clone.yml` workflow scaffold. Execute, open PR, validate by dispatching the new workflow to spawn a third test clone (`autonomous-agent-test-clone-2`).

**Outcome:** Q-Path complete. ADR-0011 §1 fully validated end-to-end. Phase E plan in place.

---

## 2026-05-01 — ADR-0011 Phase D: Telegram Managed Bots — DEFERRED (vendor floor)

**Agent:** Claude Code (claude-opus-4-7), session `claude/adr-0011-phase-d-defer`
**Trigger:** Phase C (PR #32) merged. Per the ADR-0011 phased plan, Phase D was scoped to implement Telegram per-clone bot minting via Bot API 9.6 Managed Bots.

**Why deferred:** before writing code, I re-researched the actual Bot API 9.6 flow and found that Phase A's framing — "auto-mint a per-clone Telegram child bot fully programmatically" — was an **over-claim**. The real flow per [Telegram's Bot API changelog](https://core.telegram.org/bots/api-changelog) and [Aiia's Managed Bots writeup](https://aiia.ro/blog/telegram-managed-bots-create-ai-agents-two-taps/):

1. Manager bot constructs `https://t.me/newbot/{manager_bot}/{suggested_username}`.
2. **Recipient must tap the link, then tap "Create"** in Telegram's pre-filled dialog.
3. Manager bot receives a `managed_bot` webhook update; calls `getManagedBotToken` to retrieve the new bot's token.

Telegram's stated policy: *"explicit approval before any managed bot is created — anti-abuse"*. The tap is **non-removable**.

**Operator decision (this session):** defer Phase D. Treating Telegram bot creation parallel to ADR-0011 §4's handling of Linear (vendor-blocked silo isolation). The 1-tap flow remains a real improvement over the multi-step @BotFather conversation, but it's not full automation, so the silo-isolation goal of "operator action = once globally, never per clone" is not achievable on Telegram today.

**What changed in this PR (no code, docs only):**

- `docs/adr/0011-silo-isolation-pattern.md` — top Status banner reflects Phase D deferral; §3 rewritten to "Status: Deferred — vendor floor"; §3 preserves the 1-tap implementation outline for the eventual unblocking ADR; phased table marks D as "Docs only — Deferred". Future-implementation outline preserved.
- `docs/risk-register.md` R-04 — classification re-revised from `AUTOMATABLE_VIA_BOT_API_9.6` (Phase A's over-claim) to `HITL_TAP_REQUIRED_PER_CLONE`. Full revision history preserved (DO_NOT_AUTOMATE → AUTOMATABLE → HITL_TAP_REQUIRED). Risk Matrix row updated.
- `CLAUDE.md` — Forbidden inventory line 20 (Telegram) corrected; HITL row 6 corrected; Risk Matrix R-04 row corrected.
- `README.md` — HITL inventory row 6 corrected.
- `docs/JOURNEY.md` — this entry.

**No changes to:**
- `tools/grant-autonomy.sh` — still expects operator-provided `telegram-bot-token` (ADR-0010 contract preserved).
- `src/n8n/workflows/*.json` — they read `TELEGRAM_BOT_TOKEN` env var; whichever path provides the value is invisible to them.
- `bootstrap.yml` Phase 1 — still injects `telegram-bot-token` from GitHub Secrets to GCP.

**Unblocking trigger:** Telegram surfaces a vendor-API path that mints child bots without a per-bot tap (e.g., a SaaS pre-authorization flow). Track via [Bot API changelog](https://core.telegram.org/bots/api-changelog). When this lands, supersede the deferral with a new ADR.

**Net ADR-0011 status (post this PR):**

- §1 (GCP Project Factory) — ✅ shipped (Phase C, PR #32)
- §2 (Cloudflare parameterization) — ✅ shipped (Phase B, PR #31)
- §3 (Telegram Managed Bots) — ⏸ deferred (this PR)
- §4 (Linear gap acknowledgment) — ✅ shipped (Phase A, PR #30)
- §5 (Documentation reconciliation) — ✅ shipped (Phase A, PR #30)

**2 new auto-implementations** (§1 GCP Project Factory, §2 Cloudflare parameterization) **+ 2 vendor-floored exceptions** (§3 Telegram tap residue, §4 Linear no-API). §5 (docs reconciliation) shipped in Phase A. The silo-isolation goal is met for every per-clone resource the agent can autonomously provision; Telegram and Linear remain the two named vendor exceptions.

**Outcome:** pending PR #33 merge.

---

## 2026-05-01 — ADR-0011 Phase C: GCP Project Factory adoption

**Agent:** Claude Code (claude-opus-4-7), session `claude/adr-0011-phase-c-project-factory`
**Trigger:** Phase B (PR #31) merged. Per the ADR-0011 phased plan, Phase C extends `tools/grant-autonomy.sh` to auto-create the per-clone GCP project so the operator no longer has to pre-create it in the GCP Console.

**Implementation choice — bash gcloud, not the terraform-google-project-factory module:**

The original ADR-0011 §1 named [`terraform-google-modules/terraform-google-project-factory`](https://github.com/terraform-google-modules/terraform-google-project-factory) as the canonical mechanism. On implementation, I opted for `gcloud projects create` + `gcloud billing projects link` directly in `grant-autonomy.sh` because:

1. **Chicken-and-egg with state bucket.** The grant-autonomy.sh script also creates the GCS Terraform state bucket inside the project (line 76-86). If project-creation lived in Terraform, the state bucket would have to be either (a) created in a different bootstrap-only project, (b) created post-hoc after a separate manual `terraform apply`, or (c) bootstrapped via the same chicken-egg dance the script already solves. The bash path is just cleaner here.
2. **Single project per script run.** The terraform module shines for org-level multi-project scaffolding (one `terraform apply` produces N projects). Per-clone provisioning needs one project; the bash 4-line equivalent is sufficient.
3. **No new TF dependency.** Avoids pinning, version-bumping, and registry-source-trust burdens for a 4-line equivalent.

ADR-0011 §1 was amended in this PR to document this implementation choice; the canonical "Project Factory pattern" name still applies (silo isolation via auto-creation) — just realized in bash, not HCL.

**Mode contract:**

- **Auto-create (ADR-0011 §1):** export `GCP_BILLING_ACCOUNT` + one of `GCP_PARENT_FOLDER`/`GCP_PARENT_ORG`. Script runs `gcloud projects create --folder=...` (or `--organization=...`) → `gcloud billing projects link --billing-account=...`. Operator one-time pre-grants on parent: `roles/resourcemanager.projectCreator` + `roles/billing.user`.
- **Manual fallback (ADR-0010):** if `GCP_BILLING_ACCOUNT` is unset OR if the project already exists, the script proceeds in ADR-0010 manual mode (no creation, just describe).
- **Diagnostic on misconfiguration:** if the project doesn't exist AND `GCP_BILLING_ACCOUNT` is unset → fail with a message that surfaces both modes. If billing is set but no parent → fail.

**Deferred safety check:** my initial Phase A claim that "Project Factory generates unique project IDs with a random suffix → collision is structurally impossible" was over-claimed for the bash implementation (which uses operator-specified IDs without random suffix). Phase C corrects ADR-0010's supersession banner: the deferred collision-detection check from ADR-0010 §2 **remains relevant** as a future enhancement, since accidental ID reuse across clones can still produce a no-op-then-overwrite race in bash mode.

**Files:**

- `tools/grant-autonomy.sh:14-26, 55-92` — usage docs + new "Step 0" auto-create block.
- `docs/adr/0011-silo-isolation-pattern.md:71-85, 96, 104` — §1 status update; §5 supersession-banner correction; phased table marks C as this PR.
- `docs/adr/0010-clone-gcp-project-isolation.md:1-7` — supersession banner corrected (deferred check is NOT obsolete).
- `CLAUDE.md` HITL row 1 — both modes documented.
- `README.md` "Single bootstrap action" block — both modes + new env-var example.
- `docs/runbooks/bootstrap.md` Path A — both modes + env-var example.

**Plan:**
1. Branch `claude/adr-0011-phase-c-project-factory`.
2. Edit `tools/grant-autonomy.sh` + 5 doc files.
3. Open PR #32. CI: `markdownlint`, `markdown-invariants`, `OPA`, `lychee` pass.
4. After merge: validation is by re-running grant-autonomy.sh on the existing project — must remain idempotent (the new auto-create branch is gated on project NOT existing). Actual auto-create path can only be exercised on a brand-new throwaway project + parent folder, deferred to first real second-clone scenario.

**Outcome:** pending PR #32 merge.

---

## 2026-05-01 — ADR-0011 Phase B: Cloudflare parameterization (clone_slug)

**Agent:** Claude Code (claude-opus-4-7), session `claude/adr-0011-phase-b-cloudflare`
**Trigger:** Phase A (PR #30) merged. Per the ADR-0011 phased plan, Phase B is the lowest-risk implementation phase — self-contained Terraform + wrangler change.

**What changed:**

- `terraform/variables.tf` — new `var.clone_slug` (default `"agent"` for back-compat).
- `terraform/cloudflare.tf:24-67` — three hardcoded names replaced:
  - `cloudflare_record.agent_api.name`: `"api"` → `"${var.clone_slug}-api"`.
  - `cloudflare_record.n8n.name`: `"n8n"` → `"${var.clone_slug}-n8n"`.
  - `cloudflare_worker_script.edge_router.name`: `"edge-router"` → `"${var.clone_slug}-edge"`.
- `wrangler.toml:1` — `name = "autonomous-agent-edge"` → `name = "${CLONE_SLUG}-edge"` (placeholder, rendered at deploy time).
- `.github/workflows/deploy.yml:89-105` — new step "Render wrangler.toml clone_slug placeholder" runs `envsubst '${CLONE_SLUG}'` (vars-list-restricted to keep rendering side-effect-free) before `cloudflare/wrangler-action@v3`.
- `.github/workflows/bootstrap.yml:239-248` — `terraform plan` now passes `-var="clone_slug=${{ github.event.repository.name }}"`.
- `.github/workflows/terraform-plan.yml:21-27` — adds `TF_VAR_clone_slug` to the env block consumed by the PR-level plan job.
- `terraform/terraform.tfvars.example` — adds `clone_slug = "agent"` for local-plan ergonomics.

**Why `envsubst '${CLONE_SLUG}'` (not bare `envsubst`):** the bare form expands every `${VAR}` in the file. Restricting to a single var keeps the wrangler.toml rendering idempotent if more shell-style placeholders are added later, and avoids accidental expansion of a CI-context var (e.g. `${HOME}`).

**Why `var.clone_slug` defaults to `"agent"`:** terraform-plan and any local `terraform plan` against a developer's machine without GitHub-Actions context need a sane default; CI always overrides via `TF_VAR_clone_slug` or `-var="clone_slug=..."`. Falling back to `"agent"` reproduces the original hardcoded names *for the original `autonomous-agent-template-builder` repo only*: `agent-api`, `agent-n8n`, `agent-edge`. Subsequent clones get `<repo-name>-api`, `<repo-name>-n8n`, `<repo-name>-edge` — distinct from this repo's, so no collision when a second clone deploys to the same Cloudflare account.

**Pre-existing behavior preserved:**
- `cloudflare_zone_id == ""` still gates the entire Cloudflare config off (per `terraform/cloudflare.tf:12-14` `local.cloudflare_enabled`). No surprise activations.
- The Worker `lifecycle.ignore_changes = [content]` still applies — wrangler-action remains the source of truth for Worker code; Terraform only manages metadata.

**Plan:**
1. Branch `claude/adr-0011-phase-b-cloudflare`.
2. Edit the 6 files above + ADR-0011 §2 status update + this JOURNEY entry.
3. Open PR #31. CI: `markdownlint`, `markdown-invariants`, `OPA`, `lychee` pass; `terraform-plan` will run on the new branch only if it pushes `terraform/**` paths (it does — flags new var).
4. After merge: dispatch `bootstrap.yml` to verify the new TF var is accepted; if `vars.CLOUDFLARE_ZONE_ID` is set, the apply will create new DNS records under `agent-api`/`agent-n8n` (replacing `api`/`n8n`).

**Outcome:** pending PR #31 merge.

---

## 2026-05-01 — ADR-0011 Phase A docs baseline (silo isolation pattern)

**Agent:** Claude Code (claude-opus-4-7), session `claude/adr-0011-silo-isolation-docs`
**Trigger:** Operator question post-PR #29 — "shouldn't every clone of this template get its own GCP project? Isn't that the goal?" — exposed an architectural gap. Three resources are NOT auto-isolated per clone: (a) the GCP project itself (no `gcloud projects create` anywhere; ADR-0010 documents "operator-brings"), (b) Cloudflare DNS records (`name = "api"`, `name = "n8n"` hardcoded in `terraform/cloudflare.tf:27,42`) and the Worker name (`autonomous-agent-edge` hardcoded in `wrangler.toml:1`), (c) the Telegram bot (R-04 `DO_NOT_AUTOMATE`). Linear is also not isolated but is vendor-blocked.

**Internet research conducted (per operator request "תבצע מחקר אינטרנטי שמעיד על הסטנדארט המקצועי ותכריע מה עדיף ותוכיח את הטענות שלך"):**

- **AWS canonical pattern:** [Account Vending Machine / Control Tower Account Factory](https://docs.aws.amazon.com/controltower/latest/userguide/terminology.html). Auto-creates an AWS account per tenant via Service Catalog + CloudFormation StackSets.
- **GCP canonical pattern:** [`terraform-google-modules/terraform-google-project-factory`](https://github.com/terraform-google-modules/terraform-google-project-factory) — Google-official, Terraform Registry, pinned `~> 18.2`. Required org-level pre-grants: `roles/resourcemanager.projectCreator`, `roles/billing.user`, `roles/resourcemanager.organizationViewer`.
- **Cloudflare canonical pattern:** [Cloudflare for SaaS](https://developers.cloudflare.com/cloudflare-for-platforms/cloudflare-for-saas/) with [Custom Hostnames API](https://developers.cloudflare.com/cloudflare-for-platforms/cloudflare-for-saas/domain-support/create-custom-hostnames/) + wildcard fallback origin. For MVP, simple subdomain parameterization is sufficient.
- **Telegram (CRITICAL FINDING):** [Bot API 9.6 (April 2026)](https://core.telegram.org/bots/api-changelog) introduced **Managed Bots** with `getManagedBotToken` / `replaceManagedBotToken`. R-04's `DO_NOT_AUTOMATE` is **outdated**; per-clone bot creation is now programmatically possible.
- **Linear:** [GraphQL API docs](https://linear.app/developers/graphql) — confirmed no `createWorkspace` mutation. Vendor-blocked.
- **Industry taxonomy:** [AWS SaaS Lens silo/pool/bridge models](https://docs.aws.amazon.com/wellarchitected/latest/saas-lens/silo-pool-and-bridge-models.html). Operator's stated goal = silo (dedicated resources per tenant; "regulated industries"; "willing to pay premium for dedicated infrastructure").

**Decision (ADR-0011):** adopt the silo pattern across all auto-soluble resources (§1 GCP, §2 Cloudflare, §3 Telegram). Document Linear as the lone vendor-blocked exception (§4). Reconcile with ADR-0007 + ADR-0010 (§5).

**Phase A scope (this PR):** docs only — ADR-0011 itself, R-04 status revision (`DO_NOT_AUTOMATE` → `AUTOMATABLE_VIA_BOT_API_9.6`), R-10 add (Linear gap), ADR-0010 supersession banner, README + CLAUDE.md HITL row 6 + Key Files updates. Zero code changes; deliberate to keep blast radius zero before the higher-risk Phases B/C/D land in their own PRs.

**Plan:**
1. Branch `claude/adr-0011-silo-isolation-docs`.
2. Write `docs/adr/0011-silo-isolation-pattern.md` (full MADR with all 4 §, marking §1/§2/§3 as "Implementation pending").
3. Edit `docs/risk-register.md` (R-04 row + body, R-10 add).
4. Edit `docs/adr/0010-clone-gcp-project-isolation.md` (supersession banner).
5. Edit `CLAUDE.md` (Forbidden inventory + HITL row 6 + Risk Matrix R-04 + Key Files).
6. Edit `README.md` (HITL row 6 + ADR-0010/-0011 cross-link).
7. Open PR #30 (Phase A). After merge: continue with Phase B (Cloudflare), Phase C (Project Factory), Phase D (Telegram).

**Outcome:** pending PR #30 merge.

---

## 2026-05-01 — bootstrap.yml Phase 3 green end-to-end (closes the ADR-0009 → ADR-0010 chain)

**Agent:** Claude Code (claude-opus-4-7), session `claude/journal-bootstrap-phase3-green`
**Trigger:** PR #28 merged. Per the original session task — "after the mutation is green, dispatch bootstrap.yml with `skip_terraform=true`, `skip_railway=false`, `dry_run=false`. Verify Phase 3 (`inject-railway-variables`) completes successfully."

**Dispatch:** `bootstrap.yml` run `25217007545` on commit `3c1cbb5` (post-PR-#28 head of main).

**Outcome — all five top-level jobs converged:**

| Phase / Job | Conclusion | Notes |
|-------------|------------|-------|
| `generate-and-inject-secrets` (Phase 1) | ✅ success | New versions for `n8n-encryption-key`, `n8n-admin-password-hash`, `n8n-admin-password-plaintext`; OpenRouter runtime key reprovisioned. |
| `terraform-apply` (Phase 2) | skipped | `inputs.skip_terraform == 'true'` per the dispatch payload. |
| `inject-railway-variables` (Phase 3) | ✅ success | Both `Inject n8n service variables` and `Inject agent service variables` steps succeeded. |
| `github-app-registration` (Phase 4) | skipped | `vars.GITHUB_ORG && vars.APP_NAME` unset (expected — this is the template-builder, not a child instance, per CLAUDE.md HITL row 9). |
| `bootstrap-summary` | ✅ success | Final summary printed. |

**Phase 3 step-level evidence (the focal milestone):**

1. `Authenticate to GCP (WIF)` — ✅ WIF token exchange against `vars.GCP_WORKLOAD_IDENTITY_PROVIDER`.
2. `Set up Cloud SDK` — ✅ gcloud installed.
3. `Retrieve secrets from Secret Manager` — ✅ fetched the `n8n-*` keys + `openrouter-*` keys + the four `railway-*-id` IDs added by ADR-0009 / written live by `apply-railway-provision.yml` run `25216580152` (state=A on adopted orphan `ff709798-…`).
4. `Inject n8n service variables` — ✅ `variableCollectionUpsert` on n8n service with the 9 env vars (encryption key, admin owner, runtime gates).
5. `Inject agent service variables` — ✅ `variableCollectionUpsert` on agent service with the 11 env vars (OpenRouter runtime/management/budget, rate-limit knobs, `TELEGRAM_CHAT_ID`).

**What this proves end-to-end:**

- The ADR-0009 storage pivot (GitHub Variables → GCP Secret Manager) works: bootstrap.yml's `steps.secrets.outputs.railway_*_service_id` outputs correctly drive both inject jobs.
- The Cloudflare 1010 UA + Accept header pair is in force across every Railway GraphQL call (probe + provisioner + bootstrap).
- The classifier fix from PR #27 produced correct, persistent IDs that survive across workflow boundaries.
- The full autonomous bootstrap chain is functional from `tools/grant-autonomy.sh` through Phase 3 — zero operator action required since the ADR-0007 handshake.

**Closes the original session task:** the Railway provisioning gap that PR #15 left open is now closed. Future sessions can layer on top — n8n flow imports, real Telegram `/health` checks, etc.

**Next-session candidates (not in scope here):**

- Implement the deferred `grant-autonomy.sh` collision-detection check from ADR-0010 before any second clone of this template.
- E2E n8n workflow validation (`telegram-route.json`, `health-check.json`, etc.) once env vars have propagated and Railway has redeployed both services.
- ADR-0011 to track Railway's `service.serviceInstances.edges[*].node.domains.serviceDomains` polling result over time (when do domains actually surface for these two services?).

---

## 2026-05-01 — ADR-0010 (clone GCP project isolation) + bootstrap-state secrets reconciliation

**Agent:** Claude Code (claude-opus-4-7), session `claude/adr-0010-clone-isolation`
**Trigger:** Operator question after PR #27 merge — "shouldn't every clone of this template get its own GCP project? That was the goal." A correct, important question. The codebase had no `gcloud projects create` anywhere, no per-secret prefix, and no documented per-clone GCP-project contract — meaning two clones bootstrapped against the same `GCP_PROJECT_ID` would silently overwrite each other's kebab-case secrets (now including `railway-project-id` etc. that ADR-0009 just added).

**Investigation (proof of the gap):**
- `terraform/gcp.tf` — zero `google_project` resources; only `google_project_service` and IAM/SA bindings on `var.gcp_project_id`.
- `tools/grant-autonomy.sh:32`: `: "${GCP_PROJECT_ID:?GCP_PROJECT_ID must be exported}"` — requires the operator to bring an existing project; never creates one. `:58`: `gcloud projects describe` (read-only).
- `bootstrap.yml:62`: `GCP_PROJECT_ID: ${{ vars.GCP_PROJECT_ID }}` — per-repo Variable.
- Three options surfaced for closing the gap (per-clone agent-created project / per-secret prefix / per-clone operator-created project). Operator chose **Option C: per-clone operator-created GCP project**.

**Decision (ADR-0010):** Each child instance MUST live in its own operator-provided GCP project. The GCP project boundary IS the secret namespace boundary; ADR-0006 kebab-case canon stays un-prefixed. The single permitted operator action under ADR-0007 (`tools/grant-autonomy.sh`) is "per child instance", not "once globally" — explicitly clarified in the ADR + README + CLAUDE.md HITL row 1. A collision-detection safety check in `grant-autonomy.sh` is deferred to the next ADR; it lands before the first real second-clone.

**Side outcome (apply-railway-provision.yml first green run, post-PR #27):**

Run `25216580152` on commit `ff266c3` succeeded with `state=A project=ff709798-aa1b-4c52-9a1f-f30b3294f2aa` — the new aggregated classifier (`me.projects` ∪ `me.workspaces[*].projects`, dedupe-by-id) correctly adopted one of the two debugging-cycle orphans without creating a third project. Four GCP secrets written:

- `railway-project-id`       = `ff709798-aa1b-4c52-9a1f-f30b3294f2aa`
- `railway-environment-id`   (production environment of the adopted project)
- `railway-n8n-service-id`   (n8n service in adopted project)
- `railway-agent-service-id` (agent service in adopted project)

Both `n8n` and `agent` services warned `no domain yet (env vars pending)` — expected per ADR-0009 polling soft-fail; Phase 3 will redeploy.

`docs/bootstrap-state.md` reconciled in this PR: `32 secrets present` → `36 secrets present` with the four `railway-*-id` rows added.

**Plan for this session:**
1. Author ADR-0010 (Option C contract).
2. Update README.md "Single bootstrap action" — explicit per-clone GCP project requirement.
3. Update CLAUDE.md HITL row 1 + Key Files table.
4. Update bootstrap-state.md (count + 4 rows).
5. Open PR #28. After merge: dispatch `bootstrap.yml` Phase 3 (skip_terraform=true, skip_railway=false, dry_run=false) — must complete with both `Inject … service variables` reporting `✅ … injected`.

**Outcome:** Pending PR #28 merge + `bootstrap.yml` dispatch.

---

## 2026-05-01 — ADR-0009 (Railway mutation workflow) + apply-railway-provision.yml

**Agent:** Claude Code (claude-opus-4-7), session `claude/adr-0009-railway-mutation`
**Trigger:** Operator request — close the loop opened by ADR-0008. The probe ran live (run id `25214901719`) and returned `state=C` (zero projects). `bootstrap.yml` Phase 3 (`inject-railway-variables`) is gated on four `RAILWAY_*` GitHub Variables that no workflow currently produces. ADR-0007 forbids any operator action, so the build agent must own end-to-end Railway provisioning.

**Session-start ritual:** ✅ Verified. `docs/bootstrap-state.md:131-138` records WIF provider ACTIVE; autonomy is granted.

**Plan:**
1. Author ADR-0009 (MADR, Status: Accepted) — covers state-A/B/C dispatch, idempotency, Cloudflare 1010 immunity (UA + Accept), failure semantics, header contract.
2. Write `.github/workflows/apply-railway-provision.yml` — `workflow_dispatch` + a path-scoped `pull_request` trigger so the workflow self-registers on the PR that introduces it (mirrors `probe-railway.yml`). PR-trigger runs are probe-only; mutations and Variable writes only fire on `workflow_dispatch`.
3. Open PR, dispatch on the branch (which won't work — `workflow_dispatch` REST API only resolves workflows on the default branch), so the real verification is: merge first, then dispatch on `main`.
4. After mutation green: dispatch `bootstrap.yml` with `skip_terraform=true`, `skip_railway=false`, `dry_run=false`. Phase 3 must complete with both `Inject n8n service variables` + `Inject agent service variables` reporting `✅ … injected`.
5. Update `docs/bootstrap-state.md` with the four new Variables; update `CLAUDE.md` Key Files; close ADR-0009's Validation section with the live run ids.

**Header contract (proven live in ADR-0008):**

```
User-Agent: autonomous-agent-template-builder/1.0 (+apply-railway-provision.yml)
Accept:     application/json
```

**Risks noted before dispatch:**
- `projectCreate` may fail for reasons we haven't seen (e.g. account in trial-cooldown after the operator's recent dashboard exploration). Mitigation: surface the raw response in step summary + annotation, never delete-and-retry (per ADR-0009 failure semantics).
- `serviceConnect` triggers an immediate deploy that will fail (no env vars yet). This is **expected** and benign per ADR-0008 → Consequences. The polling step is soft-fail for the same reason.
- The `me` query and the chained `projectCreate`/`serviceCreate`/`serviceConnect` mutations all flow through the same Cloudflare-fronted `backboard.railway.app` endpoint. The probe proved the UA + Accept headers pass; the mutation workflow uses the same pair.

**Outcome:** ✅ ADR-0009 + workflow merged through PRs #24 (initial), #25 (`workspaceId` fix after live API drift), #26 (token-fallback attempt). Three live `workflow_dispatch` runs (`25215413434`, `25215551564`, `25215937519`) revealed two compounding issues that drove a final pivot in PR #27:

1. **Classifier missed workspace-scoped projects.** `me.projects` returns only personal-scope projects; `projectCreate(workspaceId=...)` puts new projects under the workspace, so each re-run classified `state=C` and created another `autonomous-agent` project. Two orphans now exist (`d6564477-…`, `ff709798-…`) and remain in Railway non-destructively per ADR-0009 failure semantics. The classifier now queries both `me.projects` and `me.workspaces[*].projects { edges { node {…} } }`, dedupes by `id`, and adopts the duplicate with the most services.

2. **GitHub Variables write requires a PAT we cannot provision.** `PATCH /repos/.../actions/variables/{name}` returns 403 (`Resource not accessible by integration`) for `GITHUB_TOKEN` even with `actions: write`; the required permission (`Variables: write` / `actions_variables:write`) is not exposed via workflow `permissions:`. ADR-0007 forbids asking the operator for a PAT, so the storage backend pivoted to **GCP Secret Manager** under kebab-case canon (ADR-0006): `railway-project-id`, `railway-environment-id`, `railway-n8n-service-id`, `railway-agent-service-id`. The runtime SA already has `secretmanager.admin`. `bootstrap.yml` Phase 3 was updated in the same PR to read these from Secret Manager via the same WIF auth path it uses for `n8n-encryption-key` etc.

PR #27 (`claude/adr-0009-gcp-storage-and-classifier`) ships both fixes. After it merges and the workflow dispatches green, the next step is the planned `bootstrap.yml` Phase 3 dispatch.

---

## 2026-05-01 — ADR-0008 (Railway provisioning) + read-only probe workflow

**Agent:** Claude Code (claude-opus-4-7), session `claude/railway-probe-and-adr-0008`
**Trigger:** Operator asked whether Phase 3 of `bootstrap.yml` (`inject-railway-variables`) can be unblocked autonomously, and to back any answer with internet research before implementing.

**Why this matters now.** Phase 3 of `bootstrap.yml` runs `variableCollectionUpsert` GraphQL mutations against existing Railway services (`bootstrap.yml:347-460`), gated on `vars.RAILWAY_N8N_SERVICE_ID != ''` and `vars.RAILWAY_AGENT_SERVICE_ID != ''`. The repo defines two services (`railway.toml` for `agent`, `railway.n8n.toml` for `n8n`) but contains zero automation that **creates** them — `tools/bootstrap.sh:220-223` literally documents `export RAILWAY_*_SERVICE_ID=... (from service settings)` (manual). On a fresh template clone (state C — see ADR), the Phase 3 step silently no-ops; the system never deploys. Per ADR-0007, asking the operator to click in the Railway dashboard is forbidden, so the build agent must own this.

**Internet research conducted before implementation:**
- Railway public GraphQL endpoint, auth model, mutation surface — confirmed via `docs.railway.com/integrations/api`, `docs.railway.com/guides/api-cookbook`, `docs.railway.com/integrations/api/manage-services`, Postman public collection `postman.com/railway-4865/railway/...`.
- `serviceCreate` + `source.repo` is documented but unreliable per `station.railway.com/questions/help-problem-processing-request-when-ecb49af7` — the working pattern is `serviceCreate(name, projectId)` then a separate `serviceConnect(id, {repo, branch})`.
- `me` query returns the personal account's projects/services/environments — but **only with an account token** (project/workspace tokens cannot use `me`). Per `runbooks/bootstrap.md:135-137` our `RAILWAY_API_TOKEN` is an account token.
- Free trial: $5 credits, 30-day expiry, 5-services-per-project cap. Hobby plan $5/mo. Two services (n8n + agent) is well under the cap.
- WebFetch was 403-blocked by Cloudflare on docs.railway.com pages, so the verification came from search-snippet quotes plus the existing working `variableCollectionUpsert` invocation in `bootstrap.yml:402-422` (which already proves endpoint + auth model).

**Decision (ADR-0008):** introduce a read-only `probe-railway.yml` workflow that runs the `me { projects { id name services { id name } environments { id name } } }` query, classifies the operator's account into one of three states (A: project + both services exist; B: project exists, services missing; C: nothing exists), and emits the result to the `$GITHUB_STEP_SUMMARY`. The probe is fail-closed read-only — no mutations. Mutation work (the actual `projectCreate` / `serviceCreate` / `serviceConnect` plumbing) is deferred to a follow-up session that consumes the probe's classification.

**Plan for this session:**
1. Create branch `claude/railway-probe-and-adr-0008` (done above this entry).
2. Write `docs/adr/0008-railway-provisioning.md` (MADR template, Status: Accepted, full state-A/B/C analysis).
3. Write `.github/workflows/probe-railway.yml` (`workflow_dispatch`, single Python step, no auth besides `secrets.RAILWAY_API_TOKEN`).
4. Dispatch the probe via REST API; read step-summary to determine state A/B/C.
5. Append the probe outcome to ADR-0008 ("Probe result, 2026-05-01: state X").
6. Update `CLAUDE.md` Key Files table; risk-register if new R-XX is appropriate.
7. Open PR.

**Risks noted before dispatch:**
- The probe might 401 if `RAILWAY_API_TOKEN` is a project/workspace token rather than an account token — `me` would fail. Mitigation: surface the raw error in step summary; if 401, pivot to `projects { ... }` directly with the token's scope.
- The endpoint `backboard.railway.app` may have rebranded to `backboard.railway.com` — `bootstrap.yml:402` still uses `.app` and works, so I'm sticking with it for the probe; if it 30x-redirects we'll learn from the response.

**Outcome:** ✅ Probe green on 3rd attempt (run id `25214901719`, commit `87fd479`). Classification: **state = C** (zero projects in the operator's Railway account). ADR-0008 updated with full result.

### Iteration log

1. **Run 1 (commit `7558e44`) — failure: exit code 1, no body in annotations.**
   The probe wrote diagnostics to `$GITHUB_STEP_SUMMARY` only. The check-runs API returns `output.summary` as empty, and the step-summary file lives behind an Azure log blob (`productionresultssa2.blob.core.windows.net`) the sandbox can't reach. Annotations only contained the generic exit-code note.
   **Fix (commit `efb9f6f`):** also emit the failure body via `::error title=...::<json>` so it lands in the check-runs annotations endpoint.

2. **Run 2 (commit `efb9f6f`) — failure: HTTP 403 / Cloudflare error `1010`.**
   The annotation now exposed the actual response: `{"_http_error": 403, "_body": "error code: 1010"}`. Cloudflare Browser Integrity Check rejected the default `Python-urllib/3.x` User-Agent.
   **Fix (commit `87fd479`):** add `User-Agent: autonomous-agent-template-builder/1.0 (+probe-railway.yml)` and `Accept: application/json` headers.

3. **Run 3 (commit `87fd479`) — success.**
   Annotation: `Railway probe state=C projects=0`. The `me.projects.edges = []` payload confirms an authenticated account with zero projects.

### Side-effect: latent bug discovered in `bootstrap.yml` — fixed in this PR

`bootstrap.yml:402-410` and `:454-459` (the n8n + agent `variableCollectionUpsert` blocks) used the same `urllib` pattern with the same missing UA/Accept headers. When Phase 3 finally runs (after ADR-0009 provisions the services), it would hit Cloudflare 1010 the same way. Patched during /simplify cleanup so ADR-0009 doesn't carry the fix. Both blocks now send `User-Agent: autonomous-agent-template-builder/1.0 (+bootstrap.yml)` and `Accept: application/json`.

### Next steps (for the next session, ADR-0009 scope)

1. Author ADR-0009 — Railway mutation workflow.
2. Write `apply-railway-provision.yml` workflow:
   - Re-run the probe (or accept its prior classification as a workflow input).
   - For state C: `projectCreate(name='autonomous-agent')` → capture `id` + `defaultEnvironment.id` → `serviceCreate × 2` → `serviceConnect × 2` (`repo='edri2or/autonomous-agent-template-builder'`, `branch='main'`) → poll for `serviceDomain` → write 4 GitHub Variables: `RAILWAY_PROJECT_ID`, `RAILWAY_ENVIRONMENT_ID`, `RAILWAY_N8N_SERVICE_ID`, `RAILWAY_AGENT_SERVICE_ID`.
   - All requests must include the `User-Agent` + `Accept` headers proven here.
3. Patch `bootstrap.yml:402-410` and `:431-454` in the same PR — same UA fix.
4. Re-dispatch `bootstrap.yml` with `skip_terraform=true`, `skip_railway=false` and verify Phase 3 successfully injects env vars.

---

## 2026-05-01 — First post-autonomy `bootstrap.yml` dispatch (skip_terraform + skip_railway)

**Agent:** Claude Code (claude-opus-4-7), session `claude/bootstrap-verification-setup-XapRm`
**Trigger:** Operator request — exercise Phase 1 of `bootstrap.yml` autonomously now that `tools/grant-autonomy.sh` has populated `GCP_WORKLOAD_IDENTITY_PROVIDER`. Per ADR-0007, no further operator action permitted; this is the agent's first end-to-end use of WIF.

**Session-start ritual:** ✅ Verified. `docs/bootstrap-state.md:131-138` records WIF provider `projects/974960215714/locations/global/workloadIdentityPools/github/providers/github` ACTIVE since 2026-05-01. Autonomy granted, proceed.

**Plan:**
1. `mcp__github__` `workflow_dispatch` of `.github/workflows/bootstrap.yml` on the working branch with `skip_terraform=true`, `skip_railway=true`, `dry_run=false`.
2. With `vars.GITHUB_ORG` and `vars.APP_NAME` unset, the `github-app-registration` gate evaluates false (`bootstrap.yml:472`) and that phase is skipped. Only Phase 1 (`generate-and-inject-secrets`) executes.
3. Expected delta in GCP Secret Manager: 4 new secret containers — `n8n-encryption-key`, `n8n-admin-password-hash`, `n8n-admin-password-plaintext`, `openrouter-runtime-key`. New versions added on existing containers (`telegram-bot-token`, `cloudflare-api-token`, `cloudflare-account-id`, `openrouter-management-key`, `railway-api-token`). Total container count: 28 → 32.

**Risk noted before dispatch:** the inject step on `bootstrap.yml:162-166` references `vars.GITHUB_APP_ID`, `vars.GITHUB_APP_INSTALLATION_ID`, and `secrets.GITHUB_APP_PRIVATE_KEY`, which have not been populated yet (they are produced by the `github-app-registration` job, which is gated off in this run). If those expand to empty strings, `gcloud secrets versions add --data-file=-` may reject the empty payload. If the run fails on that, the diagnosis + fix will be appended below.

**Outcome:** ✅ Phase 1 green on the third dispatch (run 25213902199, head `a7cd62e`). Took two preceding workflow fixes to get there — none of them required operator intervention (per ADR-0007).

### Run 1 — dispatch rejected by GitHub at parse time (HTTP 422)

```
{
  "message": "Invalid Argument - failed to parse workflow: (Line: 171, Col: 13):
    Unrecognized named-value: 'secrets'.
    Located at position 30 within expression:
      inputs.dry_run == 'false' && secrets.OPENROUTER_MANAGEMENT_KEY != ''",
  "status": "422"
}
```

GitHub Actions does not allow `secrets.*` in step-level `if:` conditions (the `secrets` context is restricted to `with:`, `env:`, and `run:` bodies). The bad expression was on `bootstrap.yml:171`, gating the `Provision OpenRouter runtime key` step. The whole workflow file failed validation, so no run could be created at all.

**Fix (commit `8fc0f1e`):** dropped the `secrets.OPENROUTER_MANAGEMENT_KEY != ''` clause; left only `inputs.dry_run == 'false'`. The provisioning script (`tools/provision-openrouter-runtime-key.sh`) reads the management key from GCP Secret Manager directly and is fail-loud + idempotent, so the inline guard was redundant.

### Run 2 — `25213770552` failed in `Inject secrets into GCP Secret Manager`

Predicted in the pre-flight section above. With `vars.GITHUB_APP_ID`, `vars.GITHUB_APP_INSTALLATION_ID`, and `secrets.GITHUB_APP_PRIVATE_KEY` all empty (those are minted later by the `github-app-registration` job, gated off by `vars.GITHUB_ORG && vars.APP_NAME`), `inject_secret` invoked `printf '%s' "" | gcloud secrets versions add ... --data-file=-`, and gcloud rejects empty payloads.

**Fix (commit `eb2efc6`):** `inject_secret` now no-ops on empty input and prints `↷ Skipping <name> (empty value — will be populated by a later phase)`. Generated and pre-existing secrets are still written; bootstrap-managed-but-not-yet-provisioned secrets (the GitHub App quartet) are correctly deferred without aborting the step.

### Run 3 — `25213839506` failed in `Provision OpenRouter runtime key`

Inject step now ✓. The provisioning script then aborted because `gcloud secrets versions add openrouter-runtime-key` requires the secret container to already exist, and on a fresh project it does not (`bootstrap-state.md` had it listed as "Missing — auto-provisioned"). The script uses `versions add`, not `secrets create`, so the first run on a fresh project always failed.

**Fix (commit `a7cd62e`):** Before the `versions add`, the script now `gcloud secrets describe`s the container and, if missing, creates it with `--replication-policy=automatic`. Subsequent runs continue to short-circuit on the existing-version idempotency check at the top.

### Run 4 (third dispatch on `a7cd62e`) — `25213902199` ✅ green

All Phase 1 steps succeeded. Skipped jobs (`Terraform apply`, `Inject Railway environment variables`, `Register GitHub App (2-click)`) were intentionally gated off via `skip_terraform=true`, `skip_railway=true`, and unset `vars.GITHUB_ORG`/`vars.APP_NAME` — exactly as the operator specified.

### State delta

GCP Secret Manager containers: 28 → 32. New containers:

| Name | Why | Source |
|------|-----|--------|
| `n8n-encryption-key` | n8n credential encryption | `bootstrap.yml:106-111` (CSPRNG hex 32B) |
| `n8n-admin-password-hash` | n8n owner login (R-06) | `bootstrap.yml:113-131` (bcrypt) |
| `n8n-admin-password-plaintext` | sister of `-hash` (operator visibility) | `bootstrap.yml:154` |
| `openrouter-runtime-key` | n8n runtime LLM gateway, $10/day cap (ADR-0004) | `tools/provision-openrouter-runtime-key.sh` via Management API |

`docs/bootstrap-state.md` and `CLAUDE.md` Secrets Inventory updated to reflect the new state. Three remaining bootstrap-managed-but-missing secrets are the GitHub App quartet (`github-app-id`, `github-app-private-key`, `github-app-webhook-secret`, `github-app-installation-id`); those will be created when the `github-app-registration` job is exercised on a future dispatch with `vars.GITHUB_ORG` and `vars.APP_NAME` set.

### Notes for the next session

- Workflow log files are served from `productionresultssa2.blob.core.windows.net`, which is not in the sandbox proxy allowlist — i.e. raw step logs cannot be read from this environment. Diagnosing failed steps relies on the `runs/<id>/jobs` step-level metadata + reading the workflow source. The two runtime fixes here were both inferred from step-level metadata only.
- The `secrets`-in-`if:` guardrail is general; if any new step-level conditional needs to depend on a secret's presence, indirect via a job-level env mapping (`env: HAS_SECRET: ${{ secrets.X != '' }}`) and check `env.HAS_SECRET == 'true'` instead.

---

## 2026-05-01 — `tools/grant-autonomy.sh` executed: ✅ AUTONOMY GRANTED

**Operator action (the one and only, per ADR-0007):** `edriorp38@or-infra.com` ran `tools/grant-autonomy.sh` in GCP Cloud Shell. The script completed with `✅ AUTONOMY GRANTED` banner. No SA keys minted, stored, or shipped.

### Cloud Shell flow that worked end-to-end

1. `gh auth login` — interactive device-flow (`Login with a web browser`). Token persisted to `~/.config/gh/hosts.yml`. `GH_TOKEN` env var was unset first because Cloud Shell had a stale invalid token (verified: `curl -sH "Authorization: Bearer $GH_TOKEN" https://api.github.com/user` returned `Bad credentials`).
2. `gh repo clone edri2or/autonomous-agent-template-builder` — used gh's stored auth, succeeded where raw `git clone` had failed.
3. `GH_TOKEN="$(gh auth token)" GITHUB_REPO=... GCP_PROJECT_ID=... bash tools/grant-autonomy.sh` — passed the token only as a subprocess env var; never `export`ed to the shell, never written to history.

### State delta caused by the handshake

**GCP project `or-infra-templet-admin` (number 974960215714):**
- 4 GCP APIs enabled: `iam`, `iamcredentials`, `sts`, `cloudresourcemanager` (Step 1, `tools/grant-autonomy.sh:62-73`).
- GCS bucket `or-infra-templet-admin-tfstate` created with versioning + uniform access (Step 2).
- Service account `github-actions-runner@or-infra-templet-admin.iam.gserviceaccount.com` created (Step 3) — federation-only, no keys.
- 9 project-level IAM roles granted to the runtime SA (Step 4): `secretmanager.secretAccessor`, `secretmanager.admin`, `storage.admin`, `iam.serviceAccountAdmin`, `resourcemanager.projectIamAdmin`, `serviceusage.serviceUsageAdmin`, `run.admin`, `artifactregistry.admin`, `iam.workloadIdentityPoolAdmin`.
- WIF pool `github` created at `projects/974960215714/locations/global/workloadIdentityPools/github` (Step 5).
- WIF provider `github` created with OIDC issuer `https://token.actions.githubusercontent.com` and attribute condition `assertion.repository == 'edri2or/autonomous-agent-template-builder'` (Step 5).
- `roles/iam.workloadIdentityUser` binding from the WIF principalSet to the runtime SA (Step 6).

**GitHub repository `edri2or/autonomous-agent-template-builder`:**
- 6 Variables set via REST API (Step 7): `GCP_PROJECT_ID`, `GCP_REGION`, `GCP_WORKLOAD_IDENTITY_PROVIDER`, `GCP_SERVICE_ACCOUNT_EMAIL`, `TF_STATE_BUCKET`, `N8N_OWNER_EMAIL`.
- 4 Secrets synced GCP→GitHub via libsodium sealed-box (Step 8): `TELEGRAM_BOT_TOKEN`, `CLOUDFLARE_API_TOKEN`, `OPENROUTER_MANAGEMENT_KEY`, `RAILWAY_API_TOKEN`.

**GCP Secret Manager total count is unchanged at 28.** The sync step adds new versions on existing secret containers; no new containers were created. The Jest invariants test continues to pass.

### Documentation updates in this entry's PR

- `docs/bootstrap-state.md` header `Last verified` line updated to mark the handshake.
- Workload Identity Federation section: `EMPTY` → real pool/provider details.
- Service Accounts section: `EMPTY` → `github-actions-runner` with full role set.
- GCS Buckets section: `EMPTY` → `or-infra-templet-admin-tfstate` with versioning details.
- Required APIs section: removed (all four formerly-missing APIs are now enabled).
- Project IAM section: 9 new role bindings listed under the runtime SA.
- New "GitHub Variables and Secrets (post-handshake)" section.
- "Single remaining operator action" → "Handshake completed". The contract is now in its post-handshake state.

### Operator-facing gotcha worth recording (for future template instances)

The Cloud Shell environment may carry a stale `GH_TOKEN` env var from prior sessions or `.bashrc` provisioning. Pre-existing `GH_TOKEN` blocks `gh auth login` from running its interactive flow (gh defers to env vars). Recovery sequence:

```bash
unset GH_TOKEN
gh auth login                            # device-flow, persistent in ~/.config/gh/
gh repo clone edri2or/autonomous-agent-template-builder
cd autonomous-agent-template-builder
GH_TOKEN="$(gh auth token)" \
  GITHUB_REPO=edri2or/autonomous-agent-template-builder \
  GCP_PROJECT_ID=or-infra-templet-admin \
  bash tools/grant-autonomy.sh
```

This sequence keeps the PAT in `~/.config/gh/hosts.yml` (Cloud Shell persistent disk) and never in shell history, scrollback, or environment beyond the single grant-autonomy subprocess. Worth folding into the runbook and possibly the script itself (auto-detect stale token + auto-prompt) — left as a follow-up.

### What the next session does

The session that follows this one reads `CLAUDE.md`, performs the session-start verification ritual, observes that `GCP_WORKLOAD_IDENTITY_PROVIDER` is set, declares autonomy granted, and proceeds to run the initial bootstrap (`workflow_dispatch` of `bootstrap.yml` with `skip_terraform=true skip_railway=true`, no `GITHUB_ORG`/`APP_NAME`). It must not request any operator action — ADR-0007 binds it.

**Validation:** `npm test` 69 tests pass on this branch; markdown invariants test still passes (28 secrets count unchanged); `markdownlint-cli2` 0 errors locally; YAML valid.

**Next steps:** none from operator. From the next agent session: trigger Phase 1 of bootstrap.yml; expected new GCP secrets `n8n-encryption-key`, `n8n-admin-password-hash`, `n8n-admin-password-plaintext`, `openrouter-runtime-key` (4 new → 32 total); update inventory invariant accordingly.

---

## 2026-05-01 — Doc-lint CI: lychee + markdownlint-cli2 + Jest invariants

**Agent:** Claude Code (claude-opus-4-7)
**Branch:** `claude/doc-lint-ci`
**Trigger:** PR #19 surfaced that top-level docs PRs run zero CI checks (`documentation-enforcement.yml` path filter excludes `*.md` at root and most of `docs/`). Hand-audited /simplify runs caught real defects (PR #15 count "9" vs 13 actual; PR #16 "70+ call sites" unverifiable; PR #19 audit briefly flagged a phantom 28-vs-31 mismatch). Goal: automate this class of catch.

**Research conducted (parallel agents, web + codebase):**
- 2026 link-check consensus: `lycheeverse/lychee-action@v2` (Rust-fast, mature). The popular `gaurav-nelson/github-action-markdown-link-check` wrapper is **deprecated** ([repo](https://github.com/gaurav-nelson/github-action-markdown-link-check)). Industry pattern (GitLab Docs, Grafana Writers' Toolkit) splits internal-on-PR + external-on-cron.
- 2026 markdown linter consensus: `DavidAnson/markdownlint-cli2-action@v20`, author-recommended for new projects ([dlaa.me](https://dlaa.me/blog/post/markdownlintcli2)).
- Custom invariants ("claim N items, table must have N rows"): no canonical linter — Vale is token-level not structural. Repo already runs Jest (68 tests, `src/agent/tests/router.test.ts` pattern). Extending Jest beats new tooling.

**Files added:**
- `.github/workflows/doc-lint.yml` — four jobs: `markdownlint`, `link-check-internal` (lychee `--offline`), `link-check-external` (lychee, scheduled cron + manual dispatch only — never blocks PRs), `invariants` (Jest).
- `.markdownlint-cli2.jsonc` — strict baseline minus 16 disabled cosmetic rules. Disabled: MD013 (line length), MD041 (first-line H1), MD024 (duplicate headings — JOURNEY entries repeat dates), MD033 (inline HTML), MD036, MD040, MD060 (table column style), MD032 (blanks-around-lists), MD034 (bare URLs), MD022 (blanks-around-headings), MD031 (blanks-around-fences), MD009 (trailing spaces), MD007 (ul-indent), MD025 (multiple H1), MD047 (final-newline), MD049 (emphasis-style), MD012 (multiple-blank-lines). Kept: MD001 (heading increment), MD026 (no trailing punctuation in heading), MD058 (blanks-around-tables), and the rest of `default: true`. Local run on full repo: 0 errors with this config.
- `.lycheeignore` — placeholder hostnames (`YOUR_N8N_URL`, `<n8n-service>-<project>.up.railway.app`, `claude.ai/code/session_*`) so external-link cron never flags illustrative URLs.
- `src/agent/tests/markdown-invariants.test.ts` — Jest suite with `rowsAfterClaim` helper. First invariant: "N secrets present" line in `docs/bootstrap-state.md` matches the row count of the immediately following table. Future invariants are additive — same helper.

**Reactive fixes:**
- `docs/bootstrap-state.md:58` — removed trailing colon in `### Required APIs still **missing** (...)` heading (MD026).
- Two leftover `deep-research-report*.md` files in repo root added to lint ignores; not part of active architecture, retroactive cleanup not justified.

**Validation:**
- `npm test` — 69 tests pass (was 68; new invariants test adds 1).
- `npx markdownlint-cli2` locally on full repo — 0 errors with the chosen config.
- `bash -n` not applicable (no new shell scripts in this PR).
- The `invariants` Jest job is wired into `doc-lint.yml`; the existing `npm test` invocation in `deploy.yml` already covers it implicitly on push to main.

**Trigger / blast radius:**
- New workflow runs on `pull_request` with paths `**/*.md`, `.markdownlint-cli2.jsonc`, `.lycheeignore`, `.github/workflows/doc-lint.yml`.
- Schedule cron weekly Mon 06:00 UTC for external links, never blocks a PR.
- Failure recovery: typo → CI fails → operator pushes a fix commit on the same branch → CI re-runs. No new PR needed.

**What this does NOT cover (deferred per ADR notes only — no new ADR required):**
- Vale prose linting / spelling — too noisy for a multi-register, English+Hebrew docs corpus.
- markdownlint auto-fix on push — defer until rule set stabilizes.
- Issue auto-creation when external-link cron fails (`peter-evans/create-issue-from-file`) — defer until external rot is observed.

**Forbidden Words check (ADR-0007 self-audit):** this entry contains zero "Run this in Cloud Shell" / "manually set" / "click [button]" / operator-CLI-invocation strings. ✓

**Next steps:** none required from operator. Future docs PRs now run four lint jobs automatically; existing /simplify reviews can lean on these instead of hand-counting.

---

## 2026-05-01 — `OPENROUTER_API_KEY` deleted from GCP Secret Manager + OpenRouter UI

**Operator action:** the operator deleted `OPENROUTER_API_KEY` (vanilla inference key, no daily cap, OpenRouter internal name `130-2`, label `sk-or-v1-dc7...c98`) from both GCP Secret Manager and the OpenRouter dashboard. Confirmed via screenshot of the GCP Secret Manager listing — the alphabetical region `OPENAI_API_KEY → OPENCODE_API_KEY → openrouter-management-key → PERPLEXITY_API_KEY` is contiguous with no `OPENROUTER_API_KEY` between `OPENCODE_API_KEY` and `openrouter-management-key`.

**Rationale:** zero references in code/IaC/workflows. Verification command: `grep -rn 'OPENROUTER_API_KEY\|openrouter-api-key' --include='*.{ts,js,json,yml,yaml,tf,sh,py}' .` → 0 results. ADR-0004 mandates the `openrouter-management-key` (Provisioning) + `openrouter-runtime-key` (auto-minted, $10/day cap) split — the management key covers all provisioning/probing needs (`/credits`, key minting), the runtime key covers all inference, and a third uncapped inference key was both redundant and a budget/security risk.

**Anti-regression directive for future sessions:** This secret is intentionally absent. Do **NOT** attempt to recreate it. If a workflow or skill is missing an OpenRouter capability, route through `openrouter-management-key` (provisioning) or `openrouter-runtime-key` (inference). The canonical record is `docs/bootstrap-state.md` → `### Recently deleted secrets (do not recreate)`. That table is read-only history; if some future use case genuinely needs an additional inference key, mint a new one via the management key with a daily cap, name it kebab-case, and add an ADR justifying the new role — never resurrect this exact name.

**Documentation changes:**
- `docs/bootstrap-state.md` — Secret Manager inventory header changed `29 secrets` → `28 secrets` with a forward reference to the new section; the `OPENROUTER_API_KEY` row was removed from the inventory table; new `### Recently deleted secrets (do not recreate)` section was added with the row above the still-missing-secrets table so future readers encounter the deletion log before any "missing" interpretation.
- `CLAUDE.md` — Secrets Inventory footnote count `29` → `28`; appended a parenthetical pointing to the Recently-deleted log.

**Validation:** documentation-only. `git diff --stat` should show two files. `policy/context_sync.rego` is satisfied (CLAUDE.md and JOURNEY.md both touched). No code, no IaC, no workflow changes.

**Next steps:** none required for this PR. The autonomy bootstrap path (`tools/grant-autonomy.sh`, ADR-0007) is unaffected — it does not reference `OPENROUTER_API_KEY` and never did.

---

## 2026-05-01 — Inviolable Autonomy Contract (ADR-0007) + `tools/grant-autonomy.sh`

**Agent:** Claude Code (claude-opus-4-7)
**Branch:** `claude/inviolable-autonomy-contract`
**Trigger:** Operator demanded an end to drip-fed manual tasks. Verbatim: *"אני פותח את האוטונומיה ל-GCP וזהו. אני לא נודע יותר בכלום. לא ריילוואי, לא n8n, לא יצירת חשבונות ולא כלום. אסור לבקש ממני יותר! ... תחקור על זה במערכת הקיימת ותחקור באינטרנט על הסטנדרט המקצועי ועל האוטונומיה ואל תעז לחזור לכאן בלי פתרון אוטונומי מלא ובטיחותי."*

**Research conducted (parallel agents):**
- Codebase audit: traced full bootstrap call chain. Found two genuine chicken-egg artifacts requiring operator action — (1) GCP trust handshake (per Google WIF docs, no auto-bootstrap exists; cite https://docs.cloud.google.com/iam/docs/workload-identity-federation), (2) GitHub App registration for child instances (2-click manifest flow per github.com policy; 1-click on GHEC preview API per https://github.blog/changelog/2025-07-01-enterprise-level-access-for-github-apps-and-installation-automation-apis/). All else is automatable.
- 2026-era industry standards (web research): Spacelift, Atlantis, Terraform Cloud all converge on "ONE OIDC trust + ONE IAM binding then full autonomy" (https://docs.spacelift.io/integrations/cloud-providers/aws). OWASP Top 10 for Agentic Applications (2025-12-09, https://genai.owasp.org/2025/12/09/owasp-top-10-for-agentic-applications-the-benchmark-for-agentic-security-in-the-age-of-autonomous-ai/) names destructive ops, IAM elevation, and billing as ASI02/ASI03 categories that must remain HITL at runtime, but bootstrap is not a kill-switch category.
- AGENTS.md emerging open standard (https://agents.md/) for unambiguous agent rules; this repo's CLAUDE.md plays the same role.

**Decision:** Codify the Inviolable Autonomy Contract as ADR-0007 and ship `tools/grant-autonomy.sh` as the **single, idempotent, one-time operator action** for the lifetime of any repo that uses this template. The script:
- Enables required GCP APIs.
- Creates the GCS Terraform state bucket.
- Creates the runtime SA and grants it the full role set (Secret Manager, Storage, IAM, Service Usage, Cloud Run, Artifact Registry, WIF pool admin) needed for the agent to operate autonomously.
- Creates the WIF pool and provider, restricted to the exact repo via `assertion.repository`.
- Sets all GCP-related GitHub Variables.
- Syncs platform secrets (`telegram-bot-token`, `cloudflare-api-token`, `openrouter-management-key`, `railway-api-token`) from GCP Secret Manager to GitHub Secrets via libsodium-encrypted REST API calls.
- Verifies the handshake.
- **Never mints an SA key.** WIF is the sole identity backbone from the first GitHub Actions run.

**Actions taken:**
- Created `tools/grant-autonomy.sh` (~250 lines, idempotent).
- Created `docs/adr/0007-inviolable-autonomy-contract.md` (Accepted; supersedes the "STOP and ask" rules in the prior CLAUDE.md autonomy block).
- Inserted `## ⚠️ Inviolable Autonomy Contract` section at the top of `CLAUDE.md` — verbatim Forbidden Words list, session-start verification ritual, distinction between bootstrap (no HITL after handshake) and runtime (ASI02/ASI03 HITL kill switches preserved).
- Updated `CLAUDE.md` Build-Agent Autonomy table — last "Forbidden" row now reads: *"Request **any** manual operator action besides ADR-0007's one-time handshake"*.
- Replaced `CLAUDE.md` "Human-Gated Operations (HITL)" perimeters list with a historical inventory tagged DONE; future sessions must not interpret it as active asks.
- Replaced `docs/bootstrap-state.md` "Open questions for the next session" with a single "Single remaining operator action" pointer to `grant-autonomy.sh`.
- Restructured `docs/runbooks/bootstrap.md` with Path A (`grant-autonomy.sh`, recommended) and Path B (`one-shot.sh`, legacy / fresh-template path).
- Rewrote `README.md` "Bootstrap Prerequisites" → "The single bootstrap action" with the new pre-existing-state table.

**Validation:** Documentation-only on the human side. Functionality of the script will be validated when the operator runs it. Idempotency designed in (every `gcloud create` is guarded by `describe ... || create`). The script's verification step asserts `GCP_WORKLOAD_IDENTITY_PROVIDER` is visible in the GitHub repo Variables before reporting success.

**Forbidden Words enforcement:** Future sessions reading CLAUDE.md must not produce any string in the Forbidden Words list. Enforcement is currently advisory (no machine check); a follow-up could add a self-test that greps the agent's outgoing messages.

**Next steps:** Operator runs `tools/grant-autonomy.sh` ONCE in Cloud Shell. After it succeeds, every subsequent Claude Code session begins with the verification ritual: read this file → confirm `GCP_WORKLOAD_IDENTITY_PROVIDER` is non-empty → proceed with full autonomy.

---

## 2026-05-01 — R-09 jsCode-level coverage for destroy-resource approval flow

**Agent:** Claude Code (claude-opus-4-7)
**Branch:** `claude/continue-work-G15vZ`
**Objective:** Tighten R-09 (`callback_data` trust boundary) test coverage. Existing Jest only asserts the cross-workflow prefix agreement; the actual JS code blocks of `approval-callback.json` (chat.id whitelist, malformed-data parser, missing-`TELEGRAM_CHAT_ID` fail-closed) and `destroy-resource.json` (48-char `resource_id` ceiling that keeps `callback_data` ≤ 64 bytes) had **zero** test coverage. A silent regression in any of these is the difference between a fail-closed and a fail-open authorization gate.

**Pre-planning:**
- Branch was identical to main (no work yet). Repo state: 64 tests passing, build clean, all 5 n8n workflow stubs already migrated to real handlers (PRs #11–#14).
- R-09 was the only Open risk in `docs/risk-register.md` not validated locally; R-01/R-03/R-05 are NEEDS_EXPERIMENT against external infra and not improvable in-repo.
- No documentation drift; no operator-actionable task could be unblocked by code changes.

**Approach chosen:** evaluate the embedded `jsCode` strings in n8n workflows in a sandboxed `new Function(...)` harness with stubbed `$input`, `$env`, `$()`, `require`, `Buffer`. Same harness pattern works for both Code-node bodies because n8n evaluates them as function bodies with `return [...]`.

**Actions taken:**
- Added 4 targeted Jest tests in `src/agent/tests/router.test.ts`:
  1. `approval-callback.json validate-and-parse: missing TELEGRAM_CHAT_ID throws (R-09 fail-closed)`
  2. `approval-callback.json validate-and-parse: chat.id mismatch returns _action='unauthorized'`
  3. `approval-callback.json validate-and-parse: malformed callback_data returns _action='unknown'`
  4. `destroy-resource.json validate-and-extract: resource_id > 48 chars throws (callback_data 64-byte cap)`
- Added a private helper `evalNodeJsCode(workflowFile, nodeId, ctx)` next to the existing workflow-file `describe` block. Single helper, ~15 lines, no new module.

**Validation:**
- `npm test` — 68 tests pass (was 64).
- `npm run build` — clean (`tsc --noEmit`).

**Blockers / Human actions required:** None. No new env vars, no dependency changes, no architectural shifts. Risk register R-09 status updated from "Open" to "Validated (Jest jsCode-level)" with the test names listed alongside the existing prefix-agreement test.

**Next steps:**
- The remaining R-09 manual E2E (real Telegram bot tap from an off-whitelist chat) stays deferred until a Railway environment exists.
- Operator-blocked tasks unchanged: SA key path for first bootstrap, `WEBHOOK_URL` reservation, `GH_ADMIN_TOKEN` PAT minting.

> **NOTE (post-merge):** Three "operator-blocked tasks" listed above were superseded by the Inviolable Autonomy Contract entry directly above (ADR-0007 + `tools/grant-autonomy.sh`). Preserved here unchanged for append-only non-repudiation.

---

## 2026-05-01 — Post-PR #15: Decisions 1 + 2 resolved, GCP secrets reconciled

**Agent:** Claude Code (claude-opus-4-7)
**Branch:** `claude/post-pr15-state-reconciled`
**Objective:** Following PR #15 merge, resolve the three open decisions blocking bootstrap E2E. Update all state-of-the-world docs so the next session begins with accurate, exhaustive context.

**Decisions resolved:**

1. **Naming convention → kebab-case canonical (ADR-0006).**
   Recorded in new `docs/adr/0006-secret-naming-convention.md`. Six kebab-case copies created in GCP Secret Manager by reading values from existing UPPER_SNAKE_CASE originals via `gcloud secrets versions access` and re-injecting via `gcloud secrets create + versions add --data-file=-` (pipe; values never echoed):
   - `cloudflare-account-id`     ← `CLOUDFLARE_ACCOUNT_ID`     (length 32, 09:25:38)
   - `cloudflare-api-token`      ← `CLOUDFLARE_API_TOKEN`      (length 53, 09:25:46)
   - `linear-api-key`            ← `LINEAR_API_KEY`            (length 48, 09:25:54)
   - `linear-webhook-secret`     ← `LINEAR_WEBHOOK_SECRET`     (length 64, 09:26:01)
   - `railway-api-token`         ← `RAILWAY_TOKEN`             (length 36, 09:26:08)
   - `telegram-bot-token`        ← `TELEGRAM_BOT_TOKEN`        (length 46, 09:26:16)
   UPPER_SNAKE originals retained — disposition deferred.

2. **OpenRouter classification → vanilla inference, not Provisioning.**
   Diagnostic against the existing `OPENROUTER_API_KEY`:
   ```
   GET /api/v1/keys     → HTTP 401 {"error":{"message":"Invalid management key","code":401}}
   GET /api/v1/credits  → HTTP 200 {"data":{"total_credits":10,"total_usage":1.30933311}}
   ```
   Followed by Provisioning-key listing (after the new key was created): the existing key has `name: "130-2", label: "sk-or-v1-dc7...c98", limit: null, limit_remaining: null, limit_reset: null` — i.e. no daily cap. Per ADR-0004 the runtime key requires `limit_reset: daily, limit: $10`, so this key is **neither** the management nor the runtime key — it is a vanilla inference key that coexists. The operator created a new Provisioning Key in the OpenRouter UI and stored it as `openrouter-management-key` in GCP at 09:23:50; verification call returned HTTP 200 with the existing key listing. The future `openrouter-runtime-key` will be auto-minted by `tools/provision-openrouter-runtime-key.sh` during `bootstrap.yml`.

3. **Bootstrap-time GitHub admin PAT (former Decision 3) → still open long-term.**
   Solved transiently for the current session only. From the next session, no PAT is available in environment. `bootstrap.yml:258-305` (the auto-update of `GCP_WORKLOAD_IDENTITY_PROVIDER` + `GCP_SERVICE_ACCOUNT_EMAIL` GitHub Variables, plus deletion of `GOOGLE_CREDENTIALS`) requires a `GH_ADMIN_TOKEN` GitHub Secret. Operator must mint a fine-grained PAT (`repo` + `workflow` + `admin:org` scopes, minimal repo scope) and store it, OR accept manual GitHub Variable updates after each `terraform-apply`. Tracked as Open Question 3 in `docs/bootstrap-state.md`.

**State delta in GCP** (vs PR #15 snapshot of 22 secrets):
- 7 new secrets, total **29**, of which **9 in canonical kebab-case** schema. WIF / SA / GCS / Artifact Registry / Cloud Run remain empty (expected pre-bootstrap).

**Actions taken:**
- Created `docs/adr/0006-secret-naming-convention.md` (Accepted).
- Refreshed `docs/bootstrap-state.md` Secret Manager inventory: 22 → 29 rows, six UPPER_SNAKE marked as "Original — kebab copy below", `OPENROUTER_API_KEY` reclassified as Extra (vanilla inference, no daily cap), seven new kebab rows added with creation timestamps and lengths.
- `docs/bootstrap-state.md` "Open decisions blocking bootstrap E2E" replaced with two sections: **Resolved decisions** (1 + 2 with diagnostic record) and **Open questions for the next session** (SA key path, WEBHOOK_URL/Railway state, operator PAT for GitHub admin, disposition of UPPER_SNAKE originals).
- Updated `CLAUDE.md` Secrets Inventory `Status` column: six ⚠️ case-mismatch rows + the ⚠️ Ambiguous OpenRouter row → ✅ Present, with creation timestamps and lengths.
- Updated `CLAUDE.md` reconciliation footnote: 22 → 29; "open decisions blocking" → "resolved decisions per ADR-0006 + open questions for the next session".

**Validation:** documentation-only change. `git diff --stat` should show 4 files: `CLAUDE.md` + `docs/JOURNEY.md` + `docs/bootstrap-state.md` + `docs/adr/0006-secret-naming-convention.md` (new). `policy/context_sync.rego` satisfied — both `CLAUDE.md` and `docs/JOURNEY.md` touched.

**Open questions handed off to next session:**
1. SA key (`GOOGLE_CREDENTIALS`) — A. mint+auto-delete (recommended) vs B. manual WIF.
2. `WEBHOOK_URL` — A. deploy n8n first then capture hostname vs B. reserve Cloudflare DNS in advance.
3. Operator PAT — operator must mint and store as `GH_ADMIN_TOKEN` GitHub Secret.
4. Disposition of UPPER_SNAKE originals after successful bootstrap — defer until kebab copies are validated by E2E.

**Next steps:** operator decides on Open Questions 1 + 2 + 3, then trigger `tools/one-shot.sh` (or directly `bootstrap.yml` from Actions UI).

---

## 2026-05-01 — GCP project state inventory + Secrets Manager reconciliation

**Agent:** Claude Code (claude-opus-4-7)
**Branch:** `claude/bootstrap-e2e-testing-TBik8`
**Objective:** Establish ground-truth snapshot of `or-infra-templet-admin` (project number `974960215714`) before any bootstrap run; reconcile against `CLAUDE.md` Secrets Inventory; surface naming convention conflict and missing operator inputs so future sessions never have to re-ask.

**Method:** Operator ran a read-only `gcloud` inventory in Cloud Shell (full command preserved in `docs/bootstrap-state.md` Refresh section). Output parsed into 10 structured blocks (`PROJECT_META`, `CURRENT_AUTH`, `ENABLED_APIS`, `SECRETS_LIST`, `WIF`, `SERVICE_ACCOUNTS`, `GCS_BUCKETS`, `ARTIFACT_REGISTRY`, `CLOUD_RUN`, `PROJECT_IAM_POLICY`). No `gcloud secrets versions access` was used — secret values never read.

**Findings:**
- **22 secrets present**, predominantly `UPPER_SNAKE_CASE` (e.g. `TELEGRAM_BOT_TOKEN`, `CLOUDFLARE_API_TOKEN`). The codebase, by contrast, uses `lower-kebab-case` exclusively (verified: 70+ references across `CLAUDE.md`, `terraform/variables.tf`, `.github/workflows/bootstrap.yml`, `tools/bootstrap.sh`; zero deviations). Two operator secrets are already kebab-case (`cloudflare-dns-manager-token`, `cloudflare-dns-manager-token-id`).
- **13 "extra" secrets** present beyond the CLAUDE.md inventory: 6 LLM keys (Anthropic, OpenAI, Google, Perplexity, DeepSeek, OpenCode), 1 payment (Stripe), 2 Cloudflare auxiliary tokens, plus `LINEAR_TEAM_ID`, `RAILWAY_WEBHOOK_SECRET`, and 2 IDs that the codebase treats as GitHub Variables rather than Secret Manager entries (`CLOUDFLARE_ZONE_ID`, `TELEGRAM_CHAT_ID`). The LLM keys are useful for future multi-LLM router skills.
- **GCP infra absent** as expected pre-bootstrap: WIF pool/provider EMPTY, no custom service accounts, no GCS buckets, no Artifact Registry repos, no Cloud Run services. `terraform-apply` will create all of these (`bootstrap.yml:191-241`).
- **4 GCP APIs missing** vs `bootstrap.yml:91-104` requirements: `iam`, `iamcredentials`, `sts`, `cloudresourcemanager`. Auto-enabled on first bootstrap.
- **Authn:** `edriorp38@or-infra.com` has `roles/owner`. Sufficient for first-run bootstrap with `GOOGLE_CREDENTIALS` SA key path.

**Actions taken:**
- Created `docs/bootstrap-state.md` — single source of truth snapshot, including the exact refresh command for future sessions.
- Updated `CLAUDE.md` Secrets Inventory (lines 121-136) — added `Status (2026-05-01)` column to all 13 rows, plus reconciliation footnote linking to `docs/bootstrap-state.md`.
- Appended this JOURNEY entry.

**Open decisions** (block bootstrap E2E run, do NOT block this PR):
1. **Naming convention.** Recommend creating kebab-case secrets in GCP via `gcloud secrets create <kebab-name> + versions add` (preserves existing UPPER_SNAKE_CASE for any other consumers). Rationale: 70+ kebab-case references vs zero UPPER_SNAKE_CASE in the codebase; reversing the convention is a multi-file refactor for no architectural gain. Awaiting operator confirmation.
2. **`OPENROUTER_API_KEY` classification.** ADR-0004 requires two distinct keys (`openrouter-management-key` for provisioning + `/credits` probe; `openrouter-runtime-key` auto-minted with `$10/day` cap). Operator must check OpenRouter dashboard to confirm whether the existing key is a provisioning/management type.
3. **`GITHUB_TOKEN` (operator PAT).** Required by `tools/one-shot.sh:79-81` to write GitHub Secrets/Variables and trigger `bootstrap.yml`. Not present anywhere — operator must mint a fine-grained PAT (`repo` + `workflow` scopes) and store as `github-pat` in Secret Manager.

**Validation:** N/A (documentation-only). `git diff --stat` should show 1 new file + 2 edits. `policy/context_sync.rego` is satisfied (both CLAUDE.md and JOURNEY.md touched).

**Blockers / Human actions required:** the 3 open decisions above. No tool/code blocker — `git status` was clean before this session.

**Next steps:**
- Operator resolves the 3 open decisions.
- Follow-up PR: create kebab-case secret aliases in GCP (Decision 1 → if Option B); store `github-pat` (Decision 3); split or rename OpenRouter key (Decision 2).
- After all three resolved: trigger `tools/one-shot.sh` → `bootstrap.yml` end-to-end.

---

## 2026-05-01 — Convert destroy-resource.json from stub to real handler (final stub)

**Agent:** Claude Code (claude-opus-4-7)
**Objective:** Convert the last remaining stub `src/n8n/workflows/destroy-resource.json` (`requires_approval: true`) into a real handler with a Telegram inline-keyboard approval gate. Architecturally distinct from the prior 4 conversions because it must pause for an asynchronous human decision.

**Pre-planning research:**
- Internal: confirmed Router's `pending_approval` shape (`src/agent/index.ts:437-444`), no state store in the repo, no existing inline_keyboard pattern (openrouter-infer.json sends text-only).
- External: Telegram Bot API (`InlineKeyboardMarkup`, `callback_query`, `answerCallbackQuery`, 64-byte `callback_data` cap), n8n Telegram Trigger callback support, n8n Wait-node caveats (Issue #13633).

**Architecture chosen** (per ADR-0005, Option B): two workflows + idempotent callback_data.
- `destroy-resource.json`: HMAC validate → ADR-0003 sign → Router → on `pending_approval`, Telegram `sendMessage` with inline-keyboard buttons whose `callback_data` fully encodes the destroy command (`dr:<verb>:<resource_type_short>:<resource_id>`) → respond 200.
- `approval-callback.json` (new): Telegram Trigger on `callback_query` → chat.id whitelist (vs `TELEGRAM_CHAT_ID`) → Switch on verb → [approve] Railway `serviceDelete` → editMessageReplyMarkup → answerCallbackQuery → reply.
- MVP scope: `resource_type=railway-service` only. GCP / GitHub / Linear destroy paths deferred.

**Actions taken:**
- Rewrote `src/n8n/workflows/destroy-resource.json` (real handler).
- Created `src/n8n/workflows/approval-callback.json` (passive Telegram callback listener).
- Created `docs/adr/0005-destroy-resource-approval-callback.md` (MADR documenting Option B + rejected alternatives).
- Added R-09 to `docs/risk-register.md` (callback_data trust boundary).
- Added 5 tests in `src/agent/tests/router.test.ts` (3 canonical triplet for destroy-resource + 1 for approval-callback Telegram Trigger + 1 cross-workflow callback_data prefix agreement).
- Updated `CLAUDE.md` §Key Files (split stub row, added two real-handler rows).

**Validation:**
- `npm test` — pending.
- `npm run build` (`tsc --noEmit`) — pending.

**Blockers / Human actions required:** None for this change. New env var `DESTROY_RESOURCE_WEBHOOK_SECRET` follows the existing `*_WEBHOOK_SECRET` convention. `RAILWAY_API_TOKEN` and `TELEGRAM_*` are reused from prior real handlers.

**Next steps:**
- All 5 n8n workflows now real handlers — the template's runtime skill set is complete.
- Trigger `bootstrap.yml` end-to-end once the 7 platform credentials are collected.
- Follow-up: extend `approval-callback.json` to additional `resource_type` short codes (GCP, GitHub repo, Linear issue) as needed.

---

## 2026-05-01 — Convert deploy-railway.json from stub to real handler

**Agent:** Claude Code (claude-opus-4-7)
**Objective:** Convert `src/n8n/workflows/deploy-railway.json` from a 2-node stub to a real handler that triggers a Railway redeploy via the GraphQL API, mirroring the `github-pr.json` pattern (PR #12). Third real-handler conversion in the series (after `health-check`, `create-adr`, `github-pr`).

**Actions taken:**
- Rewrote `src/n8n/workflows/deploy-railway.json` — replaced stub with real handler: webhook trigger → R-02 fail-closed HMAC validation (`DEPLOY_RAILWAY_WEBHOOK_SECRET`) → parallel respond-200 + ADR-0003 sign → call Skills Router → routing gate (`skill==='deploy-railway' && status!=='pending_approval'`) → Railway GraphQL POST (`serviceInstanceRedeploy(serviceId, environmentId)`) → format-success / format-deny → Telegram reply. Auth via `Bearer $env.RAILWAY_API_TOKEN`. Inbound payload: `{service_id (required), environment_id?, chat_id?, user_id?}` — `environment_id` falls back to `$env.RAILWAY_ENVIRONMENT_ID`.
- Added 3 unit tests in `src/agent/tests/router.test.ts` mirroring the canonical assertions: valid JSON, signs per ADR-0003 (with workflow-specific `DEPLOY_RAILWAY_WEBHOOK_SECRET`), no longer returns the stub response.
- Updated `CLAUDE.md` §Key Files — split the stub row, added a dedicated `deploy-railway.json` row.

**Validation:**
- `npm test` — pending.
- `npm run build` (`tsc --noEmit`) — pending.

**Blockers / Human actions required:** None for this change. `RAILWAY_API_TOKEN` already lives in GCP Secret Manager (`railway-api-token`) and is propagated to n8n's Railway env via `bootstrap.yml` Phase 3. The new `DEPLOY_RAILWAY_WEBHOOK_SECRET` follows the existing `*_WEBHOOK_SECRET` convention — operator-injected on first deploy.

**Next steps:**
- Convert `destroy-resource.json` (last stub; requires Telegram approval-callback design).
- Trigger `bootstrap.yml` end-to-end once the 7 platform credentials are collected.

---

## 2026-05-01 — Convert github-pr.json from stub to real handler

**Agent:** Claude Code (claude-opus-4-7)
**Objective:** Convert `src/n8n/workflows/github-pr.json` from a 2-node stub to a real handler that opens a GitHub pull request via the GitHub App, mirroring the `create-adr.json` pattern (PR #11). User-selected stub from a 3-way choice (`github-pr` / `deploy-railway` / `destroy-resource`).

**Actions taken:**
- Rewrote `src/n8n/workflows/github-pr.json` — replaced stub with real handler: webhook trigger → R-02 fail-closed HMAC validation (`GITHUB_PR_WEBHOOK_SECRET`) → parallel respond-200 + ADR-0003 sign → call Skills Router → routing gate (`skill==='github-pr' && status!=='pending_approval'`) → GitHub App branch (build JWT → get installation token → POST `/repos/{owner}/{repo}/pulls`) → format-success / format-deny → Telegram reply.
- Added 3 unit tests in `src/agent/tests/router.test.ts` mirroring the canonical `create-adr.json` assertions: valid JSON, signs per ADR-0003 (with workflow-specific `GITHUB_PR_WEBHOOK_SECRET`), no longer returns the stub response.
- Updated `CLAUDE.md` §Key Files — split the stub row, added a dedicated `github-pr.json` row describing the real handler.

**Validation:**
- `npm test` — 56/56 passing (53 → 56, 3 new).
- `npm run build` (`tsc --noEmit`) — clean.
- Generic test gates `every workflow filename matches its inner webhook path` and `every skill.n8n_webhook path is served by some workflow file` continue to pass.

**Blockers / Human actions required:** None for this change. The runtime workflow secret `GITHUB_PR_WEBHOOK_SECRET` follows the existing `*_WEBHOOK_SECRET` convention — operator-injected into n8n env on first deploy (see `docs/runbooks/bootstrap.md` Step 4); no Secret Manager / `bootstrap.yml` plumbing change required.

**Next steps:**
- Convert `deploy-railway.json` and `destroy-resource.json` (separate follow-ups). `destroy-resource` additionally requires a Telegram approval-callback design.
- Trigger `bootstrap.yml` end-to-end once the 7 platform credentials are collected (see `docs/runbooks/bootstrap.md`).

---

## Format

```
## YYYY-MM-DD — Session Title

**Agent:** Claude Code (claude-sonnet-4-6 / claude-opus-4-7)
**Objective:** What was attempted
**Actions taken:** Bullet list of changes made
**Validation:** Commands run + outcomes
**Blockers / Human actions required:** Any HITL gates hit
**Next steps:** What remains
```

---

## 2026-05-01 — Migrate create-adr stub to real handler (HMAC R-02 + ADR-0003 + GitHub App PR)

**Agent:** Claude Code (claude-opus-4-7)
**Objective:** Migrate `src/n8n/workflows/create-adr.json` from the `{"status":"stub"}` stub to a real handler, following the reference pattern committed in PR #10 (`health-check.json`). The deployed runtime needs a Telegram-driven path to scaffold a new ADR from `docs/adr/template.md` and open a PR via the GitHub App, so that ADR-driven HITL gates (`policy/adr.rego`) are reachable from the operator loop.

**Trigger:** Operator instruction. Builds on PR #10.

**Decision rationale:**
- **Reuse the canonical chain.** Inbound HMAC validate (R-02 fail-closed) → respond 200 (fan-out) → ADR-0003 sign → Skills Router → real work → Telegram reply. The HMAC and Router-call Code-node bodies are copied verbatim from `health-check.json:20, :41, :50–70` so a single contract change updates both via the same CI signal.
- **Routing Gate is defensive.** `create-adr` is `requires_approval: false / budget_gated: false` today, but the IF still surfaces `pending_approval` / `matched: false` to Telegram instead of opening a PR. Future SKILL.md changes (e.g. promoting `create-adr` to budget-gated when an LLM gets involved in drafting) won't silently bypass HITL.
- **GitHub App auth in n8n.** RS256 JWT (iat, exp=iat+540, iss=app_id) → `crypto.createSign('RSA-SHA256')` against `GITHUB_APP_PRIVATE_KEY`, exchanged for an installation token via `POST /app/installations/{id}/access_tokens`. No new secret types needed — the `github-app-*` triplet is already in CLAUDE.md § Secrets Inventory and provisioned by the bootstrap receiver (R-07, validated).
- **No new ADR.** This is a stub-to-real migration along the contract already set in ADR-0003 — exactly mirroring PR #10's posture for `health-check.json`. The OPA gate `policy/adr.rego` only fires on infra changes; this is `src/` + `docs/` only.
- **No new risk.** The handler stays under R-02 (fail-closed inbound HMAC, validated) and R-07 (GitHub App identity, validated). Risk-register unchanged.

**Actions taken:**
- Wrote `src/n8n/workflows/create-adr.json` — full graph: Webhook → Validate&Extract (HMAC) → fan-out (Respond 200 OK + Compute Skills Router HMAC) → Call Skills Router → Routing Gate IF → [Build JWT → Get Installation Token → List ADRs → Read Template → Build ADR + Branch Plan → Get base SHA → Create Branch → Commit File → Open PR → Format Telegram (success)] / [Format Telegram (error)] → Reply to Telegram.
- Added 3 shape tests in `src/agent/tests/router.test.ts` mirroring the `openrouter-infer.json` block at `:505–525`: valid JSON; ADR-0003 signing markers present; **no `"status": "stub"`** to lock the migration in CI.
- Updated `CLAUDE.md` Key Files table — split the grouped stub row so `create-adr.json` gets its own entry describing the real handler.
- Risk-register: no change.

**Validation:**
- `npm test` — all Router tests pass, including the 3 new shape tests.
- `tsc --noEmit` — clean.
- `git status` — only the 4 expected files touched.

**Blockers / Human actions required:**
- End-to-end Telegram → real PR run is **deferred** — requires Railway service, GCP Secret Manager bindings, GitHub App install (R-07 manual phase), and a real Telegram bot (R-04, DO_NOT_AUTOMATE). Same posture as PR #10's deferral for `health-check.json`.

**Next steps:**
- Migrate the remaining three stubs in separate PRs (`deploy-railway`, `github-pr`, `destroy-resource`). Each has a destructive-write surface and warrants its own review.
- After Railway is provisioned, wire `CREATE_ADR_WEBHOOK_SECRET` and the `GITHUB_APP_*` env vars on the n8n service.

---

## 2026-04-30 — Validate staging risks (R-06/R-07/R-08) + health-check real handler + filename normalization

**Agent:** Claude Code (claude-opus-4-7)
**Objective:** Close three open items from the prior session's "Next steps": (1) provide executable validation for R-06 (n8n owner restart idempotency on Railway), R-07 (Cloud Run receiver lifecycle), R-08 (OpenRouter `/credits` probe fail-closed) without real OpenRouter credits / GCP billing / Telegram bot — using local Docker, mocked `gcloud`, and Jest mocks; (2) migrate one stub workflow from `{"status":"stub"}` to a real handler as a copyable reference for the remaining four (`deploy-railway`, `create-adr`, `github-pr`, `destroy-resource`); (3) reconcile the legacy filename mismatches `telegram-listener.json` ↔ skill `telegram-route` and `linear-sync.json` ↔ skill `linear-issue`.

**Trigger:** Operator instruction. Builds on PRs #8 and #9.

**Decision rationale:**
- **Health-check** chosen as first real handler because it has zero side effects, no external mutations, no creds beyond the management key already in Secret Manager, and exercises the canonical `webhook → HMAC validate (R-02) → Respond 200 → Compute ADR-0003 HMAC → call Router → external probes → Telegram reply` chain in 7 nodes — making it copyable for the four remaining stubs. The two parallel external probes (Skills Router `/health` + OpenRouter `/credits`) reuse the exact response shape `OpenRouterBudgetGate.getCreditsBalance` reads (`src/agent/index.ts:254-257`), so the same response parsing is exercised in two places.
- **Filename rename over skill rename:** SKILL.md skill names describe **action** (`telegram-route`, `linear-issue`); filenames are an implementation artifact. The 5 stubs from PR #9 already follow `filename = skill name = path`. Renaming files (Option A) requires only doc updates; renaming skills (Option B) would require updating tests at `router.test.ts:138, 225` and replace semantic names with mechanism names.
- **R-08 already mostly covered.** Existing Jest coverage at `router.test.ts:335-345, 431-480` exercises `OpenRouterBudgetGate` fail-closed/fail-open and the `BUDGET_THRESHOLD` handler path. The R-08 §Required experiment specifically calls for forcing **probe failure** through the webhook handler — the missing path. Added one test using existing `mockFetchReject` helper (line 30). Also fixed risk-register's expected `reason` string from `"openrouter_budget_probe_failed"` (incorrect) to `"probe_failed_fail_closed"` (matches `GATE_REASONS.PROBE_FAIL_CLOSED` at `src/agent/index.ts:210`).
- **R-06 staging script** uses Docker with `n8nio/n8n:2.17.0` + SQLite volume; reads owner row before/after a restart and asserts hash + createdAt unchanged — directly answers the R-06 §Required experiment without Railway. The Railway-specific behavior is identical because Railway's restart-on-deploy is the same container restart Docker performs.
- **R-07 lifecycle script** uses `PATH` override to inject a `mock-gcloud` shim that logs commands. Drives three scenarios: happy path (secrets appear → teardown invoked), timeout (secrets never appear → teardown still invoked, asserting the `if: always()` semantics), and pre-flight WEBHOOK_URL missing (re-asserts the PR #8 invariant). The full E2E (real GitHub App registration) stays manual because R-07 has irreducible HITL.

**Actions taken:**
- **Part A — filename normalization:**
  - `git mv src/n8n/workflows/telegram-listener.json src/n8n/workflows/telegram-route.json`
  - `git mv src/n8n/workflows/linear-sync.json src/n8n/workflows/linear-issue.json`
  - `CLAUDE.md` — Key Files table updated for both renames.
  - `docs/runbooks/bootstrap.md:212-213` — both filenames updated.
  - `docs/adr/0003-webhook-signature-contract.md:9, :47` — both references updated.
  - `src/agent/tests/router.test.ts` — new test "every workflow filename matches its inner webhook path" locks the convention going forward.
- **Part B — health-check real handler:**
  - `src/n8n/workflows/health-check.json` — full rewrite from 2-node stub to 9-node real handler. Mirrors `openrouter-infer.json` HMAC pattern but without budget-gate branch; adds two parallel HTTP probes (Skills Router `/health` + OpenRouter `/credits`) with `continueOnFail: true` so a single down service produces a `down` row instead of crashing the workflow. Top-level `_comment` documents env vars + reuse of `OpenRouterBudgetGate` response shape.
- **Part C — staging artifacts:**
  - `src/agent/tests/router.test.ts` — added "budget-gated skill returns pending_approval with probe_failed_fail_closed when /credits probe rejects" — exercises the full webhook handler with `mockFetchReject()`.
  - `docs/risk-register.md` — fixed R-08 §Required experiment `reason` string; updated R-06/R-07/R-08 statuses to reference the new validation artifacts.
  - `tools/staging/test-r06-n8n-owner.sh` — new Docker-based n8n owner restart idempotency test.
  - `tools/staging/test-r07-receiver-lifecycle.sh` — new gcloud-mocked Cloud Run receiver lifecycle test (3 scenarios).
  - `docs/runbooks/staging-validation.md` — new runbook documenting how to run all 3 staging artifacts + manual E2E checklist for the irreducible R-07 HITL step.

**Validation:**
- `cd src/agent && npm test` — all prior tests + 2 new tests pass.
- `for f in src/n8n/workflows/*.json; do python3 -c "import json; json.load(open('$f'))"; done` — all 8 workflows parse.
- `bash tools/staging/test-r07-receiver-lifecycle.sh` — exits 0 (no GCP needed).
- `bash tools/staging/test-r06-n8n-owner.sh` — exits 0 when Docker available; documented as manual local step in CI-less environments.
- `git grep -l telegram-listener src/ docs/runbooks/ docs/adr/ CLAUDE.md` — no matches outside historical JOURNEY.md entries.
- `git grep "openrouter_budget_probe_failed"` — 0 matches (incorrect string fixed).

**Blockers / Human actions required:** None for code. R-07 full E2E remains manual (free GCP project + sandbox GH org → 2 browser clicks); the lifecycle script de-risks every part except the human OAuth dance. R-06 script requires Docker locally; environments without Docker should rely on the manual checklist in the new staging-validation runbook.

**Next steps:** Migrate the remaining 4 stubs (`deploy-railway`, `create-adr`, `github-pr`, `destroy-resource`) using `health-check.json` as reference. Add CI hook to run `test-r06`/`test-r07` scripts (currently they're manual). Once a real OpenRouter account is connected, exercise the full R-08 fail-open scenario per the runbook.

---

## 2026-04-30 — Backfill risk-register R-06..R-08 + scaffold orphan skill workflows

**Agent:** Claude Code (claude-opus-4-7)
**Objective:** Close two doc/scaffold drift gaps surfaced in the post-PR-#7 review. (1) `docs/risk-register.md` matrix listed only R-01..R-05 even though R-06 and R-07 narratives existed below; R-08 was declared in `CLAUDE.md` §Active Risks but had no entry at all. (2) Five skills declared in `src/agent/skills/SKILL.md` (`health-check`, `deploy-railway`, `create-adr`, `github-pr`, `destroy-resource`) had no receiving workflow in `src/n8n/workflows/` — the Skills Router (`src/agent/index.ts:451`) returns the `n8n_webhook` URL without verifying the target exists, so these would resolve in the Router but produce silent 404s in n8n.

**Trigger:** Post-PR-#7 review. Sibling of PR #8 (the bootstrap WEBHOOK_URL fail-closed fix, already merged — see entry below).

**Decision rationale:** For the risk register, extending the matrix and adding a full R-08 narrative restores the contract documented in CLAUDE.md§Session Protocol that the register stays in sync. R-08 wording aligns with CLAUDE.md:113 + ADR-0004 and explicitly calls out the operator footgun of flipping `OPENROUTER_BUDGET_FAIL_OPEN=true` during a probe outage. For the orphan skills, scaffolding stub workflows (vs. removing the skills from SKILL.md) preserves design intent and keeps the Router contract honest — the stubs return `{"status":"stub","skill":"<name>","message":"workflow not yet implemented"}` so callers see an explicit unimplemented signal instead of a silent 404. Each stub file carries a top-level `_comment` warning that HMAC validation (R-02) and the ADR-0003 Router HMAC contract must be added before wiring real logic. The `destroy-resource` stub additionally surfaces `requires_approval: true` in the response body, mirroring its SKILL.md declaration.

**Actions taken:**
- `docs/risk-register.md` — matrix extended with R-06, R-07, R-08 rows; appended a full R-08 section (Risk, Classification, Evidence basis, Impact, Mitigation, Required experiment, Owner, Status) in the same format as R-06/R-07.
- `src/n8n/workflows/health-check.json`, `deploy-railway.json`, `create-adr.json`, `github-pr.json`, `destroy-resource.json` — five new stub workflows, each: webhook trigger at the SKILL.md-declared path → `respondToWebhook` returning the stub JSON. Pattern mirrors `openrouter-infer.json` lines 4-38 (trigger + respond nodes only).
- `CLAUDE.md` — Key Files table adds a row for the new stub bundle.
- `src/agent/tests/router.test.ts` — added regression test "every skill.n8n_webhook path is served by some workflow file" (post-/simplify follow-up). Iterates over all `*.json` in `src/n8n/workflows/`, collects each workflow's webhook node `parameters.path`, and asserts every `discoverSkills()` skill's `n8n_webhook` URL resolves to one. Excludes the SKILL.md template stub `skill-name`. Would have caught the original 5 orphan skills.

**Validation:**
- `for f in src/n8n/workflows/*.json; do python3 -c "import json; json.load(open('$f'))"; done` — all 8 workflows parse as valid JSON.
- Cross-check: every `n8n_webhook` for the 5 newly-listed skills resolves to a workflow file. Pre-existing path mismatches (`telegram-route` → `telegram-listener.json`, `linear-issue` → `linear-sync.json`) are out of scope: their internal `path` declarations correctly match SKILL.md, only the filename differs.
- Manual end-to-end deferred: requires a deployed n8n to import each stub and POST to its `/webhook/<name>` path.

**Blockers / Human actions required:** None. Stub workflows must be imported via n8n UI before they respond; same operator step already documented for the existing workflows.

**Next steps:** Future PRs implement real handlers per skill (one PR per skill, owner-driven). Each implementation must replace the stub respond node with: HMAC validation block (`R-02 fail-closed`) → real handler → ADR-0003-compliant Skills Router callback if needed. The R-08 fail-closed default should be exercised in the staging environment per the experiment described in `risk-register.md`. A separate follow-up should also reconcile the pre-existing `telegram-route`/`linear-issue` SKILL.md path mismatches with the actual workflow filenames.

---

## 2026-04-30 — Fail-closed bootstrap when WEBHOOK_URL unset

**Agent:** Claude Code (claude-opus-4-7)
**Objective:** Eliminate the placeholder fallback in the GitHub App bootstrap flow. Both `bootstrap.yml:537` and `bootstrap-receiver/main.py:37` defaulted `WEBHOOK_URL` to `https://placeholder.example.com/webhook/github` when the operator forgot to set the repo variable. That placeholder was written into the live GitHub App Manifest (`main.py:112`), creating a real App with a non-functional webhook URL — fixable only by hand-editing the App in GitHub UI after the fact.

**Trigger:** Post-PR-#7 review surfaced this as a latent one-shot blast-radius bug. Merged as PR #8.

**Decision rationale:** Fail-closed at two layers. (1) `bootstrap.yml` adds a pre-flight step that asserts `vars.WEBHOOK_URL` is non-empty before any Cloud Run deploy work begins, with a remediation message naming the `gh variable set` command. The placeholder fallback at the deploy step is removed. (2) `main.py` raises `SystemExit` if `WEBHOOK_URL` is empty — defense-in-depth in case the receiver image is ever invoked outside the bootstrap workflow. Runbook updated with a new sub-step 1h explaining that the webhook URL is immutable post-registration and must be predicted from the planned Railway hostname (or set after a first n8n deploy via re-run).

**Actions taken:**
- `.github/workflows/bootstrap.yml` — new "Pre-flight — require WEBHOOK_URL repo variable" step before the Cloud Run deploy; removed the `|| 'https://placeholder.example.com/webhook/github'` fallback in the `--set-env-vars` line.
- `src/bootstrap-receiver/main.py` — `WEBHOOK_URL` defaults to empty; if empty, `print(..., file=sys.stderr); sys.exit(1)` matching the file's existing GCP_PROJECT_ID validation pattern. Docstring at line 20 expanded to mark `WEBHOOK_URL` as REQUIRED.
- `docs/runbooks/bootstrap.md` — new sub-step 1h documenting the WEBHOOK_URL prerequisite.
- `CLAUDE.md` — HITL §GitHub App expanded with the pre-flight requirement.

**Validation:** `grep -rn 'placeholder.example.com' .` returns no hits in code/config. Smoke test: importing `main.py` with `WEBHOOK_URL` unset exits with code 1.

**Blockers / Human actions required:** Operators upgrading from prior bootstrap must set the `WEBHOOK_URL` repo variable before re-running the workflow.

---

## 2026-04-30 — Close gap #2: enforce four runtime guardrails

**Agent:** Claude Code (claude-opus-4-7)
**Objective:** Implement enforcement for the four runtime autonomy bounds declared in `CLAUDE.md` but absent from code: (1) OpenRouter $10/day cap, (2) 20 req/min n8n webhook rate-limit, (3) HITL gate when OpenRouter budget threshold breached, (4) missing `openrouter-infer` n8n workflow handler.

**Trigger:** Operator instruction — blocking work before connecting an OpenRouter account with real credits. Prior session (PR #5) closed gaps #1 and #3; gap #2 was deferred and is the last unimplemented runtime guardrail set.

**Decision rationale:** Two-layer budget enforcement — (a) hard cap server-side via OpenRouter Management API: provision a downstream key with `limit=10, limit_reset="daily"`, n8n uses *this* key (not the management key) so OpenRouter rejects requests at the edge when cap hit; (b) soft HITL gate in the Skills Router: pre-route `GET /api/v1/credits` (60s cached) when matched skill is `budget_gated`, return `pending_approval` with `reason: "openrouter_budget_threshold"` if remaining < `OPENROUTER_BUDGET_THRESHOLD_USD`. Rate-limit enforced in-process at the Skills Router (zero-dep sliding window keyed by `req.socket.remoteAddress`, 20 req per 60s window) — this is the single trust boundary every n8n call must cross per ADR-0003. Cloudflare-edge rate-limit deferred (n8n hostname is un-proxied CNAME). New skill field `budget_gated: true` chosen over flipping `requires_approval: true` to preserve CLAUDE.md's "Query OpenRouter for inference (≤ $10/day cap)" autonomy clause; gating only fires when budget would be exceeded. Default `OPENROUTER_BUDGET_FAIL_OPEN=false` (gate when probe fails) — CLAUDE.md treats budget excess as HITL; uncertain ⇒ assume excess.

**Actions taken:**
- `src/agent/index.ts` — added `budget_gated?: boolean` to `Skill` interface, `class RateLimiter` (sliding window, configurable via env), `OpenRouterBudgetGate` module (cached `/credits` probe + `shouldGate`), and two new gates in `handleWebhook`: rate-limit (post-signature, pre-parse, returns 429) + budget gate (post-match, pre-`requires_approval`, returns `pending_approval`).
- `src/agent/skills/SKILL.md` — `openrouter-infer` now declares `budget_gated: true`; template updated; header documents the new field.
- `src/agent/tests/router.test.ts` — new describe blocks for `RateLimiter` (5 tests), `OpenRouterBudgetGate` (6 tests, mocked fetch), `Webhook handler — guardrails` (4 integration tests on ephemeral port), `n8n workflow files` (JSON validity + schema parity); extended `discoverSkills` block.
- `src/n8n/workflows/openrouter-infer.json` — new 7-node workflow mirroring `telegram-listener.json` HMAC pattern: webhook → validate → compute Router HMAC → call Router → branch on `pending_approval` → either call OpenRouter (`OPENROUTER_RUNTIME_KEY`, not management) or notify Telegram for HITL approval → reply.
- `terraform/variables.tf` — added `openrouter-runtime-key` to `secret_names`.
- `tools/provision-openrouter-runtime-key.sh` — new idempotent script: reads management key from Secret Manager, calls `POST /api/v1/keys` with daily limit, writes downstream key to `openrouter-runtime-key` Secret Manager container.
- `.github/workflows/bootstrap.yml` — new `Provision OpenRouter runtime key` step in `generate-and-inject-secrets` job; agent service now receives `OPENROUTER_RUNTIME_KEY`, `OPENROUTER_BUDGET_THRESHOLD_USD=1.0`, `OPENROUTER_BUDGET_FAIL_OPEN=false`, `RATE_LIMIT_MAX=20`, `RATE_LIMIT_WINDOW_MS=60000`.
- `CLAUDE.md` — secrets inventory adds `openrouter-runtime-key`; risk register adds R-08 (OpenRouter budget probe); rate-limit text expanded to name the enforcement location.
- `docs/adr/0004-runtime-guardrails.md` — new MADR documenting the design decisions.

**Validation:**
- `npm test` — see commit; all 27 prior tests must still pass; ≥18 new tests added.
- `npx tsc --noEmit` — clean.
- `python3 -c "import json; json.load(open('src/n8n/workflows/openrouter-infer.json'))"` — JSON OK.
- Manual end-to-end deferred: requires OpenRouter Management key + deployed n8n; documented in plan and ADR-0004.

**Blockers / Human actions required:** None for code. Bootstrap workflow now needs `OPENROUTER_MANAGEMENT_KEY` GitHub Secret to provision the downstream runtime key; if absent, the new step is skipped (no failure).

**Next steps:** Operator can now safely wire OpenRouter credits — the $10/day cap is enforced both server-side (by OpenRouter on the runtime key) and pre-flight (HITL gate at the Router). Follow-up PR may add Cloudflare-edge rate-limit on the n8n hostname (deferred — DNS topology change).

---

## 2026-04-30 — Fix gaps #3 (Terraform secret) + #1 (n8n→Router HMAC mismatch)

**Agent:** Claude Code (claude-opus-4-7)
**Objective:** Close two of the three gaps identified in the repo gap review:
- **#3** — `github-app-webhook-secret` was listed in the CLAUDE.md secrets inventory and written by `src/bootstrap-receiver/main.py:257`, but its container was not declared in `terraform/variables.tf` `secret_names`. Bootstrap would fail when the Cloud Run receiver tried to write a non-existent secret.
- **#1** — End-to-end runtime path was broken. `src/n8n/workflows/telegram-listener.json` posted to `${SKILLS_ROUTER_URL}/route` with header `X-Webhook-Signature` and merged the HMAC into the body as `_sig`. The Skills Router (`src/agent/index.ts:287`) only accepts `POST /webhook` with header `x-signature-256`, and HMAC must be computed over the exact raw bytes of the body — not over a JSON-stringified object that includes the signature itself.

**Trigger:** Operator review answered "yes, immediate fix" for #3 + #1. Direction for #1 chosen via web-evidenced research (decision: align n8n to Router, not the reverse).

**Decision rationale (#1):** Aligning n8n to the Router preserves an already-correct `validateWebhookSignature` (timing-safe, `sha256=<hex>` GitHub-aligned), an existing 6-test fail-closed suite (R-02), and the `/webhook/...` prefix already used in every `SKILL.md` skill. The only `/route` reference in the entire repo was the broken n8n line. Industry research confirmed: (a) GitHub's `X-Hub-Signature-256` + `sha256=` is the de-facto convention; (b) HMAC must be computed over raw body bytes, not a re-serialized object; (c) the n8n best practice is to build the body as a string in a Code node and send it via HTTP Request `contentType: raw` so the node does not reformat it.

**Actions taken:**
- `terraform/variables.tf:75` — added `"github-app-webhook-secret"` to `secret_names`. The `for_each = toset(var.secret_names)` in `terraform/gcp.tf:96-111` provisions the container automatically on next `terraform apply`.
- `src/n8n/workflows/telegram-listener.json` — three changes to the "Compute Skills Router HMAC" Code node and the "Call Skills Router" HTTP node:
  1. Code node now builds an explicit `bodyStr = JSON.stringify({intent, chat_id, user_id, timestamp, metadata})`, signs that exact string, and returns `{_bodyStr, _sig}` as separate fields (no merge into payload, no `_sig`-in-body anti-pattern).
  2. HTTP node URL: `/route` → `/webhook`.
  3. HTTP node header: `X-Webhook-Signature` → `x-signature-256`. Body now sent via `contentType: "raw"` + `rawContentType: "application/json"` + `body: "={{ $json._bodyStr }}"` so n8n does not re-serialize and break the signature.
- Fail-closed enforcement: Code node now throws `'SKILLS_ROUTER_SECRET missing — fail-closed (R-02)'` if the secret env var is absent.

**Validation:**
- `python3 -c "import json; json.load(open('src/n8n/workflows/telegram-listener.json'))"` → `JSON OK`.
- `npm test` — see commit (Router code unchanged, all 27 tests must still pass).
- Manual end-to-end HMAC simulation deferred until n8n is deployed (requires running n8n + Router; documented in plan file).

**Blockers / Human actions required:** None for these two fixes. Gap #2 (OpenRouter $10/day cap + n8n 20 req/min rate-limit) deferred until OpenRouter is wired in.

**Next steps:** Address gap #2 before connecting OpenRouter Management API and credits.

---

## 2026-04-30 — Align README + bootstrap runbook with one-shot.sh flow

**Agent:** Claude Code (claude-opus-4-7)
**Objective:** Bring user-facing docs in sync with the actually-shipped automation. README prerequisites table and `docs/runbooks/bootstrap.md` still described the old multi-step UI flow (manual GitHub Secrets/Variables setup, manual `bootstrap` environment with required reviewer, manual GitHub App registration, manual post-terraform variable update).

**Trigger:** Operator: "המשך מה שנשאר" — continue what's left. Tests green (27/27). All PRs (#1–#3) merged. Concrete remaining gap is documentation drift, not code.

**Actions taken:**
- `README.md` — prerequisites table updated: GitHub App now "2 browser clicks (Cloud Run receiver, R-07)"; n8n root user "AUTOMATED (≥2.17.0, R-06)". Quick Start replaced with the `tools/one-shot.sh` flow (export env vars → run script → 2 clicks).
- `docs/runbooks/bootstrap.md` — rewritten end-to-end around `one-shot.sh`: human collects 7 platform credentials, exports them, runs the script, completes 2 clicks. Removed obsolete Step 2 (manual Secrets/Variables UI), Step 3 (`bootstrap` environment with reviewer — removed in PR #3), and Step 5 manual variable update (now auto-handled by terraform-apply step).
- Step 1b (GitHub App manual registration) replaced with R-07 receiver explanation.
- Step 5 (n8n password retrieval) removed — bcrypt-only flow.

**Validation:** `npm test` — 27/27 passed. No source changes.

**Blockers / Human actions required:** None — docs only.

**Next steps:** Operator runs `./tools/one-shot.sh` once platform prerequisites are obtained.

---

## 2026-04-30 — Zero-click GitHub config: one-shot.sh + bootstrap.yml dual-auth

**Agent:** Claude Code (claude-sonnet-4-6)
**Objective:** Eliminate all manual GitHub UI configuration — user runs ONE command; only 2 browser clicks remain (Create GitHub App + Install)

**Trigger:** Operator confirmed no GitHub console access. All secrets/variables must be set programmatically from a single shell command.

**Actions taken:**
- Created `tools/one-shot.sh` — single command that:
  - Sets all GitHub Secrets via REST API (PyNaCl libsodium sealed-box encryption)
  - Sets all GitHub Variables via REST API
  - Creates `bootstrap` GitHub environment (no reviewers — no blocking gate)
  - Stores GITHUB_TOKEN as `GH_ADMIN_TOKEN` secret (needed for post-terraform var updates)
  - Triggers `bootstrap.yml` workflow_dispatch
  - Prints the Actions link
- Modified `.github/workflows/bootstrap.yml`:
  - Removed `environment: bootstrap` from `generate-and-inject-secrets` and `terraform-apply` jobs (approval gates not needed for solo operator)
  - Replaced all WIF auth steps with dual auth: WIF if `GCP_WORKLOAD_IDENTITY_PROVIDER` is set, SA key (`GOOGLE_CREDENTIALS`) otherwise — solves chicken-and-egg for first bootstrap
  - Added `Auto-update GitHub variables and remove SA key` step in `terraform-apply` job: reads `wif_provider_name` and `service_account_email` from terraform outputs, updates GitHub variables via API using `GH_ADMIN_TOKEN`, then DELETES `GOOGLE_CREDENTIALS` secret once WIF is operational

**Full lifecycle (zero manual GitHub UI):**
1. User: `export GITHUB_TOKEN=... GCP_PROJECT_ID=... RAILWAY_API_TOKEN=... [all tokens] GOOGLE_CREDENTIALS='...'`
2. User: `./tools/one-shot.sh` — sets everything, triggers workflow
3. Workflow runs → terraform creates WIF → auto-updates GCP_WORKLOAD_IDENTITY_PROVIDER + GCP_SERVICE_ACCOUNT_EMAIL → deletes GOOGLE_CREDENTIALS
4. User: 2 browser clicks (Create GitHub App + Install) — link in Actions summary

**Validation:** No TypeScript/test impact.

**Next steps:** User completes platform prerequisites (GCP SA key, Railway token, Cloudflare token, OpenRouter key, Telegram @BotFather), then runs `./tools/one-shot.sh`

---

## 2026-04-30 — Phase 4 readiness: fix railway.toml, add wrangler.toml, n8n workflows, ADR-0002

**Agent:** Claude Code (claude-sonnet-4-6)
**Objective:** Resolve concrete gaps blocking Phase 4 (Service Deployment) and prepare Phase 5 foundation

**Actions taken:**
- Fixed `railway.toml` — removed invalid `[[services]]` TOML (not a Railway construct); agent service config retained; n8n split to `railway.n8n.toml` with `n8nio/n8n` image reference
- Added `wrangler.toml` — required by `cloudflare/wrangler-action@v3`; defines Worker name, compatibility date, `RAILWAY_ORIGIN` var
- Fixed `RAILWAY_TOKEN` → `RAILWAY_API_TOKEN` in `.github/workflows/deploy.yml` (consistent with `bootstrap.yml`)
- Created `docs/adr/0002-web-native-bootstrap.md` — MADR documenting the architectural pivot from local CLI to GitHub Actions bootstrap
- Created `src/n8n/workflows/telegram-listener.json` — starter n8n workflow for Telegram webhook → Skills Router routing
- Created `src/n8n/workflows/linear-sync.json` — starter n8n workflow for Linear webhook → issue state sync

**Validation:** `npm test` — 27/27 passed (no TypeScript changes)

**Blockers / Human actions required:** None in this session

**Next steps:** Human completes Phase 1 bootstrap checklist; triggers `bootstrap.yml` workflow; imports n8n workflows via UI

---

## 2026-04-30 — Complete GitHub App Cloud Run receiver + bootstrap.yml integration

**Agent:** Claude Code (claude-sonnet-4-6)
**Objective:** Complete the GitHub App automation: Dockerfile, bootstrap.yml `github-app-registration` job, risk register, CLAUDE.md updates

**Actions taken:**
- Created `src/bootstrap-receiver/Dockerfile` — minimal `python:3.12-slim` image, no pip deps, exposes PORT 8080
- Added `github-app-registration` job to `.github/workflows/bootstrap.yml`:
    - Checks if `github-app-id` secret already exists (idempotent — skips if app already registered)
    - Builds and pushes receiver image to Artifact Registry
    - Deploys Cloud Run service → captures URL → re-deploys with `REDIRECT_URL` set to `/callback`
    - Probes `/health` endpoint before printing operator URL
    - Prints operator instruction to GitHub Actions step summary with direct link
    - Polls Secret Manager for `github-app-id` (20× 30s = 10 min max)
    - Tears down Cloud Run service in `if: always()` cleanup step
    - Updated `summary` job `needs:` to include `github-app-registration`
- Added R-07 to `docs/risk-register.md` — Cloud Run receiver pattern, NEEDS_EXPERIMENT
- Updated `CLAUDE.md`:
    - Item 1 (GitHub App): changed from BLOCKED to "2-click minimum via Cloud Run receiver (R-07)"
    - Risk table: added R-07 row
    - Secrets inventory: `github-app-private-key`, `github-app-id`, `github-app-webhook-secret` now show "Cloud Run receiver (auto-injected)"; `github-app-installation-id` remains human operator

**Validation:** No TypeScript/test impact. YAML structure validated by review.

**Remaining human minimum:** 2 browser clicks (non-GHEC): "Create GitHub App" + "Install". Plus: set `GITHUB_APP_INSTALLATION_ID` variable after installation, and `GITHUB_ORG` + `APP_NAME` GitHub Variables before triggering bootstrap workflow.

**Next steps:** Human sets `GITHUB_ORG` and `APP_NAME` as GitHub Variables, then triggers bootstrap workflow.

---

## 2026-04-30 — GitHub App creation reduced to 2 browser clicks via Cloud Run receiver

**Agent:** Claude Code (claude-sonnet-4-6)
**Objective:** Research and implement near-full automation of GitHub App creation using GCP

**Research findings:**
- GitHub App Manifest flow Step 1 requires a browser POST — no REST API alternative exists for non-GHEC orgs
- A GCP Cloud Run service can serve the pre-filled manifest form (auto-submits via JS), handle the OAuth code exchange, and write all credentials to Secret Manager automatically
- Human interaction reduced to exactly 2 browser clicks: "Create GitHub App" + "Install"
- GHEC-only: July 2025 preview API (`POST /enterprises/{e}/apps/organizations/{org}/installations`) eliminates even the installation click
- Headless browser automation violates GitHub ToS — not implemented
- Probot uses this exact Cloud Run pattern in production (via `@probot/adapter-google-cloud-functions`)

**Actions taken:**
- Created `src/bootstrap-receiver/` — minimal Python Cloud Run service (stdlib only, no pip deps):
    - `GET /` → serves pre-filled manifest HTML form that auto-submits to GitHub
    - `GET /callback?code=...` → exchanges code, writes APP_ID + PRIVATE_KEY + WEBHOOK_SECRET to Secret Manager, redirects to install URL
- Created `src/bootstrap-receiver/Dockerfile`
- Updated `.github/workflows/bootstrap.yml` — new `github-app-registration` job: deploys Cloud Run receiver, polls Secret Manager until secrets appear (up to 10 min), cleans up service
- Added R-07 to `docs/risk-register.md`
- Updated `CLAUDE.md` GitHub App entry from BLOCKED to "2-click minimum via Cloud Run receiver"

**Validation:** No TypeScript/test impact.

**Remaining human minimum:** 2 browser clicks (non-GHEC) or 1 click (GHEC).

---

## 2026-04-30 — Web-native bootstrap: replace bootstrap.sh with GitHub Actions workflow

**Agent:** Claude Code (claude-sonnet-4-6)
**Objective:** Replace local CLI bootstrap approach with fully web-native GitHub Actions workflow

**Trigger:** Operator clarified the environment is Claude Code on the web — no local terminal, no gcloud CLI, no local npm or terraform. All automation must run through GitHub Actions.

**Architectural pivot:**
- `tools/bootstrap.sh` (relied on gcloud, local python, terraform CLI) → deprecated
- New: `.github/workflows/bootstrap.yml` — `workflow_dispatch` workflow that runs entirely in GitHub Actions cloud runners
- Human sets GitHub Secrets (encrypted) and Variables (plaintext) in the GitHub UI
- Workflow authenticates to GCP via WIF, generates secrets, injects into Secret Manager, sets Railway env vars via GraphQL API, runs terraform apply with environment approval gate

**Actions taken:**
- Created `.github/workflows/bootstrap.yml`
- Updated `docs/runbooks/bootstrap.md` — web-based instructions (GitHub UI, not CLI)
- Updated `CLAUDE.md` — removed local CLI references
- Deprecated `tools/bootstrap.sh` with explanatory header

**Validation:** No TypeScript/test impact.

**Next steps:** Human sets GitHub Secrets/Variables, then triggers bootstrap workflow via GitHub Actions UI.

---

## 2026-04-30 — Maximize Bootstrap Automation

**Agent:** Claude Code (claude-sonnet-4-6)
**Objective:** Research and automate every technically automatable bootstrap step

**Research findings (2 internet research queries):**
- Railway env vars: fully automatable via `variableCollectionUpsert` GraphQL mutation using `RAILWAY_API_TOKEN` (account/workspace token). Project tokens may lack mutation permissions — must use account token.
- GitHub App creation: Manifest flow requires browser click (no curl workaround). Org installation requires human OAuth admin consent. GHEC-only API exists but is preview and enterprise-scoped.
- bcrypt hash: auto-generatable via Python `bcrypt` or `htpasswd`.

**Conflict resolution:** GitHub App and org installation remain HUMAN_REQUIRED per official GitHub docs. All other steps fully automated.

**Actions taken:**
- Rewrote `tools/bootstrap.sh` — auto-generates secrets (password, bcrypt hash, encryption key), injects into GCP Secret Manager, sets Railway env vars via GraphQL API, runs terraform apply
- Updated `docs/runbooks/bootstrap.md` — human steps reduced to 6 (down from 9 requiring manual inputs)
- Updated `CLAUDE.md` HITL list — Railway env vars removed from manual steps, terraform apply documented as bootstrap.sh step

**Validation:** No TypeScript/test impact.

**Next steps:** Run `./tools/bootstrap.sh` after completing the 6 remaining human-gated one-time steps.

---

**Agent:** Claude Code (claude-sonnet-4-6)
**Objective:** Research and correct the n8n owner-setup autonomy classification after operator challenge

**Trigger:** Operator disputed the `HUMAN_REQUIRED` classification for n8n root user creation, requesting internet evidence.

**Research findings:**
- n8n 2.17.0 (released 2026-04-14) introduced five new environment variables enabling fully automated owner account creation: `N8N_INSTANCE_OWNER_MANAGED_BY_ENV`, `N8N_INSTANCE_OWNER_EMAIL`, `N8N_INSTANCE_OWNER_PASSWORD_HASH`, `N8N_INSTANCE_OWNER_FIRST_NAME`, `N8N_INSTANCE_OWNER_LAST_NAME`
- Source: PR #27859, commit `1b995cd` in n8n-io/n8n
- The `HUMAN_REQUIRED` classification in the Handoff was accurate for n8n ≤2.16.x but is no longer valid for 2.17.0+
- Official docs (docs.n8n.io) not yet updated — docs PR #4466 still open
- Railway templates not yet updated to use new variables
- Password must be stored as bcrypt hash in GCP Secret Manager, not plaintext

**Conflict resolution:** Handoff document conflicted with current official n8n source code / released version. Per operating contract: deferred to official vendor source. No contradiction with architecture — secrets remain in GCP Secret Manager.

**Actions taken:**
- Updated `CLAUDE.md` — changed n8n from HUMAN_REQUIRED to automatable (≥2.17.0)
- Updated `docs/runbooks/bootstrap.md` Step 5 — documented automated path
- Updated `docs/risk-register.md` — added R-06 (n8n 2.17.0 validation experiment)
- Updated `.env.example` — added five new n8n owner env vars
- Updated `terraform/variables.tf` — added `n8n-admin-password-hash` secret name

**Validation:** No compilation or test impact. Business logic unchanged.

**Blockers:** None. R-06 experiment (Railway restart behavior) should be validated post-deploy.

**Next steps:** Validate that `N8N_INSTANCE_OWNER_MANAGED_BY_ENV=true` does not destructively re-create the owner on every Railway container restart.

---

## 2026-04-30 — Initial Repository Scaffold

**Agent:** Claude Code (claude-sonnet-4-6)
**Objective:** Execute Phase 2 (Scaffolding & IaC) and Phase 3 (CI/CD & Policies) per `FINAL_SYNTHESIS_HANDOFF.md.md`

**Actions taken:**
- Created full repository structure matching `template-repo-requirements.md` specification
- Created `CLAUDE.md` (root + docs/) with autonomy contracts A and B
- Created `AGENTS.md` documenting Build Agent, TS Skills Router, n8n Orchestrator, and MCP server roles
- Created `SECURITY.md` with vulnerability disclosure policy and secrets handling rules
- Created `.gitignore` with comprehensive secret exclusion patterns
- Created `package.json` (zero runtime deps; dev deps: typescript, jest, @types/*)
- Created `tsconfig.json` (strict mode, ES2022, CommonJS)
- Created `.env.example` with all required keys blank
- Created `railway.toml` with build/deploy/health configuration
- Created `Dockerfile` with multi-stage build (builder → runtime, non-root user)
- Created `.claude/settings.json` with MCP servers, permissions, autonomy contract references
- Created `.github/workflows/documentation-enforcement.yml` (OPA/Conftest policy gate)
- Created `.github/workflows/terraform-plan.yml` (WIF/OIDC → GCP, PR comment)
- Created `.github/workflows/deploy.yml` (Railway + Cloudflare Workers + Telegram notify)
- Created `docs/adr/0001-initial-architecture.md` (MADR format)
- Created `docs/adr/template.md` (MADR template)
- Created `docs/runbooks/bootstrap.md` (step-by-step human bootstrap guide)
- Created `docs/runbooks/rollback.md` (reversion procedures)
- Created `docs/autonomy/build-agent-autonomy.md`
- Created `docs/autonomy/runtime-system-autonomy.md`
- Created `docs/risk-register.md` (mirrors embedded register + adds tracking)
- Created `policy/adr.rego` (OPA: ADR enforcement)
- Created `policy/context_sync.rego` (OPA: JOURNEY.md + CLAUDE.md drift detection)
- Created `src/agent/index.ts` (zero-dependency TypeScript Skills Router with Jaccard similarity)
- Created `src/agent/skills/SKILL.md` (initial skill registry: telegram-route, linear-issue, openrouter-infer, health-check)
- Created `src/agent/tests/router.test.ts` (Jest tests for discoverSkills() and routeIntent())
- Created `terraform/gcp.tf` (WIF pool, provider, Secret Manager, IAM bindings)
- Created `terraform/cloudflare.tf` (DNS zone, records, Worker scaffold)
- Created `terraform/variables.tf` (all variable declarations)
- Created `terraform/outputs.tf` (WIF provider name, Secret Manager project)
- Created `terraform/backend.tf` (GCS state backend)
- Created `terraform/terraform.tfvars.example` (blank variable values template)
- Created `tools/bootstrap.sh` (human-guided bootstrap with HITL gates)
- Created `tools/validate.sh` (local validation runner)

**Validation:**
- `npm run build` → pending (requires `npm install` first)
- `npx jest` → pending
- `terraform validate` → pending

**Blockers / Human actions required:**
- All 9 HITL gates from `human-actions.md` are pending (not blocking scaffold)
- No live secrets required for scaffolding

**Next steps:**
- Human operator completes bootstrap checklist in `docs/runbooks/bootstrap.md`
- Run `./tools/validate.sh` after `npm install`
- Run `terraform init` in `terraform/` with GCP credentials to validate provider config
