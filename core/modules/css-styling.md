---
name: css-styling
description: Styling and design tokens — detecting Tailwind v3 versus v4 before writing syntax, CSS-first configuration with @import "tailwindcss", @theme, @custom-variant and @utility, the v3-to-v4 changes that fail silently, dynamic class names that never generate, class conflict resolution with tailwind-merge, component variants with cva, class-based dark mode, oklch colour tokens, flex layout and token traps that masquerade as other bugs, and the non-Tailwind alternatives with their SSR traps. Use when writing or reviewing Tailwind classes, setting up theme tokens, fixing styles that work in development and vanish in production, content cut off beside a sidebar, wiring dark mode, building component variants, migrating Tailwind v3 to v4, or touching a CSS entry file or Tailwind config.
globs:
  - "**/*.css"
  - "**/tailwind.config.js"
  - "**/tailwind.config.ts"
  - "**/tailwind.config.cjs"
  - "**/tailwind.config.mjs"
alwaysApply: false
---

# Styling & Design Tokens

## Determine the Tailwind version before writing anything

v3 and v4 configuration are **not compatible**. v4 syntax in a v3 project fails silently —
no error, no styles.

| Marker | Version | Configuration lives in |
|---|---|---|
| `@import "tailwindcss";` in the CSS entry | **v4** | The CSS file (`@theme`) |
| `@tailwind base; @tailwind components; @tailwind utilities;` | **v3** | `tailwind.config.js` |
| `@tailwindcss/vite` or `@tailwindcss/postcss` dependency | **v4** | The CSS file |
| Classic `postcss` + `autoprefixer` pairing | usually **v3** | `tailwind.config.js` |

Check `package.json` *and* the CSS entry file. Do not assume a workspace is uniform — v3 and
v4 projects can sit side by side in one monorepo.

## Tailwind v4 — CSS-first configuration

```css
@import 'tailwindcss';

@custom-variant dark (&:is(.dark *));        /* class-based dark mode */

:root {
  --background: oklch(1 0 0);
  --foreground: oklch(0.141 0.005 285.823);
  --primary:    oklch(0.21 0.006 285.885);
}

.dark {
  --background: oklch(0.141 0.005 285.823);
  --foreground: oklch(0.985 0 0);
}

@theme inline {                              /* tokens become utility classes */
  --color-background: var(--background);
  --color-foreground: var(--foreground);
  --color-primary:    var(--primary);
}
```

What matters in that structure:

- **`@theme` is what registers a token as a utility.** `--color-primary` produces
  `bg-primary`, `text-primary`, `border-primary`. A plain custom property on `:root`
  produces **no class at all** — this is the most common "my token does nothing" bug
- **`@theme inline` versus `@theme`.** `inline` writes the variable reference into the
  utility, so the value can be overridden by a narrower scope (`:root` versus `.dark`).
  That is what makes class-based dark mode work without duplicating every token
- **There is no `content` array.** v4 discovers sources automatically, which means anything
  outside that discovery — another workspace package — needs an explicit `@source`
- **`@utility` replaces `@layer utilities`** for custom utilities
- Legacy JS plugins load through `@plugin`, and an old v3 config through `@config` as a
  migration bridge

### The v3 → v4 changes that bite most often

| v3 | v4 | Effect if left unchanged |
|---|---|---|
| `@tailwind base/components/utilities` | `@import "tailwindcss"` | No styles at all |
| `tailwindcss` PostCSS plugin | `@tailwindcss/postcss` or `@tailwindcss/vite` | Build fails |
| `tailwind.config.js` | `@theme` in CSS (or `@config` as a bridge) | Tokens unrecognised |
| `shadow-sm`, `rounded-sm` | `shadow-xs`, `rounded-xs` | Sizes shift one step, silently |
| `outline-none` | `outline-hidden` | Focus ring disappears — an accessibility regression |
| `bg-opacity-50` | `bg-black/50` | Opacity stops applying |

An entry point, not the complete list. Check the official upgrade guide before a large
migration.

## Traps that apply to both v3 and v4

**A dynamically built class name will never be generated.** Tailwind scans source as plain
text; it does not execute the code.

```tsx
// Never emitted — the string "text-red-500" appears nowhere in the source
<p className={`text-${color}-500`} />

// The scanner sees a complete string
const tone = { error: 'text-red-500', ok: 'text-green-500' } as const
<p className={tone[status]} />
```

This is the number one cause of "works in development, missing in production".

**`@apply` is not how components are built.** Moving ten utilities into one custom class
throws away colocation and deletability, and adds a layer that has to be read. Keep `@apply`
for resets in `@layer base`. Component variants belong in `cva`.

**Class conflicts are not resolved by the order they are written in.** `class="p-2 p-4"` is
decided by the order in the generated CSS, not in the markup. Merging classes from props
therefore requires `tailwind-merge`:

