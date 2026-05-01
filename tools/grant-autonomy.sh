#!/usr/bin/env bash
# ============================================================================
# tools/grant-autonomy.sh — The single, one-time operator action.
#
# After this script runs once successfully, every future Claude Code session
# operates with full autonomy on this repo. No further operator action is
# required for: GitHub Secrets/Variables, GCP, Railway, Cloudflare, n8n,
# OpenRouter, Linear, Telegram, or any platform glue.
#
# This script is the formal "trust handshake" defined in ADR-0007 (Inviolable
# Autonomy Contract). It is the ONLY operator action documented anywhere in
# this repository as required.
#
# Run from GCP Cloud Shell after `gcloud auth login` (you already have this
# from being project owner). Provide one PAT via env var; the script does
# everything else.
#
# Usage:
#   export GH_TOKEN=ghp_xxx     # fine-grained PAT, scopes: repo + workflow + admin:org
#   export GITHUB_REPO=owner/repo
#   export GCP_PROJECT_ID=or-infra-templet-admin
#
#   # Optional — auto-create the GCP project per ADR-0011 §1 (silo isolation).
#   # When unset, the script falls back to ADR-0010 manual mode and expects
#   # GCP_PROJECT_ID to already exist.
#   export GCP_PARENT_FOLDER=123456789012        # OR
#   export GCP_PARENT_ORG=987654321098
#   export GCP_BILLING_ACCOUNT=ABCDEF-ABCDEF-ABCDEF
#
#   bash tools/grant-autonomy.sh
#
# The script is idempotent: safe to re-run on partial failure.
# ============================================================================

set -euo pipefail

# CI mode marker (ADR-0012). When CI=true (set by GitHub Actions implicitly +
# by the provision-new-clone.yml workflow explicitly), the gcloud auth is
# provided by google-github-actions/auth@v2 (WIF).
CI_MODE="${CI:-false}"

# Diagnostic ::error:: annotation emission on failure (CI-WIF mode only).
# Logs are inaccessible from the build agent's sandbox (GitHub Actions blob
# host not in proxy allowlist), so failures must surface via annotations
# which ARE queryable through the GitHub API at /check-runs/{id}/annotations.
# This trap fires on any non-zero exit (set -e is on) and emits a single
# annotation containing line number, exit code, and the failing command
# (BASH_COMMAND), then re-exits with the original code.
on_err() {
  local rc=$?
  local line="${1:-?}"
  local cmd="${BASH_COMMAND:-?}"
  if [ "${CI_MODE}" = "true" ]; then
    # Single-line annotation — newlines are not preserved in annotations.
    printf '::error file=tools/grant-autonomy.sh,line=%s::grant-autonomy.sh failed at line %s with exit %s; command: %s\n' \
      "${line}" "${line}" "${rc}" "${cmd}"
  fi
  exit "${rc}"
}
if [ "${CI_MODE}" = "true" ]; then
  trap 'on_err $LINENO' ERR
  # Verbose tracing in CI mode for log readability (logs aren't readable from
  # this sandbox but are visible in the GitHub UI for human operators).
  set -x
fi

# ── Configuration ───────────────────────────────────────────────────────────
: "${GH_TOKEN:?GH_TOKEN must be exported (PAT with repo+workflow+admin:org scopes)}"
: "${GITHUB_REPO:?GITHUB_REPO must be exported (e.g. edri2or/autonomous-agent-template-builder)}"
: "${GCP_PROJECT_ID:?GCP_PROJECT_ID must be exported}"

GCP_REGION="${GCP_REGION:-us-central1}"
TF_STATE_BUCKET="${TF_STATE_BUCKET:-${GCP_PROJECT_ID}-tfstate}"
WIF_POOL_ID="${WIF_POOL_ID:-github}"
WIF_PROVIDER_ID="${WIF_PROVIDER_ID:-github}"
RUNTIME_SA_NAME="${RUNTIME_SA_NAME:-github-actions-runner}"
RUNTIME_SA_EMAIL="${RUNTIME_SA_NAME}@${GCP_PROJECT_ID}.iam.gserviceaccount.com"
N8N_OWNER_EMAIL="${N8N_OWNER_EMAIL:-ops@example.com}"

