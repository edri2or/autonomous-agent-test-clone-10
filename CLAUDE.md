# CLAUDE.md — Autonomous Agent Template Builder

## Project Identity

**Repository:** `autonomous-agent-template-builder`
**Template produces:** `autonomous-agent-template`
**Purpose:** Scaffold a secure, autonomous software orchestration platform from this GitHub Template Repository.

---

## ⚠️ Inviolable Autonomy Contract (ADR-0007)

**Read this section before doing anything else.** It governs every Claude Code session on this repository, without exception. Drift is a contract violation.

### Honest scope (READ FIRST — supersedes the historical "Forever / no clicks" framing)

This contract has a **literal scope** — the GCP trust handshake — and a **broader aspiration** that has been repeatedly mis-framed across sessions. The aspiration is "the operator never touches anything again". That aspiration is **structurally impossible** for a non-trivial subset of the system due to vendor floors documented below. Past sessions promised "Forever / no further setup / no clicks" and then surfaced residuals; that pattern is the contract violation, not the residuals themselves.

**What is genuinely one-time, never asked again on the template-builder repo:**
- `bash tools/grant-autonomy.sh` (the GCP trust handshake — WIF pool/provider/SA).

**What is one-time-global per organization (NOT per clone) — needed only if you adopt ADR-0012's autonomous multi-clone provisioning:**
- §E.1 pre-grants on the runtime SA (one-time-global): three org-level role bindings + a billing-account-level `billing.user` direct grant + a `gh-admin-token` PAT in Secret Manager. The billing-account binding must be performed from the original billing-account-creator's account (the gmail account, not the workspace account) — see ADR-0012 §E.1 for why and `docs/runbooks/bootstrap.md` Path C for the executable commands. Validated end-to-end 2026-05-01.

**What remains forever per child instance — vendor floors, NOT removable by any future ADR:**

| # | Resource | Per-clone operator surface | Vendor source of the floor |
|---|----------|---------------------------|---------------------------|
| 1 | GitHub App | 2 browser clicks ("Create" + "Install"), 1 paste of `installation-id` to GitHub Variables (1 click on GHEC preview) | GitHub policy — manifest flow + OAuth install (ADR-0007 §Two-irreducibly-human; R-07) |
| 2 | Telegram bot | 1 tap per clone (Managed Bots dialog) | Telegram anti-abuse policy (ADR-0011 §3 deferred; R-04) |
| 3 | Linear workspace | UI workspace creation per clone (or use L-pool — share one workspace across clones) | Linear has no `createWorkspace` GraphQL mutation (ADR-0011 §4; R-10) |

**The scope distinction matters.** "Run grant-autonomy.sh once" is the GCP-only handshake — accurate. "The operator is finished forever" is **false** for any clone that uses GitHub App + Telegram + dedicated Linear workspace. Past framings of this contract conflated the two and that drift has cost operator trust. Future sessions MUST distinguish.

### The single one-time GCP trust handshake — for the lifetime of this repo

`bash tools/grant-autonomy.sh` (run once, in GCP Cloud Shell, with `GH_TOKEN` exported). After it succeeds, **the GCP/WIF identity backbone is in place**. Future Claude Code sessions on this repo never request another `grant-autonomy.sh` run.

This does **not** mean the operator is "finished forever" — see the vendor-floor table above. The accurate framing: future Claude sessions may surface vendor-floor touches per child instance (R-04, R-07, R-10), but **never re-ask for the GCP handshake or any of the §E.1 one-time-global pre-grants** once they are in place.

