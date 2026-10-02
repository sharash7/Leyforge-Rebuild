# Leyforge Repository Layout v0.3

```text
Leyforge/
├─ project.godot                  # Created by the real Godot bootstrap
├─ README.md
├─ AGENTS.md
├─ .gitignore
├─ addons/
├─ assets/
├─ content/                       # Canonical game content domains
├─ scenes/
├─ src/
│  ├─ game/                       # Leyforge-specific gameplay/presentation
│  ├─ lfe/                        # Reusable runtime infrastructure
│  └─ forge_eng/                  # Reusable authoring infrastructure
├─ tools/
│  ├─ forge/
│  │  └─ workspaces/              # Explicit known Forge sections
│  └─ development/
├─ tests/
└─ docs/
   ├─ SHOWCASE_MASTER_COVERAGE.md
   ├─ SHOWCASE_BUILD_WAVES.md
   ├─ ARCHITECTURE_BOUNDARIES.md
   ├─ PRODUCTION_COVERAGE_MAP.md
   ├─ SHOWCASE_SLICE.md
   └─ REPOSITORY_LAYOUT.md
```

The detailed subdirectories make known future ownership visible. They are not instructions to generate speculative code.