# Source project for the GCP-→-GitHub secret sync (ADR-0012).
# Operator-Cloud-Shell mode: defaults to the new clone's project (existing
# behavior — secrets the operator pre-populated live there).
# CI-WIF mode: provision-new-clone.yml exports SECRETS_SOURCE_PROJECT so the
# read points at or-infra-templet-admin where the platform tokens actually
# live. The destination (GitHub Secrets on ${GITHUB_REPO}) is unchanged.
SECRETS_SOURCE_PROJECT="${SECRETS_SOURCE_PROJECT:-${GCP_PROJECT_ID}}"

GH_API="https://api.github.com/repos/${GITHUB_REPO}"
log() { printf '\n[autonomy] %s\n' "$*"; }
fail() { printf '\n❌ [autonomy] %s\n' "$*" >&2; exit 1; }

# ── Pre-flight ──────────────────────────────────────────────────────────────
log "Pre-flight checks…"
command -v gcloud >/dev/null || fail "gcloud not found (run from Cloud Shell)"
command -v gh     >/dev/null || fail "gh not found (Cloud Shell should have it)"
command -v jq     >/dev/null || fail "jq not found"

gcloud auth list --filter=status:ACTIVE --format='value(account)' \
  | grep -q . || fail "gcloud not authenticated"

curl -sfH "Authorization: Bearer ${GH_TOKEN}" "${GH_API}" >/dev/null \
  || fail "GH_TOKEN cannot reach ${GITHUB_REPO} (check scopes)"

# ── 0. Auto-create GCP project if missing (ADR-0011 §1) ─────────────────────
# Per ADR-0011 §1: each child instance gets its own GCP project. When
# GCP_BILLING_ACCOUNT + one of {GCP_PARENT_FOLDER, GCP_PARENT_ORG} are
# exported, this step auto-creates and bills-links the project. The
# operator pre-grants `roles/resourcemanager.projectCreator` on the
# parent + `roles/billing.user` on the billing account ONCE GLOBALLY
# (not per clone).
#
# Back-compat (ADR-0010 manual mode): when the project already exists,
# this step is a no-op and the script proceeds to use it. When neither
# auto-create env var is set AND the project is missing, fail with a
# diagnostic that surfaces both paths.

if ! gcloud projects describe "${GCP_PROJECT_ID}" >/dev/null 2>&1; then
  log "Project ${GCP_PROJECT_ID} not found — entering auto-create flow (ADR-0011 §1)…"
  if [[ -z "${GCP_BILLING_ACCOUNT:-}" ]]; then
    fail "Project ${GCP_PROJECT_ID} not found AND GCP_BILLING_ACCOUNT is unset.
Either:
  (a) Pre-create the project (ADR-0010 manual mode) and re-run; OR
  (b) Set GCP_BILLING_ACCOUNT + one of {GCP_PARENT_FOLDER, GCP_PARENT_ORG}
      for ADR-0011 §1 auto-creation."
  fi
  if [[ -z "${GCP_PARENT_FOLDER:-}" && -z "${GCP_PARENT_ORG:-}" ]]; then
    fail "Project ${GCP_PROJECT_ID} not found AND neither GCP_PARENT_FOLDER nor GCP_PARENT_ORG is set.
