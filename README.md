![Upskill – Install Agent Skills](hero-banner.jpeg)

# upskill

[![26% Vibe_Coded](https://img.shields.io/badge/26%25-Vibe_Coded-ff69b4?style=for-the-badge&logo=claude&logoColor=white)](https://github.com/trieloff/vibe-coded-badge-action)

Install [Agent Skills](https://agentskills.io) from GitHub repositories.

> **Note:** This tool implements the [agentskills.io specification](https://agentskills.io/specification). Your AI agent (Claude Code, Cursor, VS Code, etc.) likely already supports this spec natively and can discover skills automatically. This tool is primarily useful for:
> - Installing skills from private repositories
> - Batch installing multiple skills
> - Managing skills across projects

## Install

- Standalone
  - macOS/Linux: `curl -fsSL https://raw.githubusercontent.com/trieloff/gh-upskill/main/install.sh | bash`
  - Custom prefix: `curl -fsSL https://raw.githubusercontent.com/trieloff/gh-upskill/main/install.sh | bash -s -- --prefix ~/.local`

- GitHub CLI extension
  - `gh extension install trieloff/gh-upskill`
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

### Install skills globally (personal skills)

Use the `-g` or `--global` flag to install skills to `~/.skills` instead of the project's `.skills` directory:

```
upskill -g anthropics/skills --skill pdf --skill xlsx
```

When installing globally:
- Skills are installed to `~/.skills`
- `.agents/discover-skills` and `AGENTS.md` are not modified (since these are project-specific)

### Install to custom destination

Use `--dest-path` to install skills to a custom location:

```
upskill anthropics/skills --skill pdf --dest-path .claude/skills
```

This is useful for compatibility with tools that expect skills in different locations (e.g., `.claude/skills`).

### Options

| Option | Description |
|--------|-------------|
| `-g, --global` | Install to `~/.skills` (personal skills) |
| `-b, --branch <ref>` | Branch, tag, or commit to clone |
| `--dest-path <path>` | Custom destination path (overrides `-g`) |
| `--list` | List available skills without installing |
| `--skill <name>` | Install specific skill(s) (repeatable) |
| `--all` | Install all discovered skills |
| `-i` | Add `.skills/` to `.gitignore` |
| `-q, --quiet` | Reduce output |

## How it works

1. Clones the source repository to a temp directory
2. Scans for all `**/SKILL.md` files (per agentskills.io spec)
3. Copies selected skill directories to `.skills/` (or custom destination)
4. Creates `.agents/discover-skills` helper script
5. Updates `AGENTS.md` with skills section (if source has one)

## Discover installed skills

After installing, list available skills in your project:

```
./.agents/discover-skills
```

This scans both project skills (`.skills/`) and personal skills (`~/.skills/`), plus legacy `.claude/skills` locations for backwards compatibility.

## Development

- Lint: `make lint` (shellcheck)
- Test: `make test` (network required for `gh repo clone`)
- CI runs lint + tests on pushes/PRs to `main`.

## Related Projects

Part of the **[AI Ecoverse](https://github.com/trieloff/ai-ecoverse)** - tools for AI-assisted development:
- [yolo](https://github.com/trieloff/yolo) - AI CLI launcher with worktree isolation
- [ai-aligned-git](https://github.com/trieloff/ai-aligned-git) - Git wrapper for safe AI commit practices
- [ai-aligned-gh](https://github.com/trieloff/ai-aligned-gh) - GitHub CLI wrapper for proper AI attribution
- [vibe-coded-badge-action](https://github.com/trieloff/vibe-coded-badge-action) - Badge showing AI-generated code percentage
