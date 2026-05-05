# skills

> Everything is just a skill issue.

My personal collection of [Agent Skills](https://agentskills.io/specification) — self-contained capability packages loaded on-demand by agents like [pi](https://github.com/mariozechner/pi-coding-agent), Claude Code, or Codex.

## Layout

Each skill lives in its own directory at the repo root and contains a `SKILL.md`:

```
skills/
├── install.sh
├── README.md
└── <skill-name>/
    ├── SKILL.md          # required: frontmatter + instructions
    ├── scripts/          # optional helpers
    └── references/       # optional docs
```

## Install

The `install.sh` script symlinks skills into your agent's skills directory. Default target is `~/.pi/agent/skills` (pi). Override with `-t` or `SKILLS_TARGET` for Claude Code (`~/.claude/skills`), Codex (`~/.codex/skills`), etc.

```bash
git clone https://github.com/uditgulati/skills.git ~/src/skills
cd ~/src/skills
```

### Install everything

```bash
./install.sh
```

### Install a specific skill (or a few)

```bash
./install.sh my-skill
./install.sh skill-a skill-b
```

### List available skills

```bash
./install.sh --list
```

### Pick a different target

```bash
./install.sh -t ~/.claude/skills              # all skills, into Claude Code
./install.sh -t ~/.codex/skills my-skill      # one skill, into Codex
SKILLS_TARGET=~/.claude/skills ./install.sh   # via env var
```

### Copy instead of symlink

Symlinks are used by default so edits in this repo are picked up live. To copy instead:

```bash
./install.sh -c              # copy all
./install.sh -c my-skill     # copy one
```

### Uninstall

```bash
rm ~/.pi/agent/skills/<skill-name>
```

## Add a new skill

1. Create a directory: `mkdir my-skill`
2. Add `my-skill/SKILL.md` with required frontmatter:
   ```markdown
   ---
   name: my-skill
   description: What it does and when to use it. Be specific.
   ---

   # My Skill
   ...
   ```
3. `./install.sh my-skill`

The `name` must match the directory name and use only lowercase letters, numbers, and hyphens.