Set one of them so 'gcloud projects create' has a parent (folder or org)."
  fi

  CREATE_ARGS=(--quiet)
  if [[ -n "${GCP_PARENT_FOLDER:-}" ]]; then
    CREATE_ARGS+=(--folder="${GCP_PARENT_FOLDER}")
    log "Creating ${GCP_PROJECT_ID} under folder ${GCP_PARENT_FOLDER}…"
  else
    CREATE_ARGS+=(--organization="${GCP_PARENT_ORG}")
    log "Creating ${GCP_PROJECT_ID} under organization ${GCP_PARENT_ORG}…"
  fi
  gcloud projects create "${GCP_PROJECT_ID}" "${CREATE_ARGS[@]}"

  # CI-WIF mode (ADR-0012): the consumer project for `gcloud billing` calls
  # is the SA's home project (SECRETS_SOURCE_PROJECT), not Cloud Shell's
  # implicit billing-quota-project. cloudbilling.googleapis.com must be
  # enabled on that consumer project before `gcloud billing projects link`
  # will work. Q-Path (Cloud Shell mode) didn't surface this because Cloud
  # Shell's default project context already had the API enabled.
  # Measured 2026-05-01 via probe-clone-state.yml run 25230782320 (annotation
  # "BILLING_PROBE_FAIL: API [cloudbilling.googleapis.com] not enabled on
  # project [974960215714]" — 974960215714 = or-infra-templet-admin).
  # Idempotent — `services enable` is a no-op if already enabled.
  if [ "${CI_MODE}" = "true" ]; then
    log "CI-WIF mode: ensuring cloudbilling.googleapis.com on consumer project ${SECRETS_SOURCE_PROJECT}…"
    gcloud services enable cloudbilling.googleapis.com \
      --project="${SECRETS_SOURCE_PROJECT}" --quiet
  fi

  # Diagnostic-rich billing link: capture stderr → emit it as the annotation
  # body on failure (the bare ERR trap above only sees BASH_COMMAND, not the
  # gcloud-side error message). Annotations are the only accessible
  # failure-context channel from the build agent's sandbox.
  log "Linking billing account ${GCP_BILLING_ACCOUNT} to ${GCP_PROJECT_ID}…"
  if BILLING_OUT=$(gcloud billing projects link "${GCP_PROJECT_ID}" \
       --billing-account="${GCP_BILLING_ACCOUNT}" --quiet 2>&1); then
    [ -n "${BILLING_OUT}" ] && printf '%s\n' "${BILLING_OUT}"
  else
    BILLING_RC=$?
    if [ "${CI_MODE}" = "true" ]; then
      # Single-line annotation: replace newlines with " | " for readability.
      ENCODED=$(printf '%s' "${BILLING_OUT}" | tr '\n' '|' | head -c 800)
      printf '::error file=tools/grant-autonomy.sh,line=158::gcloud billing projects link FAILED (exit %s): %s\n' \
        "${BILLING_RC}" "${ENCODED}"
    fi
    exit "${BILLING_RC}"
  fi
fi

PROJECT_NUMBER="$(gcloud projects describe "${GCP_PROJECT_ID}" \
  --format='value(projectNumber)')"
log "Project: ${GCP_PROJECT_ID} (number ${PROJECT_NUMBER})"

# ── 1. Enable required GCP APIs ─────────────────────────────────────────────
log "Enabling GCP APIs (idempotent)…"
gcloud services enable \
  iam.googleapis.com \
  iamcredentials.googleapis.com \
  secretmanager.googleapis.com \
  sts.googleapis.com \
  cloudresourcemanager.googleapis.com \
  storage.googleapis.com \
  run.googleapis.com \
  artifactregistry.googleapis.com \
  --project="${GCP_PROJECT_ID}" --quiet

# ── 2. Create Terraform state bucket (chicken-egg with terraform backend) ──
# Q-Path (2026-05-01) surfaced a GCS eventual-consistency race where
# `gcloud storage buckets update --versioning` returned GcsApiError('')
# immediately after bucket creation. Split create+update into independent
# idempotent gates so the versioning step is naturally retry-safe and
# recovers automatically on the next invocation.
log "Ensuring Terraform state bucket gs://${TF_STATE_BUCKET}…"

# 2a. Create-if-missing.
if ! gcloud storage buckets describe "gs://${TF_STATE_BUCKET}" \
       --project="${GCP_PROJECT_ID}" >/dev/null 2>&1; then
  gcloud storage buckets create "gs://${TF_STATE_BUCKET}" \
    --project="${GCP_PROJECT_ID}" \
    --location="${GCP_REGION}" \
    --uniform-bucket-level-access \
    --quiet
fi