```ts
// clsx composes conditionally; twMerge drops the loser.
// clsx alone does NOT resolve conflicts.
export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs))
}
```

## Component variants with cva

`class-variance-authority` separates "which variants exist" from "which classes they use":

```tsx
const button = cva('inline-flex items-center rounded-md font-medium transition-colors', {
  variants: {
    intent: { primary: 'bg-primary text-primary-foreground', ghost: 'hover:bg-accent' },
    size:   { sm: 'h-8 px-3 text-sm', md: 'h-10 px-4' },
  },
  defaultVariants: { intent: 'primary', size: 'md' },
})
```

`VariantProps<typeof button>` derives the prop types from the variant definition — one
source of truth instead of a union written twice. Always merge the result through `cn()` so
a caller's `className` can still override.

## Dark mode

- Class-based (`@custom-variant dark (&:is(.dark *))`) lets the user choose and the choice
  persist
- Media-query based (`prefers-color-scheme`) cannot be overridden by the user
- Apply the class **before first paint**, or there is a light-to-dark flash on every load
- Define **every** token in `:root`, then override only what differs in `.dark`. A token
  that exists in only one block is undefined in the other

## Colour: oklch rather than hex

`oklch(L C H)` makes a lightness change feel uniform across hues, so a generated colour
scale stays consistent and contrast is easier to hold. Contrast targets and how to verify
them → `frontend-quality`.

## Layout and token traps that look like something else

| Symptom | Cause | Fix |
|---|---|---|
| Content cut off on the right, or a horizontal page scrollbar, only while a sidebar is open | The main column is a flex item, and a flex item's default `min-width` is `auto` — its content's width. A wide table or a chart canvas sized in pixels sets that floor, so the column cannot shrink into the space the sidebar leaves. A table's own `overflow-x-auto` wrapper never scrolls, because its parent is never narrower than the table | `min-w-0` (`min-width: 0`) on the flex item that holds the content — in a sidebar layout, the inset or `<main>` |
| The same, but only after the sidebar is closed and reopened | Same cause. A canvas that resized to the wider column on close now holds the column at that width, overflowing by exactly the sidebar's width | Same fix — not a manual `ResizeObserver` on the canvas |
| One heading style renders in the browser's default serif | A self-referencing custom property such as `--font-sans: var(--font-sans)`. A cycle makes the property invalid at computed-value time, so `font-family` falls back silently — no warning anywhere. Typically left behind when the font loader that was meant to define the variable is removed or never wired | Give the token a real value, or point it at the variable the font loader actually sets |
| A chart or map ignores the theme switch while the rest of the page follows | Canvas and WebGL libraries draw pixels; they never read CSS custom properties | Keep a per-theme palette in code, mirroring the CSS tokens, and re-apply it through the library's options API whenever the resolved theme changes |

**`overflow-x: hidden` is not a fix for any of these.** It hides the scrollbar while the
content stays clipped — the cut-off button is still gone, now with no scrollbar to reach it.
Locking overflow at `body` is fine as a guard against a transient overflow during a width
transition, but only after the root cause is fixed and only when every legitimately wide
element scrolls inside its own container.

Verify a layout fix by measuring, not by looking: compare `getBoundingClientRect().width` of
the column before and after, across several rapid open/close cycles. A screenshot of one
state proves nothing about the transition between states.

## When it is not Tailwind

**CSS Modules** — per-file scoping, zero runtime, safe for SSR. Cross-file composition via
`composes`.

**Emotion / MUI** — `sx` for one-off adjustments, `styled()` for reuse. The main trap is
SSR: without correct cache setup, styles inject after hydration and produce a flash of
unstyled content. Read theme values through the theme object, not hardcoded ones.

**styled-components** — the same runtime CSS-in-JS trade-off and the same SSR consequence.
Weigh its runtime cost on pages judged by Core Web Vitals.

**Mixing Tailwind with a CSS-in-JS library inside one component is an expensive source of
specificity conflicts.** If both must coexist, split them at a component boundary and write
down why.

## Before claiming it is done

- [ ] The project's Tailwind version was checked and the syntax matches it
- [ ] No class name built from a template literal
- [ ] Classes merged through `cn()` (clsx + tailwind-merge), not string concatenation
- [ ] New tokens registered in `@theme`, not only as `:root` custom properties
- [ ] Dark mode actually exercised, not assumed — including canvas-rendered components
- [ ] No custom property defined in terms of itself
- [ ] Layout with a collapsible sidebar exercised in both states and through the transition,
      with the widest content the page can show
- [ ] A production build was run — many Tailwind problems only appear after the production
      scan

## Related modules

`frontend-quality` for contrast targets and the accessibility cost of removing focus
outlines · `pr-review` for the review checklist
