#!/usr/bin/env bash
# html-share deploy: publishes an HTML file/folder to a no-sign-in URL.
# Usage: deploy.sh <path> [name] [--provider=gist|surge|bashupload]

set -euo pipefail

INPUT="${1:-}"
NAME="${2:-}"
FORCE_PROVIDER=""

for arg in "$@"; do
  case "$arg" in
    --provider=*) FORCE_PROVIDER="${arg#*=}" ;;
  esac
done

if [[ -z "$INPUT" ]]; then
  echo "Usage: deploy.sh <html-file-or-folder> [name] [--provider=gist|surge|bashupload]" >&2
  exit 2
fi

if [[ ! -e "$INPUT" ]]; then
  echo "Error: $INPUT does not exist" >&2
  exit 2
fi

# Secret scan -- refuse if obvious tokens leak into the artifact
scan_secrets() {
  local target="$1"
  local hits
  hits=$(grep -rEho '(sk-[A-Za-z0-9]{20,}|ghp_[A-Za-z0-9]{30,}|xox[baprs]-[A-Za-z0-9-]{10,}|AKIA[0-9A-Z]{16})' "$target" 2>/dev/null | head -3 || true)
  if [[ -n "$hits" ]]; then
    echo "Refusing to deploy: possible secrets detected in artifact:" >&2
    echo "$hits" >&2
    echo "Remove them or pass --force-secrets to override." >&2
    return 1
  fi
}

if [[ "${FORCE_SECRETS:-}" != "1" ]] && [[ ! "$*" == *"--force-secrets"* ]]; then
  scan_secrets "$INPUT" || exit 3
fi