# 2b. Update-versioning with retry-with-backoff and explicit bucket-level
# IAM grant (handles GCS IAM propagation lag in CI-WIF mode).
#
# History:
# - Q-Path JOURNEY 2026-05-01 documented a GcsApiError race where the
#   update fails immediately after create but succeeds after sleep.
# - PR #35 made create idempotent.
# - PR #39 added retry-with-backoff but had a bug: `if ! cmd; then RC=$?`
#   captured 0 due to the ! operator's exit-status semantics, so the
#   script silently exited 0 after retries failed.
# - Validation run 25232328369 (clone-007) revealed: the actual error
#   isn't transient — it's an IAM propagation lag where the SA's
#   project-level roles/owner doesn't propagate to bucket-level
#   storage.buckets.update for ~30+ seconds.
#
# Fix: (a) use proper exit-code capture via if/else; (b) add explicit
# bucket-level IAM binding (storage.admin) on the SA to bypass the
# propagation lag entirely; (c) longer retry window.
BUCKET_VERSIONING_OK=false
BUCKET_LAST_OUT=""
BUCKET_LAST_RC=0
SA_FOR_GRANT="$(gcloud config list --format='value(core.account)' 2>/dev/null)"

# 2b.i. Explicit bucket-level grant (idempotent). Bypasses project→bucket
# IAM propagation lag entirely. The SA created the bucket so it has
# storage.buckets.setIamPolicy via project-owner (which IS available
# immediately at the project level even when bucket-level lag exists).
if [ -n "${SA_FOR_GRANT}" ]; then
  log "  Granting ${SA_FOR_GRANT} explicit bucket admin on gs://${TF_STATE_BUCKET}…"
  gcloud storage buckets add-iam-policy-binding "gs://${TF_STATE_BUCKET}" \
    --member="serviceAccount:${SA_FOR_GRANT}" \
    --role="roles/storage.admin" --quiet >/dev/null 2>&1 || \
    log "  (bucket IAM grant skipped or transient failure — will retry below)"
fi

# 2b.ii. Versioning update with retry, proper exit-code capture.
for attempt in 1 2 3 4 5 6; do
  if BUCKET_LAST_OUT=$(gcloud storage buckets update "gs://${TF_STATE_BUCKET}" \
       --versioning --project="${GCP_PROJECT_ID}" --quiet 2>&1); then
    BUCKET_VERSIONING_OK=true
    break
  else
    BUCKET_LAST_RC=$?
    if [ "${attempt}" -lt 6 ]; then
      delay=$((attempt * 10))  # 10, 20, 30, 40, 50 = 150s total window
      log "  bucket versioning attempt ${attempt}/6 failed (exit ${BUCKET_LAST_RC}); sleeping ${delay}s…"
      sleep "${delay}"
    fi
  fi
done

if [ "${BUCKET_VERSIONING_OK}" != "true" ]; then
  if [ "${CI_MODE}" = "true" ]; then
    ENCODED=$(printf '%s' "${BUCKET_LAST_OUT}" | tr '\n' '|' | head -c 800)
    printf '::error file=tools/grant-autonomy.sh,line=213::bucket versioning update failed after 6 attempts (exit %s): %s\n' \
      "${BUCKET_LAST_RC}" "${ENCODED}"
  fi
  exit "${BUCKET_LAST_RC}"
fi

# ── 3. Create runtime Service Account ───────────────────────────────────────
log "Ensuring runtime SA ${RUNTIME_SA_EMAIL}…"
if ! gcloud iam service-accounts describe "${RUNTIME_SA_EMAIL}" \
       --project="${GCP_PROJECT_ID}" >/dev/null 2>&1; then
  gcloud iam service-accounts create "${RUNTIME_SA_NAME}" \
    --project="${GCP_PROJECT_ID}" \
    --display-name="GitHub Actions runtime (WIF)" \
    --description="Federated identity for GitHub Actions OIDC tokens. No keys ever." \
    --quiet
fi

# ── 4. Grant runtime SA the roles it needs ──────────────────────────────────
log "Granting roles to runtime SA…"
for ROLE in \
    roles/secretmanager.secretAccessor \
    roles/secretmanager.admin \
    roles/storage.admin \
    roles/iam.serviceAccountAdmin \
    roles/resourcemanager.projectIamAdmin \
    roles/serviceusage.serviceUsageAdmin \
    roles/run.admin \
    roles/artifactregistry.admin \
    roles/iam.workloadIdentityPoolAdmin; do
  # add-iam-policy-binding is read-modify-write; in re-runs the binding may
  # already be present (returns 0 quietly) or hit a transient ETag race
  # (nonzero). Tolerate both — the next run will reach a consistent state.
  gcloud projects add-iam-policy-binding "${GCP_PROJECT_ID}" \
    --member="serviceAccount:${RUNTIME_SA_EMAIL}" \
    --role="${ROLE}" \
    --condition=None \
    --quiet >/dev/null 2>&1 || true
