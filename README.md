![Upskill – Install Agent Skills](hero-banner.jpeg)

# upskill

[![81% Vibe_Coded](https://img.shields.io/badge/81%25-Vibe_Coded-ff69b4?style=for-the-badge&logo=robot&logoColor=white)](https://github.com/ai-ecoverse/vibe-coded-badge-action)

Install [Agent Skills](https://agentskills.io) from GitHub repositories.

> **Note:** This tool implements the [agentskills.io specification](https://agentskills.io/specification). Your AI agent (Claude Code, Cursor, VS Code, etc.) likely already supports this spec natively and can discover skills automatically. This tool is primarily useful for:
> - Installing skills from private repositories
> - Batch installing multiple skills
> - Managing skills across projects

## Install

- Standalone
  - macOS/Linux: `curl -fsSL https://raw.githubusercontent.com/ai-ecoverse/gh-upskill/main/install.sh | bash`
  - Custom prefix: `curl -fsSL https://raw.githubusercontent.com/ai-ecoverse/gh-upskill/main/install.sh | bash -s -- --prefix ~/.local`

- npm: `npm install -g @ai-ecoverse/gh-upskill` (or `pnpm add -g @ai-ecoverse/gh-upskill`) installs `upskill` and `gh-upskill`

- GitHub CLI extension
  - `gh extension install ai-ecoverse/gh-upskill`
  - Then run via `gh upskill ...` (or use `upskill` directly)

- seven (SLICC): preinstalled in `/usr/bin`, see [seven / SLICC kernel](#seven--slicc-kernel)

## Usage

Skills are discovered by scanning for `**/SKILL.md` files per the [agentskills.io spec](https://agentskills.io/specification).

**List available skills:**
```
upskill anthropics/skills --list
```

**Install specific skills:**
```
upskill anthropics/skills --skill pdf --skill xlsx
```

**Install all skills:**
```
upskill anthropics/skills --all
```

**Replace existing skills that upskill did not install:**
```
upskill anthropics/skills --all --force
```

Reinstalling a skill that upskill installed updates it in place, with or without `--force` (see [Updating skills](#updating-skills)).

### Subcommands

| Subcommand | Description |
|------------|-------------|
| `list [--dest D]` | List local skills, with the source and short commit they were installed from |
| `info <name> [--dest D]` | Show details about a local skill, including its source, path and commit |
| `read <name>` | Print the SKILL.md content of a locally installed skill |
| `outdated [--dest D]` | List installed skills whose source has newer commits for their path |
| `update <name>... \| --all [--dest D] [--force]` | Update installed skills in place from their recorded source |
| `search <query>` | Search ClawHub and Tessl skill registries |

```
upskill list                        # Show local skills
upskill info pdf                    # Show skill details
upskill read pdf                    # Print SKILL.md content
upskill outdated                    # Which installed skills are behind
upskill update --all                # Update them in place
upskill search "pdf converter"      # Search registries
```

Without `--dest`, `list`, `outdated` and `update` look in the same folders as `list`: `.agents/skills`, `.skills`, `.claude/skills`, `.pi/skills`, `~/.pi/agent/skills`, `~/.agents/skills`, `~/.skills` and `~/.claude/skills`. With `--dest`, they look only in that folder.

### Updating skills

Every install writes a `.upskill` marker into the skill folder. It uses the format SLICC 6's built-in upskill wrote, so markers from SLICC 6 work with this tool and the other way round:

```json
{
  "kind": "github",
  "source": "ai-ecoverse/skills",
  "skill": "slack",
  "path": "skills/slack",
  "sha": "1fd7a319946c495c6ed95c79a43143fabf0fe0e4",
  "version": 1,
  "installed": "2026-10-27T17:43:51.000Z",
  "files": ["SKILL.md", "references/app-manifest.md", "scripts/slack-support.jsh", "..."]
}
```

- `sha` is the commit the files came from. upskill reads it from the REST API, from the commit GitHub stores as the ZIP archive comment, or from the clone. It is never a branch name.
- `ref` is recorded only when you pass `--branch` or `owner/repo@ref`. Updates then follow that ref; without it they follow the default branch.
- `files` lists every path upskill wrote, relative to the skill folder.
- ClawHub installs record `"kind": "clawhub"`, `"source": "<owner>/<slug>"` and the published version as `"release"`.

When you reinstall over a folder that has a marker, or run `upskill update`, the skill is updated in place:

- New and changed files from upstream are written.
- Files the old marker lists that upstream no longer has are removed.
- Nothing else is touched. That includes files a skill keeps as state in its own folder (for example slack's `.last-post-*.json`, `.watch-*.json` and `emoji-cache.json`) and your own notes.
- Dotfiles that already exist are never overwritten or removed, because they often hold credentials (for example `scripts/.config`). Upstream dotfiles are still written when they are missing.
- The skill keeps its folder's permissions: the folder, the folders leading to upskill's files, those files (executable or not) and the marker get the group and other bits the folder had, whatever the umask. An install takes them from the destination folder instead. So `sudo upskill update` of a skill in `/usr/share/skills` (mode 755) leaves it readable for everyone, though `sudo` keeps a umask such as 077 from the user.

A folder without a marker keeps the old behaviour. It is skipped, or deleted and reinstalled with `--force`. To start tracking a skill like that, reinstall it once with `--force`.

`upskill outdated` reports a GitHub skill when the newest commit that touches the skill's `path` differs from the newest commit that touched it at the installed `sha`. Commits elsewhere in the repository don't count. Each check uses one or two GitHub API calls. ClawHub skills are compared by published version.

```
$ upskill outdated --dest /usr/share/skills
  NAME   INSTALLED  LATEST   SOURCE              PATH
  slack  1fd7a31    556021b  ai-ecoverse/skills  /usr/share/skills/slack

1 of 1 tracked skill(s) can be updated: upskill update --all --dest /usr/share/skills

$ sudo upskill update slack --dest /usr/share/skills
Updating slack from ai-ecoverse/skills (skills/slack), installed 1fd7a31
Updating skill in place: slack
  removed scripts/slack-support.jsh (dropped upstream)
Updated skill: slack (c97fec8)
Updated 1, up to date 0, failed 0.
```

`LATEST` is the newest commit that touches the skill's path. After an update, the marker's `sha` is the repository commit the files were downloaded from, which can be newer.

`update` skips skills that are already current and still have every file the marker lists. `--force` downloads them again anyway, which restores deleted files. `update` exits non-zero if any skill fails to update. The other skills are still updated.

### Install sources

Besides GitHub repositories, skills can be installed from ClawHub and Tessl registries:

```
upskill clawhub:tavily-search                # Install from ClawHub by slug
upskill https://clawhub.ai/user/my-skill     # Install from ClawHub by URL
upskill tessl:postgres-pro                   # Install from Tessl registry
```

The `owner/repo@branch` inline syntax is also supported (the `-b` flag takes precedence if both are specified):

```
upskill anthropics/skills@main --list
```

### Filter by subfolder

Use `-p` or `--path` to restrict skill discovery to a subfolder within the repository. This is useful for repos that organize skills in nested directories:

```
upskill adobe/skills --path plugins/aem/edge-delivery-services --list
upskill adobe/skills --path plugins/aem/edge-delivery-services --all
upskill adobe/skills --path plugins/aem/edge-delivery-services --skill content-driven-development
```

This is equivalent to the Vercel Skills CLI's tree-URL syntax:
```
npx skills add https://github.com/adobe/skills/tree/main/plugins/aem/edge-delivery-services --all
```

### Install skills globally (personal skills)

Use the `-g` or `--global` flag to install skills to `~/.agents/skills` instead of the project's `.agents/skills/` directory:

```
upskill -g anthropics/skills --skill pdf --skill xlsx
```

When installing globally:
- Skills are installed to `~/.agents/skills`
- If `~/.claude/` exists, skills are also installed to `~/.claude/skills/` (see [Claude Code auto-detection](#claude-code-auto-detection))

### Install to custom destination

Use `--dest` (or its alias `--dest-path`) to install skills to a custom location:

```
upskill anthropics/skills --skill pdf --dest-path .claude/skills
```

This is useful for compatibility with tools that expect skills in different locations. Note that `--dest-path` disables [Claude Code auto-detection](#claude-code-auto-detection).

### Options

| Option | Description |
|--------|-------------|
| `-g, --global` | Install to `~/.agents/skills` (personal skills) |
| `-b, --branch <ref>` | Branch, tag, or commit to clone |
| `-p, --path <subfolder>` | Only discover skills under this subfolder |
| `--dest, --dest-path <path>` | Custom destination path (overrides `-g`) |
| `--list` | List available skills without installing |
| `--skill <name>` | Install specific skill(s) (repeatable) |
| `--all` | Install all discovered skills |
| `--force` | Replace existing skill directories that have no `.upskill` marker |
| `-i` | Add `.agents/skills/` to `.gitignore` |
| `-q, --quiet` | Reduce output |

## How it works

1. With git, gh, tar and unzip available, downloads a ZIP archive and falls back to `gh repo clone` if needed.
2. When any of those tools is missing and `jq` is available (or `unzip` is unavailable), uses `curl` and `jq` with GitHub's recursive git trees API to discover `**/SKILL.md`. Downloads manifests for discovery, then the selected skills' files individually through the contents API, pinned to the resolved commit. No archive extraction or git is needed. Desktop installations with `unzip` but no `jq` retain the ZIP path.
3. Copies selected skill directories, including hidden files and executable modes, to the destination, and writes a `.upskill` marker with the source, path, resolved commit and installed files. If the destination already has a marker, upskill updates it in place instead.

Authentication uses `GITHUB_TOKEN`, then `GH_TOKEN`, then `gh auth token` if available. This supports private repositories and higher API rate limits. Errors distinguish rate limits from permission failures. The REST path rejects truncated trees and unsafe paths instead of installing an incomplete or unsafe skill. Symbolic links with absolute targets or `..` components are rejected. ClawHub's ZIP downloads still require `unzip`; Tessl skills that resolve to GitHub can use the REST path.

### seven / SLICC kernel

Seven ships `upskill` and `gh-upskill` preinstalled, from the npm package [`@ai-ecoverse/gh-upskill`](https://www.npmjs.com/package/@ai-ecoverse/gh-upskill): root-owned commands in `/usr/bin`, kept at npm's latest release by seven's own tool updates. Nothing needs installing:

```bash
upskill --version
upskill adobe/helix-website --skill "Searching AEM Documentation"
```

Seven's global skills in `/usr/share/skills` belong to root. Anyone can check them; updating one needs `sudo`, which runs the root-owned `/usr/bin/upskill`:

```bash
upskill outdated --dest /usr/share/skills
sudo upskill update slack --dest /usr/share/skills
```

An update keeps a skill's dotfiles and state files, such as slack's `.last-post-*.json` and `emoji-cache.json` (see [Updating skills](#updating-skills)).

The package gives the SLICC kernel `upskill` and `gh-upskill` as `slicc.commands`: a small JS command (`kernel/upskill.mjs`) that runs the package's own `upskill` with the kernel's bash. Its `bin` entries are the bash scripts themselves, for npm and pnpm on other hosts. In the kernel, a pnpm bin shim of a script command doesn't run (slicc has no `node`, and the kernel runs a pnpm shim only for a non-script command of its package), so the JS command is what lets `pnpm add -g @ai-ecoverse/gh-upskill` work in seven too, from `$PNPM_HOME/bin`. Seven itself doesn't need that: it installs the package in its tools root.

`install.sh` is for other hosts. In seven, when `/usr/bin/upskill` exists, it installs nothing and says so, so a user's copy in `$PNPM_HOME/bin` never shadows the preinstalled one (that copy is the user's own, and `sudo` refuses a user-owned command). In an older seven without the preinstalled command, it installs into `$PNPM_HOME/bin` as before:

```bash
command -v upskill || curl -fsSL https://raw.githubusercontent.com/ai-ecoverse/gh-upskill/main/install.sh | bash
```

Seven is detected when `uname -s` reports `Emscripten`, or when `SLICC_PAGE_LOOPBACK` is set. The installer then defaults to `$PNPM_HOME/bin`; if `PNPM_HOME` is absent it uses `~/.local/share/pnpm/bin` and checks that directory is on PATH. Explicit `--prefix` and `--bin-dir` keep their usual meaning, and install a copy even when seven ships one.

In this environment upskill defaults to `~/.pi/agent/skills/<name>/SKILL.md`, including with `-g`. `--dest` or `--dest-path` overrides that default. `list`, `info` and `read` include pi's user skills and `.pi/skills`; pi loads project skills only in trusted folders. The destination also works explicitly outside seven:

```bash
upskill adobe/helix-website --skill "Searching AEM Documentation" --dest "$HOME/.pi/agent/skills"
```

Without slicc-node, seven reaches the web through the page's fetch, so `raw.githubusercontent.com` and `api.github.com` must answer with CORS headers; both provide them. Other sources may need the local proxy. Set `GITHUB_TOKEN` or `GH_TOKEN` in the shell for private repositories and to avoid GitHub's [60 requests per hour unauthenticated limit](https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api), shared by originating IP address.

### Claude Code auto-detection

When `--dest-path` is **not** used, upskill automatically detects Claude Code environments and dual-installs skills:

- **Local installs:** if a `.claude/` directory or `CLAUDE.md` file exists in the project, skills are also installed to `.claude/skills/`
- **Global installs (`-g`):** if `~/.claude/` exists, skills are also installed to `~/.claude/skills/`

Using `--dest-path` disables this auto-detection — skills are only installed to the specified path.

## Development

- Lint: `make lint` (shellcheck)
- Test: `make test` (portable fixtures, offline marker/update fixtures in `tests/test-update.sh`, plus network integration tests). `UPSKILL=/path/to/upskill bash tests/test-update.sh` runs the update tests against another build.
- Kernel: `bash tests/test-kernel.sh` (Node 24+, npm and network required). Runs actual WASM bash, coreutils, curl, jq, sed, gawk, grep and findutils through the Node kernel entry, with no Chrome harness. It serves the checkout's installer/scripts through the test transport so PR changes are exercised, then installs a public skill from the real GitHub API. It also installs `ai-ecoverse/skills`' slack skill at `1fd7a31` into `/usr/share/skills` with a SLICC 6-style marker and state files, then checks `outdated` and `update`. CI supplies `GH_TOKEN` for API limits; a local shell can supply either token variable.
- Package: `bash tests/test-package.sh` (part of `make test`; Node and npm). Packs the npm package and checks what it ships, that both bins are executable bash scripts, that `prepack` writes the package's version into `upskill` (`scripts/stamp-version.sh`; a checkout's `0.0.0` stays unstamped), and that `npm install -g` runs both.
- Package in the kernel: `bash tests/test-package-kernel.sh` (Node 24+, npm and network required). Installs the packed package with seven's `wasi-pnpm` (`pnpm add -g`) in slicc-kernel and runs `upskill` and `gh-upskill` from `$PNPM_HOME/bin` and `/usr/bin`, then from a tools root as seven installs it (root-owned `/usr/bin/upskill`), and checks that `install.sh` leaves a preinstalled `upskill` alone.
- CI runs lint, shell tests and the kernel tests on pushes/PRs to `main`.

### Releases

Every push to `main` that passes CI runs [semantic-release](https://github.com/semantic-release/semantic-release) (`.releaserc.json`): `feat:` and `fix:` commits publish `@ai-ecoverse/gh-upskill` to npm with provenance, through npm's trusted publishing from `ci.yml` (no npm token; the `fledgling` block in `package.json` describes the trusted publisher, `npm run trust` sets it up), tag `v<version>` and write the GitHub release. Nothing is published by hand. `install.sh` and `gh extension install` keep reading the repository's `main`.

The Node entry uses an in-memory filesystem and a transport without browser CORS constraints. For the final check in seven's actual OPFS/browser environment, run:

```bash
uname -a
printf '%s\n' "$PATH" "$PNPM_HOME"
curl -fsSL https://raw.githubusercontent.com/ai-ecoverse/gh-upskill/main/install.sh | bash
command -v upskill
upskill adobe/helix-website --skill "Searching AEM Documentation"
cat "$HOME/.pi/agent/skills/docs-search/SKILL.md"
```

The tested kernel reports `Emscripten emscripten 4.0.23 #1 wasm32 Emscripten` for `uname -a`; detection uses `uname -s` or `SLICC_PAGE_LOOPBACK`. Repeat the manual check with seven's local proxy disabled and enabled to verify its network transports.

## Related Projects

Part of the **[AI Ecoverse](https://github.com/ai-ecoverse/.github)** - tools for AI-assisted development:
- [yolo](https://github.com/ai-ecoverse/yolo) - AI CLI launcher with worktree isolation
- [ai-aligned-git](https://github.com/ai-ecoverse/ai-aligned-git) - Git wrapper for safe AI commit practices
- [ai-aligned-gh](https://github.com/ai-ecoverse/ai-aligned-gh) - GitHub CLI wrapper for proper AI attribution
- [vibe-coded-badge-action](https://github.com/ai-ecoverse/vibe-coded-badge-action) - Badge showing AI-generated code percentage
- [skills](https://github.com/ai-ecoverse/skills) - AI Ecoverse skills collection

## Acknowledgments

Several features in this release were inspired by the upskill implementation in [slicc](https://github.com/ai-ecoverse/slicc), including registry search, ClawHub/Tessl integration, and ZIP-based installs.