# ---- Provider: PageDrop (zero-setup default) ----
deploy_pagedrop() {
  if ! command -v curl >/dev/null 2>&1; then return 10; fi
  if [[ -d "$INPUT" ]]; then
    echo "pagedrop provider only supports single HTML files (use surge for folders)" >&2
    return 11
  fi
  # 5MB HTML cap per pagedrop docs
  local size
  size=$(wc -c < "$INPUT" | tr -d ' ')
  if (( size > 5242880 )); then
    echo "File ${size}B exceeds PageDrop 5MB cap — falling through" >&2
    return 11
  fi

  local title="${NAME:-html-share artifact}"
  local body resp url site_id del_token

  # Build JSON body. Prefer jq if available; fall back to python3 for safe escaping.
  if command -v jq >/dev/null 2>&1; then
    body=$(jq -n --rawfile h "$INPUT" --arg t "$title" '{html: $h, title: $t}')
  elif command -v python3 >/dev/null 2>&1; then
    body=$(python3 -c "import json,sys; print(json.dumps({'html': open(sys.argv[1]).read(), 'title': sys.argv[2]}))" "$INPUT" "$title")
  else
    echo "pagedrop needs jq or python3 to build JSON safely" >&2
    return 10
  fi

  resp=$(printf '%s' "$body" | curl -sS --max-time 30 -X POST \
    "https://pagedrop.dev/api/v1/sites" \
    -H "Content-Type: application/json" \
    --data-binary @-) || return 12

  url=$(printf '%s' "$resp" | sed -n 's/.*"url"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
  site_id=$(printf '%s' "$resp" | sed -n 's/.*"siteId"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
  del_token=$(printf '%s' "$resp" | sed -n 's/.*"deleteToken"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)

  if [[ -z "$url" ]]; then
    echo "PageDrop API returned no URL. Response: $resp" >&2
    return 12
  fi

  # Verify it renders
  local code
  code=$(curl -sLk -o /dev/null -w '%{http_code}' --max-time 15 "$url")
  if [[ "$code" != "200" ]]; then
    echo "PageDrop returned URL but HTTP ${code}" >&2
    return 13
  fi

  echo "URL=${url}"
  echo "PROVIDER=pagedrop"
  echo "SITE_ID=${site_id}"
  echo "DELETE_TOKEN=${del_token}"
  return 0
}

# ---- Provider: GitHub Gist ----
deploy_gist() {
  if ! command -v gh >/dev/null 2>&1; then return 10; fi
  # An invalid GITHUB_TOKEN env var will make gh fail even if keychain is authed.
  # Drop both env tokens for the auth check and the create call so keychain wins.
  if ! env -u GITHUB_TOKEN -u GH_TOKEN gh auth status >/dev/null 2>&1; then return 10; fi

  if [[ -d "$INPUT" ]]; then
    echo "gist provider only supports single files; pass an HTML file" >&2
    return 11
  fi

  local desc="${NAME:-html-share artifact $(date +%Y-%m-%d)}"
  local url gist_id
  url=$(env -u GITHUB_TOKEN -u GH_TOKEN gh gist create --public --desc "$desc" "$INPUT" 2>/dev/null) || return 12
  gist_id=$(basename "$url")
  local preview_url="https://gistpreview.github.io/?${gist_id}"
  # Verify the gist exists (gistpreview is client-side JS, so just check the gist itself)
  if ! curl -sf -o /dev/null --max-time 10 "https://gist.github.com/${gist_id}"; then
    echo "Gist created but not reachable: $url" >&2
    return 13
  fi
  echo "URL=${preview_url}"
  echo "PROVIDER=gist"
  echo "GIST_ID=${gist_id}"
  return 0
}

# ---- Provider: Surge ----
deploy_surge() {
  if ! command -v npx >/dev/null 2>&1; then return 10; fi
  # Surge's first run requires interactive email/password. If unauthenticated,
  # skip rather than running a broken deploy that "succeeds" but serves 404.
  if ! npx --yes surge whoami 2>&1 | grep -qi 'email'; then
    echo "Surge not authenticated. Run once interactively: npx surge login" >&2
    return 10
  fi

  local workdir
  if [[ -d "$INPUT" ]]; then
    workdir="$INPUT"
  else
    workdir="$(mktemp -d -t html-share-XXXXXX)"
    cp "$INPUT" "$workdir/index.html"
  fi

  local subdomain="${NAME:-html-share-$(date +%s)-$RANDOM}"
  subdomain=$(echo "$subdomain" | tr '[:upper:] _' '[:lower:]--' | tr -cd 'a-z0-9-')
  local domain="${subdomain}.surge.sh"

  if ! npx --yes surge "$workdir" "$domain" >/dev/null 2>&1; then
    return 12
  fi

  # Verify the deploy actually serves 200 — surge can exit 0 even on auth failure
  sleep 2
  local code
  code=$(curl -sk -o /dev/null -w '%{http_code}' --max-time 15 "https://${domain}")
  if [[ "$code" != "200" ]]; then
    echo "Surge deploy reported success but URL returned HTTP ${code}" >&2
    return 13
  fi

  echo "URL=https://${domain}"
  echo "PROVIDER=surge"
  echo "DOMAIN=${domain}"
  return 0
}

# ---- Provider: bashupload (anonymous fallback) ----
deploy_bashupload() {
  if ! command -v curl >/dev/null 2>&1; then return 10; fi
  if [[ -d "$INPUT" ]]; then
    echo "bashupload provider only supports single files" >&2
    return 11
  fi
  local resp url
  resp=$(curl -s --max-time 30 --upload-file "$INPUT" "https://bashupload.com/$(basename "$INPUT")" 2>/dev/null) || return 12
  url=$(echo "$resp" | grep -Eo 'https://bashupload\.com/[^ ]+' | head -1)
  [[ -z "$url" ]] && return 12
  echo "URL=${url}"
  echo "PROVIDER=bashupload"
  return 0
}

# ---- Provider selection ----
try_provider() {
  case "$1" in
    pagedrop) deploy_pagedrop ;;
    gist) deploy_gist ;;
    surge) deploy_surge ;;
    bashupload) deploy_bashupload ;;
    *) return 99 ;;
  esac
}

if [[ -n "$FORCE_PROVIDER" ]]; then
  if try_provider "$FORCE_PROVIDER"; then exit 0; fi
  echo "Forced provider '$FORCE_PROVIDER' failed." >&2
  exit 1
fi

for p in pagedrop gist surge bashupload; do
  if try_provider "$p"; then exit 0; fi
done

cat >&2 <<'EOF'
No working provider found. Set up one of:

  1. gh CLI (recommended):
       brew install gh && gh auth login

  2. surge.sh (memorable URLs):
       npx surge --version    # first run will prompt for email + password (no verification)

  3. curl (always available on macOS/Linux) — bashupload fallback should "just work";
     if it failed, you may be offline or behind a proxy.
EOF
exit 1
