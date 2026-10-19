# TravelWise — Workspace Agent Guidelines

TravelWise is a monorepo for an AI travel platform:

- `apps/api`: FastAPI, SQLModel, SQL Server, ChromaDB and LangChain.
- `apps/web`: Next.js App Router, React, TypeScript and Tailwind CSS.
- `apps/mobile`: Flutter and Dart.

## Shared Rules

1. Read the relevant code, tests and documentation before editing.
2. Reuse existing services, schemas, helpers and patterns before adding new logic.
3. Make precise changes only in files required by the request. Preserve unrelated working-tree changes.
4. Preserve existing API contracts and behavior unless a change is explicitly requested.
5. Keep types and validation explicit. Do not hide errors with broad catches, silent fallbacks, `as any` or `# type: ignore`.
6. Read secrets, API keys, database credentials and external URLs from configuration. Never hardcode them.
7. Update directly related documentation and tests when behavior or public interfaces change.
8. Prefer the smallest validation command that covers the change, then report the exact command and result.
9. Use Windows paths with `\` in terminal commands. Do not use destructive Git commands without explicit approval.

Project-specific rules are split into file instructions under `.github/instructions/` and are loaded according to the files being changed.