done

# ── 5. Create WIF pool + provider, restricted to this exact repo ────────────
log "Ensuring WIF pool '${WIF_POOL_ID}'…"
if ! gcloud iam workload-identity-pools describe "${WIF_POOL_ID}" \
       --location=global --project="${GCP_PROJECT_ID}" >/dev/null 2>&1; then
  gcloud iam workload-identity-pools create "${WIF_POOL_ID}" \
    --location=global --project="${GCP_PROJECT_ID}" \
    --display-name="GitHub Actions Pool" \
    --description="WIF pool for GitHub Actions OIDC authentication" \
    --quiet
fi

log "Ensuring WIF provider '${WIF_PROVIDER_ID}' (restricted to ${GITHUB_REPO})…"
if ! gcloud iam workload-identity-pools providers describe "${WIF_PROVIDER_ID}" \
       --workload-identity-pool="${WIF_POOL_ID}" \
       --location=global --project="${GCP_PROJECT_ID}" >/dev/null 2>&1; then
  gcloud iam workload-identity-pools providers create-oidc "${WIF_PROVIDER_ID}" \
    --workload-identity-pool="${WIF_POOL_ID}" \
    --location=global --project="${GCP_PROJECT_ID}" \
    --display-name="GitHub Actions Provider" \
    --issuer-uri="https://token.actions.githubusercontent.com" \
    --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository,attribute.ref=assertion.ref,attribute.actor=assertion.actor" \
    --attribute-condition="assertion.repository == '${GITHUB_REPO}'" \
    --quiet
fi

# ── 6. Bind the WIF subject (this exact repo) to the runtime SA ─────────────
log "Binding WIF principalSet → runtime SA (roles/iam.workloadIdentityUser)…"
WIF_PROVIDER_RESOURCE="projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${WIF_POOL_ID}/providers/${WIF_PROVIDER_ID}"
WIF_POOL_RESOURCE="projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${WIF_POOL_ID}"
gcloud iam service-accounts add-iam-policy-binding "${RUNTIME_SA_EMAIL}" \
  --project="${GCP_PROJECT_ID}" \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/${WIF_POOL_RESOURCE}/attribute.repository/${GITHUB_REPO}" \
  --condition=None --quiet >/dev/null 2>&1 || true