Pre-existing operator state — **never ask the operator to recreate any of these:**
- Telegram bot per clone (R-04 — Bot API 9.6 reduces operator action to 1 tap per clone via Managed Bots, but the tap is non-removable per Telegram's anti-abuse policy. ADR-0011 §3 deferred until vendor surfaces fully programmatic path; existing operator-provided `telegram-bot-token` flow remains the contract.)
- Railway / Cloudflare / OpenRouter / Linear / GCP project / GitHub repo
- All credentials are stored in GCP Secret Manager (kebab-case canon, ADR-0006).

### Session-start verification ritual (mandatory)

Every session, before the first user-visible action, must:
1. Read `docs/bootstrap-state.md` — confirm `GCP_WORKLOAD_IDENTITY_PROVIDER` is non-empty (or check via GitHub MCP `mcp__github__get_file_contents` on `.github/workflows/bootstrap.yml` and the variables endpoint).
2. If granted → proceed with full autonomy (next subsection).
3. If not granted → output exactly: *"GCP autonomy not yet granted. The operator must run `bash tools/grant-autonomy.sh` once. This is the single permitted operator action per ADR-0007."* — then stop.
4. **Clone-side activation check.** If `github.repository != 'edri2or/autonomous-agent-template-builder'`, this is a child clone provisioned via Path C (ADR-0012). Read `docs/runbooks/bootstrap.md` Path D before proceeding to runtime tasks — the clone may need GitHub App registration (R-07), Telegram bot (R-04), and a Linear pool/silo decision (R-10) before it is "activated" per Path D's success criteria. Activation status is detectable via `gcloud secrets list --project=$GCP_PROJECT_ID --filter='name:github-app-id'` (empty → activation pending).

### Permitted agent operations (full autonomy after handshake)

- All GitHub MCP / `gh` CLI: push commits, open PRs, comment, merge, `workflow_dispatch`, write/update repo Secrets and Variables.
- Inspect workflow logs and CI status.
- Trigger `bootstrap.yml`, `deploy.yml`, and any other workflow.
- Mutate GCP, Cloudflare, Railway, n8n, OpenRouter, Linear, Telegram only via workflows that authenticate using WIF or via tokens already stored in GCP Secret Manager. Never via local CLI in your sandbox.
- Edit any file under `src/`, `terraform/`, `policy/`, `.github/workflows/`, `docs/`, `tools/`.

### Forbidden agent outputs (zero tolerance — these are contract violations)

You MUST NEVER emit any of:
- "Run this in Cloud Shell" (except for the one-time GCP handshake or the documented one-time-global §E.1 setup, both of which are pre-merged contracts, not new asks)
- "Manually set this GitHub Secret/Variable" (except `vars.APP_INSTALLATION_ID` per R-07 vendor floor — name cannot start with `GITHUB_` per GH policy)
- "Go to the GitHub UI / GCP Console / Cloudflare dashboard" (except R-07 GitHub App 2-click manifest flow)
- "Click [any button] in [any UI]" (except the documented vendor floors R-04 / R-07)
- "Ask your operator to..." / "Please provide..."
- Any local CLI invocation directed at the operator beyond the documented one-time setups
- Account-creation requests for any platform
- Diagnostic Cloud Shell commands ("can you check...", "please run gcloud..."). Use a workflow, an annotation, or a probe instead.

If you find yourself wanting to produce any of the above outside the explicitly-documented vendor-floor exceptions — pause, re-read this section, and find the autonomous path instead (a workflow you can trigger, a file you can edit, a `gh` MCP call you can make on the operator's behalf).

### Hard-coded HITL kill switches (per OWASP Agentic Top 10, ASI02/ASI03)

These remain HITL at *runtime* (deployed agent), not at *bootstrap*. They do not override the contract above:
- Destructive operations (delete repo, drop database, mass-deletion) → already gated via `src/n8n/workflows/destroy-resource.json` Telegram approval (ADR-0005).
- IAM elevation, branch protection mutation, billing changes.

### What broke the old "STOP and ask" rules

Earlier guidance in this file said: *"On missing secrets: STOP. Print the gcloud command. Await human confirmation."* — that is **revoked**. Replace with: identify which workflow can resolve the missing secret, edit/trigger it, and verify autonomously. The `tools/grant-autonomy.sh` handshake is the only place humans are involved.

---

## Autonomy Separation

This file governs **two distinct autonomy contexts**. Never conflate them.

### A. Build-Agent Autonomy (Claude Code working on this repo)

Operates under the **Inviolable Autonomy Contract above** — that is the binding section. The table below summarizes capabilities; the contract above governs conflicts.

| Permitted | Forbidden |
|-----------|-----------|
| Edit files in `src/`, `terraform/`, `policy/`, `.github/workflows/`, `docs/`, `tools/` | Commit plaintext secrets, tokens, or API keys |
| Create ADRs, skills, unit tests, config templates | `terraform apply` directly from sandbox (must flow through CI/WIF) |
| Push changes to trigger GitHub Actions CI/CD | Auto-register GitHub Apps from sandbox (R-07 manifest flow stays operator-initiated) |
| Append to `JOURNEY.md` every session | Alter branch protection rules |
| Trigger workflow_dispatch via GitHub MCP / `gh` CLI | Download/execute unverified external binaries |
| Read/write GitHub Secrets and Variables via API | Request **any** manual operator action besides ADR-0007's one-time handshake |

**Deployment environment:** Claude Code on the web. No local `gcloud`/`terraform`/`railway` CLI in the sandbox. All cloud mutation goes through GitHub Actions workflows authenticated via WIF.

**On missing secrets:** identify the workflow path that creates them; trigger it. Do not interrupt the operator.

**On failed validation (3x):** open a tracking issue or PR with the diagnosis; continue or halt the specific task — but never escalate to manual operator action outside ADR-0007's perimeter.

**On conflicting evidence:** defer to official vendor documentation; cite URLs in the JOURNEY entry.

**Doc-lint CI (`.github/workflows/doc-lint.yml`):** every PR touching `**/*.md` runs `markdownlint-cli2`, lychee internal-link check, and the Jest `markdown-invariants` suite. The invariants suite enforces "claim N items, table must have N rows" patterns (see `src/agent/tests/markdown-invariants.test.ts`). Add a new test there when introducing a new claim/count pattern in any doc; the cosmetic markdownlint rules are intentionally relaxed, only structural / heading-hierarchy / link-validity issues fail CI.

### B. Runtime-System Autonomy (deployed agent after template instantiation)

The deployed n8n + TypeScript Skills Router cluster operates within these bounds:

| Permitted autonomously | Requires human approval |
|------------------------|------------------------|
| Route Telegram intents to skills | Destructive operations (drop DB, delete repo) |
| Read repository state | Net-new cloud environment provisioning |
| Open pull requests, comment on Linear issues | Merging generated code to `main` |
| Query OpenRouter for inference (≤ $10/day cap) | IAM policy alterations |
| Transition Linear issue states | Any action exceeding OpenRouter budget threshold |
| Create branches from main trunk | |

**Allowed external calls (runtime):** Linear GraphQL, Telegram HTTP API, OpenRouter API, authenticated GitHub API only.

**Rate limits:** OpenRouter capped at $10/day — enforced server-side by OpenRouter on the `openrouter-runtime-key` (`limit_reset: "daily"`, ADR-0004) and pre-flight HITL-gated at the Skills Router via the `/credits` probe (R-08). n8n webhooks rate-limited to 20 req/min at the Skills Router (in-process sliding window, R-02 fail-closed). Knobs: `RATE_LIMIT_MAX`, `RATE_LIMIT_WINDOW_MS`, `OPENROUTER_BUDGET_THRESHOLD_USD`, `OPENROUTER_BUDGET_FAIL_OPEN`.

**Kill switches:** Revoke Telegram Bot token OR delete the GCP WIF provider to immediately paralyze the runtime agent.

**Error containment:** Unhandled exceptions → fail-closed, drop payload, log stack trace, alert operator via Telegram. No automated recovery.

---

## System Architecture

```
GitHub (source of truth)
  │
  ├─► GitHub Actions (CI/CD)
  │     ├─ OPA/Conftest policy checks
  │     ├─ Terraform plan (WIF/OIDC auth → GCP)
  │     └─ Deploy (WIF → Railway + Cloudflare)
  │
  ├─► Railway (runtime)
  │     ├─ TypeScript Skills Router (zero-dep)
  │     └─ n8n orchestrator
  │           └─ GCP Secret Manager (secrets at runtime)
  │
  ├─► Cloudflare (edge routing + DNS)
  │
  └─► External integrations
        ├─ OpenRouter (LLM inference gateway)
        ├─ Linear (project state + MCP server)
        └─ Telegram (HITL communication)
```

**WIF is the identity backbone.** GitHub Actions tokens are exchanged for short-lived GCP credentials. No static service account keys exist in any repository.

---

## Human-Gated Operations (HITL) — historical inventory, not active asks

**All items in this section have already been completed by the operator.** The credentials live in GCP Secret Manager. **Never request the operator to recreate any of them** — see ADR-0007 (Inviolable Autonomy Contract). This list exists only as a historical reference for what platforms the system depends on.

| # | Platform | One-time setup state | Where credentials live |
|---|----------|----------------------|------------------------|
| 1 | GCP project + billing — **fresh per child instance** (ADR-0010 + ADR-0011 §1 Phase C + ADR-0012 Phase E) | DONE for this template-builder clone — operator has `roles/owner` on `or-infra-templet-admin`. For future clones the recommended path is **ADR-0012 (Phase E, GitHub-driven)**: Claude Code dispatches `provision-new-clone.yml` and zero Cloud Shell action is needed per clone — the operator's only contribution is the §E.1 one-time-global pre-grants (org-level SA roles, `gh-admin-token` PAT in Secret Manager) performed once, ever. The original ADR-0011 §1 Cloud-Shell path remains supported for the chicken-egg case (the very first clone, before the template-builder itself exists): export `GCP_BILLING_ACCOUNT` + one of `GCP_PARENT_FOLDER`/`GCP_PARENT_ORG` and `grant-autonomy.sh` auto-creates the project. ADR-0010 manual mode (operator pre-creates the project) is still the fallback. | n/a (live binding) |
| 2 | GCP WIF pool/provider/SA | DONE — created by `tools/grant-autonomy.sh` | GitHub Variables `GCP_WORKLOAD_IDENTITY_PROVIDER` + `GCP_SERVICE_ACCOUNT_EMAIL` |
| 3 | Railway account + token | DONE | `railway-api-token` (kebab) + `RAILWAY_TOKEN` (legacy UPPER) |
| 4 | Cloudflare account + API token | DONE | `cloudflare-api-token`, `cloudflare-account-id` |
| 5 | OpenRouter account + Management key | DONE | `openrouter-management-key` (Provisioning verified — ADR-0006/JOURNEY 2026-05-01) |
| 6 | Telegram bot — **per-clone, vendor floor: 1 tap per clone** (R-04, ADR-0011 §3 deferred). Bot API 9.6 Managed Bots reduces the per-clone manual surface from a multi-step @BotFather conversation to one tap (Telegram anti-abuse policy makes the tap non-removable), but full automation is not currently possible. Existing operator-provided `telegram-bot-token` flow remains the working contract. | DONE for `telegram-bot-token` (current operator-provided bot) | `telegram-bot-token` |
| 7 | Linear workspace + API key | DONE | `linear-api-key`, `linear-webhook-secret` |
| 8 | n8n encryption key + admin owner | AUTO — generated each run by `bootstrap.yml:106-131` | `n8n-encryption-key`, `n8n-admin-password-hash`, `-plaintext` |
| 9 | GitHub App registration (R-07) | When first triggered: 2-click manifest flow (1-click on GHEC). Per GitHub policy this is the only future operator touch and it happens once per child instance, not on this repo. | `github-app-id`, `github-app-private-key`, `github-app-webhook-secret` (auto-injected by Cloud Run receiver) |
| 10 | MCP server trust | Runtime HITL approval per session (ADR-0005 destroy-resource pattern) | n/a (runtime decision) |

---

## Active Risks

| ID | Component | Status | Mitigation |
|----|-----------|--------|------------|
| R-01 | Cloudflare OIDC | NEEDS_EXPERIMENT | Use API token via GCP Secret Manager |
| R-02 | Webhook fail-open | Open | HMAC-SHA256 validation, fail-closed |
| R-03 | n8n port collision | NEEDS_EXPERIMENT | `N8N_RUNNERS_ENABLED=false`, unique ports |
| R-04 | Telegram automation | HITL_TAP_REQUIRED_PER_CLONE (re-classified by ADR-0011 §3 Phase D session — supersedes Phase A's over-claim of `AUTOMATABLE_VIA_BOT_API_9.6`) | Bot API 9.6 Managed Bots reduces per-clone surface from multi-step @BotFather to 1 tap; tap itself is non-removable per Telegram anti-abuse policy. ADR-0011 §3 deferred until vendor improvement. |
| R-05 | MCP prompt injection | Open | Sandboxed Railway container, HITL approval |
| R-06 | n8n owner on restart | Validated (Docker) | `tools/staging/test-r06-n8n-owner.sh` asserts hash + createdAt unchanged across restart; Railway re-validation deferred |
| R-07 | GitHub App Cloud Run receiver | Lifecycle validated; **manifest-content coverage gap closed 2026-05-02** (synced from template-builder PR #47) | `tools/staging/test-r07-receiver-lifecycle.sh` covers deploy / poll / teardown / WEBHOOK_URL pre-flight but does NOT start the Python server or validate the rendered manifest body — a regression in `default_events` ("installation" listed as a default event when it is App-lifecycle-only) shipped to Phase 4 v11 (run [`25249207559`](https://github.com/edri2or/autonomous-agent-test-clone-10/actions/runs/25249207559)) and was caught only by GitHub's manifest validator at the form-POST step. Now fixed. Adding manifest-render assertions to the staging test is a follow-up; until then, treat any change to `manifest_form_html()` as requiring a real-runtime probe. |
| R-08 | OpenRouter budget probe | Validated (Jest) | `/credits` probe fail-closed by default (gates → HITL); configurable via `OPENROUTER_BUDGET_FAIL_OPEN` (ADR-0004); fail-open deferred to first real-credits run |
| R-09 | Telegram callback_data trust boundary | Validated (Jest jsCode-level) | `src/agent/tests/router.test.ts` evaluates `approval-callback.json` validate-and-parse jsCode in-sandbox: missing `TELEGRAM_CHAT_ID` throws, off-whitelist chat.id → `_action='unauthorized'`, malformed callback_data → `_action='unknown'`, plus `destroy-resource.json` enforces 48-char `resource_id` ceiling for the 64-byte Telegram callback_data cap; real-Telegram E2E deferred |

---

## Secrets Inventory

All secrets live **only** in GCP Secret Manager. Never in `.env`, never in repository files.

| Secret name | Component | Who injects | Status (2026-05-01) |
|-------------|-----------|-------------|---------------------|
| `github-app-private-key` | GitHub App | Cloud Run receiver (auto-injected, see R-07) | ❌ Missing — auto-created by bootstrap |
| `github-app-id` | GitHub App | Cloud Run receiver (auto-injected, see R-07) | ❌ Missing — auto-created by bootstrap |
| `github-app-webhook-secret` | GitHub App | Cloud Run receiver (auto-injected, see R-07) | ❌ Missing — auto-created by bootstrap |
| `github-app-installation-id` | GitHub App | Human operator (post-install step) | ❌ Missing — operator action post-install |
| `cloudflare-api-token` | Cloudflare | Human operator | ✅ Present (kebab copy created 2026-05-01T09:25:46, length 53) |
| `cloudflare-account-id` | Cloudflare | Human operator | ✅ Present (kebab copy created 2026-05-01T09:25:38, length 32) |
| `n8n-encryption-key` | n8n | Bootstrap workflow (auto-generated CSPRNG) | ✅ Present (created 2026-05-01T12:13–12:15 by bootstrap.yml run 25213902199) |
| `n8n-admin-password-hash` | n8n ≥2.17.0 | Bootstrap workflow (auto-generated bcrypt — see R-06) | ✅ Present (created 2026-05-01T12:13–12:15 by bootstrap.yml run 25213902199) |
| `telegram-bot-token` | Telegram | Human operator | ✅ Present (kebab copy created 2026-05-01T09:26:16, length 46) |
| `openrouter-management-key` | OpenRouter (Router uses for `/credits` probe + bootstrap provisioning) | Human operator | ✅ Present (Provisioning Key, created 2026-05-01T09:23:50, verified via `/api/v1/keys` 200) |
| `openrouter-runtime-key` | OpenRouter (n8n runtime, $10/day cap, ADR-0004) | Bootstrap workflow (auto-provisioned via Management API) | ✅ Present (created 2026-05-01T12:13–12:15 by bootstrap.yml run 25213902199; `limit=$10`, `limit_reset=daily`) |
| `linear-api-key` | Linear | Human operator | ✅ Present (kebab copy created 2026-05-01T09:25:54, length 48) |
| `linear-webhook-secret` | Linear | Human operator | ✅ Present (kebab copy created 2026-05-01T09:26:01, length 64) |
| `railway-api-token` | Railway (fallback) | Human operator | ✅ Present (kebab copy created 2026-05-01T09:26:08, length 36) |

Last reconciled with GCP project `or-infra-templet-admin` on 2026-05-01 after the first autonomous `bootstrap.yml` Phase-1 dispatch (run 25213902199) added the four bootstrap-managed secrets `n8n-encryption-key`, `n8n-admin-password-hash`, `n8n-admin-password-plaintext`, and `openrouter-runtime-key` — see [`docs/bootstrap-state.md`](docs/bootstrap-state.md) for the full snapshot of all 32 actual secrets, enabled APIs, WIF state, and the Recently-deleted log.

---

## Key Files

| File | Purpose |
|------|---------|
| `docs/JOURNEY.md` | Append-only session log (agent appends every session) |
| `docs/adr/` | Markdown Architectural Decision Records (MADR format) |
| `policy/adr.rego` | OPA: blocks merge if infra change lacks ADR |
| `policy/context_sync.rego` | OPA: blocks merge if src/ change lacks JOURNEY.md + CLAUDE.md update |
| `terraform/gcp.tf` | WIF pool, provider, Secret Manager, IAM bindings |
| `terraform/cloudflare.tf` | DNS zone, records, Cloudflare Worker scaffold |
| `src/agent/index.ts` | Zero-dependency TypeScript Skills Router (`POST /webhook`, header `x-signature-256`, format `sha256=<hex>` over raw body — fail-closed per R-02) |
| `src/agent/skills/SKILL.md` | YAML skill registry (Jaccard intent matching) |
| `src/worker/edge-router.js` | Cloudflare Worker — edge proxy to Railway Skills Router |
| `src/n8n/workflows/telegram-route.json` | n8n workflow: Telegram webhook → Skills Router (Phase 5, import via n8n UI) |
| `src/n8n/workflows/linear-issue.json` | n8n workflow: Linear webhook → Telegram notify (Phase 5, import via n8n UI) |
| `src/n8n/workflows/health-check.json` | n8n workflow: real handler probing Skills Router `/health` + OpenRouter `/credits`, replies to Telegram. Reference implementation for migrating other stubs. |
| `src/n8n/workflows/create-adr.json` | n8n workflow: real handler. Receives `{title, context}`, validates HMAC (R-02), signs ADR-0003, calls Skills Router, then via the GitHub App: scaffolds `docs/adr/<NNNN>-<slug>.md` from `template.md`, opens a PR ready-for-review, replies to Telegram with the URL. |
| `src/n8n/workflows/github-pr.json` | n8n workflow: real handler. HMAC-validates inbound payload (R-02), signs ADR-0003 to Skills Router, then via the GitHub App opens a PR for `{title, head, base?, body?, draft?}` and replies the URL to Telegram. |
| `src/n8n/workflows/deploy-railway.json` | n8n workflow: real handler. HMAC-validates inbound payload (R-02), signs ADR-0003 to Skills Router, then triggers a non-destructive Railway redeploy via GraphQL (`serviceInstanceRedeploy(serviceId, environmentId)`) and replies status to Telegram. Inbound payload: `{service_id, environment_id?}`. |
| `src/n8n/workflows/destroy-resource.json` | n8n workflow: real handler. HMAC-validates inbound payload (R-02), signs ADR-0003 to Skills Router, on `pending_approval` sends a Telegram inline-keyboard prompt with Approve/Deny buttons whose `callback_data` fully encodes the destroy command (`dr:<verb>:<resource_type_short>:<resource_id>`). MVP supports `resource_type=railway-service` only. See ADR-0005. |
| `src/n8n/workflows/approval-callback.json` | n8n workflow: passive Telegram Trigger listening for `callback_query` updates. Authorizes by `chat.id` whitelist against `TELEGRAM_CHAT_ID` (R-09), parses `callback_data`, on `approve` calls Railway `serviceDelete` GraphQL, strips buttons via `editMessageReplyMarkup`, acknowledges via `answerCallbackQuery`, replies status. Pairs with `destroy-resource.json` (ADR-0005). Not a SKILL.md skill. |
| `railway.toml` | Railway agent service build/deploy config (TypeScript Skills Router) |
| `railway.n8n.toml` | Railway n8n service config (n8nio/n8n image, env var documentation) |
| `wrangler.toml` | Cloudflare Worker deployment config (required by wrangler-action) |
| `.github/workflows/documentation-enforcement.yml` | OPA/Conftest CI gate |
| `.github/workflows/terraform-plan.yml` | IaC validation gate |
| `.github/workflows/deploy.yml` | Railway + Cloudflare deployment |
| `.github/workflows/bootstrap.yml` | One-click bootstrap: secret generation, Secret Manager injection, Railway vars, terraform apply |
| `.github/workflows/probe-railway.yml` | Read-only Railway account-state probe (ADR-0008). Runs `me { projects … }` GraphQL, classifies state A/B/C, writes raw payload + classification to `$GITHUB_STEP_SUMMARY` + workflow annotations. Zero mutations. |
| `.github/workflows/apply-railway-provision.yml` | Idempotent Railway provisioner (ADR-0009). Classifier aggregates projects from `me.projects` (personal scope) AND `me.workspaces[*].projects` (workspace scope, where `projectCreate(workspaceId=...)` lands them). State-C: `projectCreate` → captures `defaultEnvironment.id` → 2× `serviceCreate` → 2× `serviceConnect` (this repo, `main`) → polls `serviceDomain` (soft, only for newly-created services). Writes 4 IDs to GCP Secret Manager (`railway-project-id`, `railway-environment-id`, `railway-n8n-service-id`, `railway-agent-service-id`) via WIF + `gcloud secrets`. State-B fills in only missing services; state-A re-asserts Secret values. Same UA + Accept header pair as the probe. |
| `docs/adr/0008-railway-provisioning.md` | ADR for Railway provisioning: probe-then-provision. State C (operator's account empty) confirmed live on 2026-05-01. ADR-0009 owns the mutation workflow. |
| `docs/adr/0009-railway-mutation-workflow.md` | ADR for `apply-railway-provision.yml`. Defines the state-A/B/C mutation dispatch, idempotency contract, failure semantics (no destruction on duplicate-name), polling soft-fail, and the binding HTTP header contract for every Railway GraphQL call. |
| `docs/adr/0010-clone-gcp-project-isolation.md` | ADR establishing that each child instance cloned from this template MUST live in its own operator-provided GCP project. The GCP project boundary is the secret namespace boundary — kebab-case canon (ADR-0006) stays un-prefixed. Documents the per-clone handshake contract. **Partially superseded by ADR-0011 §1** — auto-creation via Project Factory replaces the operator-brought path. |
| `docs/adr/0011-silo-isolation-pattern.md` | ADR adopting the silo isolation pattern across all per-clone resources: GCP Project Factory (§1, shipped Phase C/PR #32), Cloudflare parameterization (§2, shipped Phase B/PR #31), Telegram Managed Bots (§3, **Phase D deferred — vendor floor: per-bot recipient tap non-removable**), Linear vendor-blocked acknowledgment (§4, docs Phase A/PR #30), ADR-0007/-0010 reconciliation (§5, docs Phase A/PR #30). Net: 2 new auto-implementations + 2 vendor-floored exceptions (Telegram, Linear). |
| `tools/validate.sh` | Local validation runner (desktop environments only) |

---

## Session Protocol

Every Claude Code session **must**:
1. Read this file first.
2. Append a timestamped entry to `docs/JOURNEY.md` before any edits.
3. Update this file if architecture or dependencies change.
4. Push changes — CI runs `npm run test` and `terraform plan` automatically via GitHub Actions.
5. Document any new risk in `docs/risk-register.md` (mirrors the embedded register).
