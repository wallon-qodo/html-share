# html-share

A Claude Code skill that hosts any HTML artifact at a free, no-sign-in-for-viewers URL.

**Use case:** You generate an HTML report / dashboard / slide deck in Claude Code
and want to send it to someone who shouldn't have to sign up for anything to view it.

---

## Install (one minute)

1. Copy this entire `html-share/` folder into your `~/.claude/skills/` directory:

   ```bash
   # If a coworker sent you a zip:
   unzip html-share.zip -d ~/.claude/skills/

   # Or clone from wherever it lives:
   cp -r /path/to/html-share ~/.claude/skills/
   ```

2. Make sure the deploy script is executable:

   ```bash
   chmod +x ~/.claude/skills/html-share/scripts/deploy.sh
   ```

3. Setup is **optional**. The default provider (PageDrop) needs nothing —
   just `curl` + `jq` (or `python3`), which you already have. Add the others
   if you want their specific perks:

   | Provider | Setup | Best for |
   |---|---|---|
   | **PageDrop** *(default)* | **None.** No account, no API key. | Instant share, anyone can run it |
   | **GitHub Gist** | `brew install gh && gh auth login` | Edit history, version-controlled |
   | **Surge.sh** | `npx surge` once (prompts for email + password, no email verification) | Memorable URLs like `my-report.surge.sh` |
   | **bashupload** | Nothing — uses `curl`, always available | Last-resort fallback (downloads instead of renders) |

That's it. Restart Claude Code or open a new session and the skill is live.

---

## Usage

Just ask Claude in plain English. Any of these trigger the skill:

- "host this HTML"
- "share this HTML file"
- "publish this artifact and give me a link"
- "make this report viewable by my team"
- "give me a link for `report.html`"

Claude will run the deploy script and reply with:

```
Hosted at: https://pagedrop.dev/s/abc123
No sign-in required to view.
Provider: pagedrop
```

### Manual invocation (without Claude)

```bash
# Auto-pick best provider
~/.claude/skills/html-share/scripts/deploy.sh report.html

# Force a specific provider
~/.claude/skills/html-share/scripts/deploy.sh dashboard.html my-name --provider=surge

# Folder with assets (CSS/JS/images alongside index.html)
~/.claude/skills/html-share/scripts/deploy.sh ./build/ --provider=surge
```

---

## How it works

`scripts/deploy.sh` tries providers in order and uses the first one that works:

1. **pagedrop** → `POST https://pagedrop.dev/api/v1/sites` with the HTML body,
   returns `https://pagedrop.dev/s/<id>`. Permanent. 5MB cap.
2. **gist** → `gh gist create --public file.html`, then returns
   `https://gistpreview.github.io/?<gist-id>` (renders the HTML in-browser).
3. **surge** → `npx surge <folder> <name>.surge.sh`.
4. **bashupload** → `curl --upload-file file.html https://bashupload.com/...`
   (3-day expiry, file downloads).

Before deploying, the script greps the artifact for obvious leaked secrets
(`sk-`, `ghp_`, `xoxb-`, `AKIA…`) and refuses if any are found. Override with
`--force-secrets` if you know what you're doing.

---

## Persistence & teardown

| Provider | Lives until |
|---|---|
| pagedrop | Permanent (per pagedrop.dev). Delete via the `deleteToken` returned at deploy — save it if you may want to remove the page later. |
| gist | You run `gh gist delete <id>` |
| surge | You run `npx surge teardown <name>.surge.sh` |
| bashupload | 3 days, automatic |

---

## Sharing with coworkers

The whole skill is this one folder. Zip it and send:

```bash
cd ~/.claude/skills && zip -r html-share.zip html-share/
```

Coworker drops it into their `~/.claude/skills/` and types `/html-share` — or
just asks Claude to host an HTML file.

---

## Troubleshooting

**"No working provider found"** — none of `gh`, `npx`, or `curl` could deploy.
Run `gh auth status` and `npx surge --version` to see which one is broken.

**"Possible secrets detected"** — the artifact contains a string that looks
like an API key. Remove it, or pass `--force-secrets` if it's a false positive.

**Surge says the subdomain is taken** — pick a different name. Surge subdomains
are first-come, first-served globally.

**Gist preview shows raw HTML instead of rendering** — make sure the file has
a `.html` extension. `gistpreview.github.io` keys off that.
