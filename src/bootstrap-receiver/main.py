"""
GitHub App Bootstrap Receiver — GCP Cloud Run service

Reduces GitHub App registration to exactly 2 browser clicks:
  1. "Create GitHub App" on GitHub (one click after auto-redirect)
  2. "Install" on the org installation page (one click)

Flow:
  GET /        → serves manifest form → auto-submits to GitHub
  GET /callback → exchanges code → writes secrets → redirects to install page

Zero pip dependencies. Uses only Python stdlib + GCP metadata server for auth.
Deployed temporarily during bootstrap; torn down automatically afterward.

Required environment variables (set at Cloud Run deploy time):
  GCP_PROJECT_ID   — GCP project for Secret Manager writes
  GITHUB_ORG       — GitHub organization name
  APP_NAME         — desired GitHub App name (e.g. "my-agent")
  REDIRECT_URL     — this service's own /callback URL (set after deploy)
  WEBHOOK_URL      — n8n or agent webhook URL for GitHub events (REQUIRED;
                     baked into the live GitHub App at registration time, so
                     fail-closed if missing — see bootstrap.yml pre-flight)
"""

import http.server
import json
import os
import urllib.parse
import urllib.request
import base64
import sys

# ── Configuration ─────────────────────────────────────────────────────────────

GCP_PROJECT_ID = os.environ.get("GCP_PROJECT_ID", "")
GITHUB_ORG     = os.environ.get("GITHUB_ORG", "")
APP_NAME       = os.environ.get("APP_NAME", "autonomous-agent")
REDIRECT_URL   = os.environ.get("REDIRECT_URL", "")   # set after Cloud Run URL is known
WEBHOOK_URL    = os.environ.get("WEBHOOK_URL", "")
if not WEBHOOK_URL:
    print(
        "ERROR: WEBHOOK_URL environment variable is required — refusing to "
        "register a GitHub App with a placeholder webhook (the URL is "
        "immutable post-registration without manual GitHub UI intervention).",
        file=sys.stderr,
    )
    sys.exit(1)
PORT           = int(os.environ.get("PORT", "8080"))

# ── GCP Secret Manager helpers ────────────────────────────────────────────────

def _get_access_token() -> str:
    """Retrieve GCP access token from the metadata server (Cloud Run identity)."""
    req = urllib.request.Request(
        "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token",
        headers={"Metadata-Flavor": "Google"},
    )
    with urllib.request.urlopen(req, timeout=5) as resp:
        return json.loads(resp.read())["access_token"]


def write_secret(name: str, value: str, token: str) -> None:
    """Create or update a GCP Secret Manager secret version."""
    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
    }
    base_url = f"https://secretmanager.googleapis.com/v1/projects/{GCP_PROJECT_ID}/secrets"

    try:
        urllib.request.urlopen(
            urllib.request.Request(f"{base_url}/{name}", headers=headers),
            timeout=10,
        )
    except urllib.error.HTTPError as e:
        if e.code == 404:
            body = json.dumps({"replication": {"automatic": {}}}).encode()
            urllib.request.urlopen(
                urllib.request.Request(base_url, data=body, headers=headers, method="POST"),
                timeout=10,
            )

    payload = json.dumps({
        "payload": {"data": base64.b64encode(value.encode()).decode()}
    }).encode()
    urllib.request.urlopen(
        urllib.request.Request(
            f"{base_url}/{name}:addVersion",
            data=payload,
            headers=headers,
            method="POST",
        ),
        timeout=10,
    )
    print(f"[SECRET] Written: {name}", flush=True)


# ── GitHub API helper ─────────────────────────────────────────────────────────

def exchange_manifest_code(code: str) -> dict:
    """Exchange a manifest temporary code for GitHub App credentials."""
    req = urllib.request.Request(
        f"https://api.github.com/app-manifests/{code}/conversions",
        data=b"",
        headers={
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
        },
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=15) as resp:
        return json.loads(resp.read())


# ── HTML pages ────────────────────────────────────────────────────────────────

