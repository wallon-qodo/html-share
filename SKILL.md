---
name: html-share
version: 1.0.0
description: |
  Publish any HTML artifact (report, dashboard, slides, visualization) to a free,
  no-sign-in-for-viewers URL. Use when the user says "host this HTML", "share this
  HTML", "publish this artifact", "give me a link for this", "make this viewable",
  or wants to send an HTML file to someone who shouldn't have to sign in.
allowed-tools:
  - Bash
  - Read
  - Write
---

# html-share

Hosts HTML artifacts to a public URL. Viewers don't sign in. The link is sendable
in Slack, email, Discord — anywhere.

## Provider order (auto-selected)

The deploy script picks the first one that works:

1. **PageDrop** — zero setup for both deployer and viewer. POSTs to
   `https://pagedrop.dev/api/v1/sites`, returns `https://pagedrop.dev/s/<id>`.
   No account, no API key. 5MB HTML cap. Permanent per their docs.
2. **GitHub Gist + gistpreview.github.io** — persistent, versioned, zero-config if
   `gh` is authed. URL format: `https://gistpreview.github.io/?<gist-id>`.
   Use when you want edit history.
3. **Surge.sh** (`npx surge`) — memorable subdomain (e.g. `my-report.surge.sh`).
   First run prompts for email + password (one-time, no verification email).
   Use when you want a custom URL or are deploying a folder.
4. **bashupload.com** — truly anonymous, no account ever, but file downloads
   instead of rendering in-browser. Last-resort fallback.

## How to invoke

When the user asks to host/share an HTML file, run the deploy script:

```bash
bash ~/.claude/skills/html-share/scripts/deploy.sh <path-to-html-file> [optional-name]
```

The script:
1. Detects available providers
2. Deploys to the best one
3. Prints the public URL on stdout

If no providers are configured, the script prints setup hints and exits non-zero.
Surface those hints to the user verbatim.

## Inputs

- **Single HTML file**: pass the file path. Most artifacts are self-contained
  (inline CSS/JS, base64 images), so a single file is the common case.
- **Folder of assets**: pass a directory. Required if the HTML references
  separate `.css` / `.js` / image files. Surge handles this; gist does not.
- **HTML content in conversation**: write it to a temp file first
  (`/tmp/share-$(date +%s).html`), then deploy.

## Output

Always reply with:

```
Hosted at: <URL>
No sign-in required to view.
Provider: <gist|surge|bashupload>
```

Then a one-line note about persistence:
- pagedrop: "Permanent per pagedrop.dev. Save the DELETE_TOKEN if you may want
  to remove it later — it's not recoverable."
- gist: "Persists until you delete it. Edit via `gh gist edit <id>`."
- surge: "Persists until you run `surge teardown <name>.surge.sh`."
- bashupload: "Expires in 3 days. Downloads instead of renders — open the URL,
  save the file, then open locally."

## Choosing a custom name

If the user wants a memorable subdomain, force surge:

```bash
bash ~/.claude/skills/html-share/scripts/deploy.sh <file> <name> --provider=surge
```

This produces `<name>.surge.sh`. Names must be lowercase, hyphen-separated.

## Sharing this skill with coworkers

This skill is a self-contained directory. To share:

1. Copy `~/.claude/skills/html-share/` to coworker's `~/.claude/skills/`
2. Coworker needs ONE of: `gh` (authed), `npx` (for surge), or `curl` (for bashupload)
3. Tell them: "Type `/html-share` in Claude Code, or just ask Claude to host an HTML file"

See `README.md` in this skill for plain-text setup instructions you can paste
into Slack/email when sharing.

## Hard rules

- **Never expose secrets**: scan the HTML for obvious tokens (`sk-`, `ghp_`,
  `xoxb-`, `AKIA`, etc.) before deploying. If found, refuse and warn the user.
- **No PII in surge subdomains**: subdomain is public. Don't include emails,
  phone numbers, or customer names unless the user explicitly approves.
- **Confirm before re-publishing** if the same name already exists on surge —
  it will overwrite.
