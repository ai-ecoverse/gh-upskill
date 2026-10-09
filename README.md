![Upskill – Install Agent Skills](hero-banner.jpeg)

# upskill

[![36% Vibe_Coded](https://img.shields.io/badge/36%25-Vibe_Coded-ff69b4?style=for-the-badge&logo=claude&logoColor=white)](https://github.com/ai-ecoverse/vibe-coded-badge-action)

Install [Agent Skills](https://agentskills.io) from GitHub repositories.

> **Note:** This tool implements the [agentskills.io specification](https://agentskills.io/specification). Your AI agent (Claude Code, Cursor, VS Code, etc.) likely already supports this spec natively and can discover skills automatically. This tool is primarily useful for:
> - Installing skills from private repositories
> - Batch installing multiple skills
> - Managing skills across projects

## Install

- Standalone
  - macOS/Linux: `curl -fsSL https://raw.githubusercontent.com/ai-ecoverse/gh-upskill/main/install.sh | bash`
  - Custom prefix: `curl -fsSL https://raw.githubusercontent.com/ai-ecoverse/gh-upskill/main/install.sh | bash -s -- --prefix ~/.local`

- GitHub CLI extension
  - `gh extension install ai-ecoverse/gh-upskill`
  - Then run via `gh upskill ...` (or use `upskill` directly)

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

**Overwrite existing skills:**
```
upskill anthropics/skills --all --force
```

### Subcommands

| Subcommand | Description |
|------------|-------------|
| `list` | List locally installed/discovered skills |
| `info <name>` | Show details about a locally installed skill |
| `read <name>` | Print the SKILL.md content of a locally installed skill |
| `search <query>` | Search ClawHub and Tessl skill registries |

```
upskill list                        # Show local skills
upskill info pdf                    # Show skill details
upskill read pdf                    # Print SKILL.md content
upskill search "pdf converter"      # Search registries
```

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
| `--force` | Overwrite existing skill directories |
| `-i` | Add `.agents/skills/` to `.gitignore` |
| `-q, --quiet` | Reduce output |

## How it works

1. With git, gh, tar and unzip available, downloads a ZIP archive and falls back to `gh repo clone` if needed.
2. When any of those tools is missing and `jq` is available (or `unzip` is unavailable), uses `curl` and `jq` with GitHub's recursive git trees API to discover `**/SKILL.md`. Downloads manifests for discovery, then the selected skills' files individually through the contents API, pinned to the resolved commit. No archive extraction or git is needed. Desktop installations with `unzip` but no `jq` retain the ZIP path.
3. Copies selected skill directories, including hidden files and executable modes, to the destination.

Authentication uses `GITHUB_TOKEN`, then `GH_TOKEN`, then `gh auth token` if available. This supports private repositories and higher API rate limits. Errors distinguish rate limits from permission failures. The REST path rejects truncated trees and unsafe paths instead of installing an incomplete or unsafe skill. Symbolic links with absolute targets or `..` components are rejected. ClawHub's ZIP downloads still require `unzip`; Tessl skills that resolve to GitHub can use the REST path.

### seven / SLICC kernel

Install directly in seven's shell:

```bash
curl -fsSL https://raw.githubusercontent.com/ai-ecoverse/gh-upskill/main/install.sh | bash
upskill adobe/helix-website --skill "Searching AEM Documentation"
```

Seven is detected when `uname -s` reports `Emscripten`, or when `SLICC_PAGE_LOOPBACK` is set. The installer defaults to `$PNPM_HOME/bin`; if `PNPM_HOME` is absent it uses `~/.local/share/pnpm/bin` and checks that directory is on PATH. Explicit `--prefix` and `--bin-dir` keep their usual meaning. No npm package is needed.

In this environment upskill defaults to `~/.pi/agent/skills/<name>/SKILL.md`, including with `-g`. `--dest` or `--dest-path` overrides that default. `list`, `info` and `read` include pi's user skills and `.pi/skills`; pi loads project skills only in trusted folders. The destination also works explicitly outside seven:

```bash
upskill adobe/helix-website --skill "Searching AEM Documentation" --dest "$HOME/.pi/agent/skills"
```

Without slicc-node, seven reaches the web through the page's fetch, so `raw.githubusercontent.com` and `api.github.com` must answer with CORS headers; both provide them. Other sources may need the local proxy. Set `GITHUB_TOKEN` or `GH_TOKEN` in the shell for private repositories and to avoid GitHub's [60 requests per hour unauthenticated limit](https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api), shared by originating IP address.

The follow-up gelatiere integration can bootstrap the same installer:

```bash
command -v upskill || curl -fsSL https://raw.githubusercontent.com/ai-ecoverse/gh-upskill/main/install.sh | bash
upskill adobe/helix-website --skill "Searching AEM Documentation"
```

### Claude Code auto-detection

When `--dest-path` is **not** used, upskill automatically detects Claude Code environments and dual-installs skills:

- **Local installs:** if a `.claude/` directory or `CLAUDE.md` file exists in the project, skills are also installed to `.claude/skills/`
- **Global installs (`-g`):** if `~/.claude/` exists, skills are also installed to `~/.claude/skills/`

Using `--dest-path` disables this auto-detection — skills are only installed to the specified path.

## Development

- Lint: `make lint` (shellcheck)
- Test: `make test` (portable fixtures plus network integration tests)
- Kernel: `bash tests/test-kernel.sh` (Node 24+, npm and network required). Runs actual WASM bash, coreutils, curl, jq, sed, gawk, grep and findutils through the Node kernel entry, with no Chrome harness. It serves the checkout's installer/scripts through the test transport so PR changes are exercised, then installs a public skill from the real GitHub API. CI supplies `GH_TOKEN` for API limits; a local shell can supply either token variable.
- CI runs lint, shell tests and the kernel test on pushes/PRs to `main`.

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