def manifest_form_html() -> str:
    manifest = {
        "name": APP_NAME,
        "url": f"https://github.com/{GITHUB_ORG}",
        "hook_attributes": {
            "url": WEBHOOK_URL,
            "active": True,
        },
        "redirect_url": REDIRECT_URL or f"https://placeholder/callback",
        "default_permissions": {
            "contents":      "write",
            "pull_requests": "write",
            "workflows":     "write",
            "secrets":       "write",
            "metadata":      "read",
        },
        "default_events": ["push", "pull_request", "installation"],
        "public": False,
    }
    manifest_json = json.dumps(manifest)
    github_url = f"https://github.com/organizations/{GITHUB_ORG}/settings/apps/new"

    return f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>Register GitHub App — {APP_NAME}</title>
  <style>
    body {{ font-family: system-ui, sans-serif; max-width: 480px; margin: 80px auto; padding: 0 20px; color: #24292f; }}
    h1 {{ font-size: 1.4rem; }}
    p {{ color: #57606a; }}
    .note {{ background: #ddf4ff; border: 1px solid #54aeff; border-radius: 6px; padding: 12px 16px; font-size: 0.9rem; }}
  </style>
</head>
<body>
  <h1>Registering GitHub App: <code>{APP_NAME}</code></h1>
  <p>You will be redirected to GitHub in a moment. Click <strong>"Create GitHub App"</strong> — that's the only action required.</p>
  <p class="note">All credentials will be stored automatically in GCP Secret Manager. You will never see the private key.</p>

  <form id="manifest-form" action="{github_url}" method="post">
    <input type="hidden" name="manifest" id="manifest-input">
  </form>

  <script>
    document.getElementById("manifest-input").value = {json.dumps(manifest_json)};
    // Auto-submit — human lands directly on GitHub confirmation page
    document.getElementById("manifest-form").submit();
  </script>
</body>
</html>"""


def success_html(app_name: str, app_id: str, install_url: str) -> str:
    return f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>GitHub App Created ✓</title>
  <style>
    body {{ font-family: system-ui, sans-serif; max-width: 480px; margin: 80px auto; padding: 0 20px; color: #24292f; }}
    .ok {{ color: #1a7f37; font-size: 1.2rem; font-weight: 600; }}
    .step {{ background: #f6f8fa; border-radius: 6px; padding: 12px 16px; margin: 16px 0; }}
    a.btn {{ display: inline-block; background: #1f883d; color: white; padding: 10px 20px;
             border-radius: 6px; text-decoration: none; font-weight: 600; margin-top: 8px; }}
    a.btn:hover {{ background: #1a7f37; }}
  </style>
</head>
<body>
  <p class="ok">✓ GitHub App "{app_name}" created successfully</p>
  <p>App ID <code>{app_id}</code> and private key have been written to GCP Secret Manager automatically.</p>

  <div class="step">
    <strong>One more click required:</strong> Install the app on your organization.
    <br><br>
    <a class="btn" href="{install_url}" target="_blank">Install App on {GITHUB_ORG} →</a>
  </div>

  <p style="color:#57606a; font-size:0.85rem">
    After clicking Install, return here — the bootstrap workflow will detect
    the installation automatically and continue.
  </p>
</body>
</html>"""


def error_html(message: str) -> str:
    return f"""<!DOCTYPE html>
<html><head><meta charset="utf-8"><title>Error</title></head>
<body style="font-family:system-ui;max-width:480px;margin:80px auto;padding:0 20px">
  <h2 style="color:#cf222e">Bootstrap error</h2>
  <pre style="background:#f6f8fa;padding:12px;border-radius:6px">{message}</pre>
  <p>Check the Cloud Run logs for details.</p>
</body></html>"""


# ── HTTP handler ──────────────────────────────────────────────────────────────

class Handler(http.server.BaseHTTPRequestHandler):

    def send_html(self, status: int, body: str) -> None:
        encoded = body.encode()
        self.send_response(status)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)

    def do_GET(self) -> None:  # noqa: N802
        parsed = urllib.parse.urlparse(self.path)

        if parsed.path in ("/", "/start"):
            self.send_html(200, manifest_form_html())
            return

        if parsed.path == "/health":
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(b'{"status":"ok"}')
            return

        if parsed.path == "/callback":
            params = urllib.parse.parse_qs(parsed.query)
            code = (params.get("code") or [None])[0]
            if not code:
                self.send_html(400, error_html("Missing 'code' parameter in callback URL."))
                return
            self._handle_callback(code)
            return

        self.send_response(404)
        self.end_headers()

    def _handle_callback(self, code: str) -> None:
        try:
            print(f"[CALLBACK] Exchanging manifest code...", flush=True)
            app_data = exchange_manifest_code(code)

            app_id   = str(app_data["id"])
            pem      = app_data["pem"]
            secret   = app_data.get("webhook_secret", "")
            app_name = app_data.get("name", APP_NAME)
            app_slug = app_data.get("slug", app_name.lower().replace(" ", "-"))

            print(f"[CALLBACK] App created: id={app_id} slug={app_slug}", flush=True)

            token = _get_access_token()
            write_secret("github-app-id", app_id, token)
            write_secret("github-app-private-key", pem, token)
            if secret:
                write_secret("github-app-webhook-secret", secret, token)

            install_url = f"https://github.com/apps/{app_slug}/installations/new/permissions?target_id={GITHUB_ORG}"
            self.send_html(200, success_html(app_name, app_id, install_url))
            print("[CALLBACK] All secrets written to Secret Manager. Bootstrap receiver job complete.", flush=True)

        except Exception as exc:
            print(f"[ERROR] {exc}", flush=True)
            self.send_html(500, error_html(str(exc)))

    def log_message(self, fmt, *args):  # suppress default access log noise
        print(f"[HTTP] {fmt % args}", flush=True)


# ── Entry point ───────────────────────────────────────────────────────────────

if __name__ == "__main__":
    if not GCP_PROJECT_ID:
        print("ERROR: GCP_PROJECT_ID environment variable is required.", file=sys.stderr)
        sys.exit(1)
    server = http.server.HTTPServer(("0.0.0.0", PORT), Handler)
    print(f"[RECEIVER] Bootstrap receiver listening on port {PORT}", flush=True)
    print(f"[RECEIVER] App: {APP_NAME}  Org: {GITHUB_ORG}", flush=True)
    server.serve_forever()
