<!-- WORKAROUND: YAML array syntax for paths: is broken in Claude Code.
     The internal CSV parser receives a JS Array object instead of a string,
     causing path matching to silently fail. Rules never load even when
     matching files are read/written.

     Bug: https://github.com/anthropics/claude-code/issues/26868
       "When I configure a rule file under .claude/rules/*.md with multiple
        entries in the paths array, Claude Code CLI does not handle them
        correctly. It appears that only one path is honored; adding a second
        (or more) path entries causes the rule to not be applied as expected."

     See also: https://github.com/anthropics/claude-code/issues/16853
       "Rules with paths: frontmatter in .claude/rules/ subdirectories are
        never automatically loaded into context when reading or editing files
        that match the specified glob patterns."

     Fix: use comma-separated string format + alwaysApply: false -->
---
alwaysApply: false
paths: "**/*.js, **/*.ts, **/*.tsx, **/*.jsx, **/package.json, **/tsconfig.json"
---

# JavaScript / TypeScript Coding Conventions

## General

- Prefer TypeScript over plain JavaScript when possible
- Use TypeScript strict mode (`"strict": true` in tsconfig.json)
- Named exports only - no default exports

## Package Manager

- Use whatever the project already uses (npm, pnpm, yarn)
- If starting fresh, prefer pnpm
- Always commit the lockfile

## Formatting and Linting

- Use the project's existing formatter/linter config
- If starting fresh: Biome or ESLint + Prettier
- No tabs - 2-space indentation

## Type Safety

- Avoid `any` - use `unknown` when the type is truly unknown
- Use type narrowing and guards instead of casting
- Prefer `interface` for object shapes, `type` for unions/intersections
- Use `as const` for literal types

## Error Handling

- Prefer explicit error handling over try/catch where possible
- When using try/catch, catch specific error types
- Always handle promise rejections - no floating promises

## Modules

- Use ES modules (`import`/`export`), not CommonJS (`require`)
- Use path aliases from tsconfig for deep imports

## Testing

- Use the project's existing test framework
- If starting fresh: Vitest for TypeScript projects
- Colocate tests with source as `*.test.ts` or in `__tests__/` directory

## Naming

- `camelCase` for functions, variables
- `PascalCase` for classes, interfaces, type aliases, React components
- `UPPER_SNAKE_CASE` for constants
- Prefix interfaces with context, not `I` (e.g. `UserService` not `IUserService`)

## React (when applicable)

- Functional components only - no class components
- Use hooks for state and effects
- Extract custom hooks for reusable logic
- Props as destructured parameters with TypeScript interfaces

## Style

- Prefer `const` over `let`, never use `var`
- Use template literals over string concatenation
- Use optional chaining (`?.`) and nullish coalescing (`??`)
- Prefer `Array.method()` (map, filter, reduce) over for loops
