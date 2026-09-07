---
name: frontend-quality
description: Measurable frontend quality — Core Web Vitals (LCP, INP, CLS) with their thresholds, a symptom-to-cause table, and the difference between lab and field data; JavaScript bundle budgets and diagnosing a size regression; and practical WCAG 2.2 AA accessibility covering semantics, keyboard reachability, focus management in overlays, form labelling and error association, contrast and target size, live regions, and the first rule of ARIA. Use when a page feels slow, a Lighthouse score drops, layout shifts during load, interactions feel laggy, a bundle grows, when building a modal, dropdown, form or table that must work by keyboard and screen reader, or when asked for a performance or accessibility audit.
alwaysApply: false
---

# Frontend Quality — Performance & Accessibility

The two things most often claimed without being measured. The rule here: **numbers first,
then fixes.** Never propose an optimisation without naming the metric it moves and how that
metric is measured.

## Core Web Vitals — thresholds

| Metric | Good | Needs work | What it measures |
|---|---|---|---|
| **LCP** Largest Contentful Paint | ≤ 2.5 s | > 4.0 s | When the main content becomes visible |
| **INP** Interaction to Next Paint | ≤ 200 ms | > 500 ms | Responsiveness across all interactions (replaced FID in 2024) |
| **CLS** Cumulative Layout Shift | ≤ 0.1 | > 0.25 | Visual stability |

Thresholds are judged at the **75th percentile of real users**, not on one Lighthouse run on
a developer laptop. Lighthouse is lab data: useful for diagnosis, not valid evidence for
"it is fast now". That claim needs field data — the `web-vitals` library reporting to an
analytics backend, or CrUX.

## Symptom → first thing to check

| Symptom | Check first | Direction |
|---|---|---|
| Slow LCP, large TTFB | The server or a missing edge cache | Cache/CDN, less work on the render path → `devops-pipeline` |
| Slow LCP, small TTFB | The LCP element is discovered late — a lazy-loaded hero, or one behind a component waiting on JS | Never `loading="lazy"` on the LCP element; `fetchpriority="high"`; preload the hero and fonts |
| Slow LCP only on data-backed pages | A request waterfall — fetching on the client, or chained fetches | Move fetching to the server and parallelise |
| Poor INP on click or type | The handler does heavy synchronous work, or re-renders the whole tree | Break up the work, defer what is not urgent |
| Poor INP only on heavy pages | Too much JavaScript executing during hydration | Fewer client components, push the client boundary toward the leaves |
| High CLS during load | Images, iframes, or video without dimensions | `width` + `height`, or `aspect-ratio` |
| High CLS once text appears | A font swap reflows the layout | `font-display`, a metric-matched fallback, preload the primary font |
| High CLS when data arrives | Content inserted above content already visible | A skeleton of the same size; never inject a banner above the fold |
| Bundle grows suddenly | One import pulling in a large library — dates, charts, a whole icon set | Analyse the bundle, import the specific path, lazy-load heavy routes |

Measure before concluding: the browser Performance panel for INP and long tasks, a bundle
analyser for size, `web-vitals` for field data. Investigation method → `debugging`.

## Bundle

- Set a **budget** — initial JS per route — and fail the build when it is exceeded. Without
  a number, no regression is ever detected
- Split by route first, then by component. Heavy components not visible on first paint
  (charts, editors, maps) are lazy-loaded
- Watch barrel files (`index.ts`) that drag in a whole module graph. Import the specific path
- Date, chart, and icon libraries are the three most common sources of bloat. Check whether
  ten icons arrived with a package containing thousands

## Accessibility — practical WCAG 2.2 AA

**The first rule of ARIA: do not use ARIA when a native HTML element already does the job.**
`<button>` beats `<div role="button" tabindex="0" onKeyDown={…}>` on every dimension. ARIA
adds no behaviour — it only changes what is announced.

**Semantics and structure**
- One `<h1>` per page; heading levels descend without skipping
- Real landmarks (`<main>`, `<nav>`, `<header>`), not a page of `<div>`
- The page language is set (`<html lang="…">`), and it matters for screen reader pronunciation

**Keyboard**
- Everything clickable is reachable and operable by keyboard
- Focus order follows visual order; no positive `tabindex`
- The focus indicator is visible. `outline: none` with no replacement is an accessibility
  bug — in Tailwind v4 note the `outline-none` → `outline-hidden` rename (→ `css-styling`)
- No keyboard trap: anything enterable must be leaveable

**Focus in overlays**
- A modal moves focus inside on open, traps it while open, **returns focus to the trigger**
  on close, and closes on `Escape`
- Content behind the modal is hidden from screen readers (`inert` or `aria-hidden`)
- This is the strongest argument for using a tested primitive library rather than writing
  overlay focus management by hand

**Forms**
- Every input has an associated `<label>`, not just a placeholder
- Error messages are linked to the input (`aria-describedby`) and announced, not merely
  coloured red
- Required fields are marked programmatically (`required` / `aria-required`), not only with
  a visual asterisk
- A validation failure moves focus to the first invalid field

**Visual**
- Text contrast at least **4.5:1** (3:1 for large text); UI components and graphics **3:1**
- Colour is never the only carrier of information — a status needs an icon or text too
- Touch targets at least **24×24 px** (WCAG 2.2, 2.5.8)
- The page remains usable at 200% zoom
- Respect `prefers-reduced-motion` for large animations

**Dynamic content**
- Toasts, live search results, and async status are announced through a live region
  (`aria-live="polite"`, or `role="alert"` when urgent)
- Loading states carry text, not only a spinner
- Descriptive `alt` for meaningful images, `alt=""` for decorative ones — a missing attribute
  means something different from a deliberately empty one

## Testing

Three layers, none of which replaces another:

1. **Automated** — axe, in development or wired into the E2E suite. Catches roughly a third
   of issues: contrast, missing labels, malformed ARIA
2. **Keyboard** — walk the whole flow with Tab, Shift+Tab, Enter, Space, Escape, and arrows
   only. No mouse. This finds the class of problem automation cannot detect
3. **Screen reader** — exercise the critical flows (sign-in, checkout, the primary form)

## Before claiming it is done

- [ ] Metrics stated as numbers with the measurement method, not "feels faster"
- [ ] The LCP element is not lazy-loaded
- [ ] Every image and media element has dimensions or an `aspect-ratio`
- [ ] The touched route's bundle did not grow without a written reason
- [ ] The changed flow was completed using the keyboard alone
- [ ] New modal or dropdown: focus trapped, `Escape` closes, focus returns to the trigger
- [ ] New inputs have associated labels and linked error messages
- [ ] axe is clean on the pages touched

Be honest about the limits: a type check and a successful build prove nothing about
performance or accessibility. If it has not been measured or walked with a keyboard, say so
rather than claiming it is done.

## Related modules

`css-styling` for tokens, contrast sources, and the focus-outline rename · `devops-pipeline`
for budget enforcement in CI · `debugging` for the investigation method