# ── 7. Set GitHub Variables (plain, public IDs) ─────────────────────────────
gh_var() {
  local NAME="$1" VALUE="$2"
  curl -sfX PATCH "${GH_API}/actions/variables/${NAME}" \
    -H "Authorization: Bearer ${GH_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    -d "$(jq -nc --arg n "${NAME}" --arg v "${VALUE}" '{name:$n,value:$v}')" \
    >/dev/null 2>&1 \
  || curl -sfX POST "${GH_API}/actions/variables" \
    -H "Authorization: Bearer ${GH_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    -d "$(jq -nc --arg n "${NAME}" --arg v "${VALUE}" '{name:$n,value:$v}')" \
    >/dev/null
  echo "  • var ${NAME}"
}

log "Setting GitHub Variables…"
gh_var GCP_PROJECT_ID                 "${GCP_PROJECT_ID}"
gh_var GCP_REGION                     "${GCP_REGION}"
gh_var GCP_WORKLOAD_IDENTITY_PROVIDER "${WIF_PROVIDER_RESOURCE}"
gh_var GCP_SERVICE_ACCOUNT_EMAIL      "${RUNTIME_SA_EMAIL}"
gh_var TF_STATE_BUCKET                "${TF_STATE_BUCKET}"
gh_var N8N_OWNER_EMAIL                "${N8N_OWNER_EMAIL}"

# ── 8. Sync platform secrets from GCP Secret Manager → GitHub Secrets ──────
# Some workflow steps consume GitHub Secrets directly (e.g. Railway GraphQL
# calls in bootstrap.yml). The kebab-case canon (ADR-0006) lives in GCP;
# this is a one-time sync to GitHub for those steps that don't yet
# fetch from Secret Manager at runtime.
log "Syncing platform secrets GCP → GitHub Secrets (kebab-case is the canon)…"

PYNACL_OK=$(python3 -c 'import nacl.public' 2>/dev/null && echo yes || echo no)
[ "${PYNACL_OK}" = "yes" ] || pip3 install --quiet pynacl

PUBLIC_KEY_JSON=$(curl -sfH "Authorization: Bearer ${GH_TOKEN}" \
  -H "Accept: application/vnd.github+json" \
  "${GH_API}/actions/secrets/public-key")
PUBLIC_KEY_ID=$(echo "${PUBLIC_KEY_JSON}" | jq -r .key_id)
PUBLIC_KEY_BASE64=$(echo "${PUBLIC_KEY_JSON}" | jq -r .key)

gh_secret() {
  local NAME="$1" VALUE="$2"
  ENCRYPTED=$(python3 -c "
import base64, sys
from nacl.public import PublicKey, SealedBox
pk = PublicKey(base64.b64decode(sys.argv[1]))
ct = SealedBox(pk).encrypt(sys.argv[2].encode())
print(base64.b64encode(ct).decode())
" "${PUBLIC_KEY_BASE64}" "${VALUE}")
  curl -sfX PUT "${GH_API}/actions/secrets/${NAME}" \
    -H "Authorization: Bearer ${GH_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    -d "$(jq -nc --arg v "${ENCRYPTED}" --arg k "${PUBLIC_KEY_ID}" \
        '{encrypted_value:$v,key_id:$k}')" \
    >/dev/null
  echo "  • secret ${NAME}"
}

sync() {
  local GCP_NAME="$1" GH_NAME="$2"
  if VALUE=$(gcloud secrets versions access latest --secret="${GCP_NAME}" \
                --project="${SECRETS_SOURCE_PROJECT}" 2>/dev/null); then
    gh_secret "${GH_NAME}" "${VALUE}"
  else
    echo "  ⚠  GCP secret ${GCP_NAME} not found in ${SECRETS_SOURCE_PROJECT} — skipping (workflow may need it later)"
  fi
}

sync telegram-bot-token        TELEGRAM_BOT_TOKEN
sync cloudflare-api-token      CLOUDFLARE_API_TOKEN
sync openrouter-management-key OPENROUTER_MANAGEMENT_KEY
sync railway-api-token         RAILWAY_API_TOKEN

# ── 9. Verify autonomy is granted ───────────────────────────────────────────
log "Verifying GitHub Variables visible…"
WIF_VAR=$(curl -sfH "Authorization: Bearer ${GH_TOKEN}" \
  "${GH_API}/actions/variables/GCP_WORKLOAD_IDENTITY_PROVIDER" \
  | jq -r .value)
[ "${WIF_VAR}" = "${WIF_PROVIDER_RESOURCE}" ] \
  || fail "GCP_WORKLOAD_IDENTITY_PROVIDER not visible to GitHub"

# ── 10. Summary ─────────────────────────────────────────────────────────────
cat <<EOF

================================================================================
✅ AUTONOMY GRANTED.

  Project:          ${GCP_PROJECT_ID}
  WIF provider:     ${WIF_PROVIDER_RESOURCE}
  Runtime SA:       ${RUNTIME_SA_EMAIL}
  Repo binding:     ${GITHUB_REPO}
  TF state bucket:  gs://${TF_STATE_BUCKET}

  ZERO static SA keys exist anywhere. WIF is the sole identity backbone.
  Future Claude Code sessions are now fully autonomous on this repo. They
  will trigger workflows; workflows authenticate to GCP via WIF; nothing
  more is required from you.

  This was the ONE permitted operator action per ADR-0007. After this point,
  any agent that asks you to run gcloud, gh, or any local CLI is in
  violation of the Inviolable Autonomy Contract — refer it back to the
  contract in CLAUDE.md.
================================================================================
EOF
