# ADR-006: Mac Web Application Stack

**Status:** Accepted for MVP  
**Date:** 2026-07-26  
**Decision owners:** Product and Engineering

## Context

Rainflow requires a web interface optimized for Mac, sharing one server-authoritative ledger with the iPhone application. The user group is smaller than 50 people, so the implementation should prioritize delivery speed, maintainability, accessibility, and a clean integration boundary with Supabase rather than infrastructure scale.

## Decision

Use **Next.js with TypeScript** for the MVP web application.

- Use the App Router.
- Use server and client components according to interaction needs.
- Keep Supabase authentication and API access behind adapters in `lib` rather than importing provider clients throughout presentation components.
- Use CSS custom properties and locally owned components for the Rainflow design system.
- Avoid a large UI framework in the first pass.
- Treat the framework choice as replaceable; domain types and command contracts remain framework-independent.

## Rationale

- Strong TypeScript support and conventional routing.
- Suitable for authenticated application pages and responsive desktop UI.
- Straightforward deployment options.
- Good compatibility with Supabase without making Supabase a UI dependency.
- The application size does not justify a custom client framework or micro-frontend architecture.

## Consequences

### Positive

- One repository can hold pages, components, API adapters, and tests.
- The first pass can be built quickly with accessible HTML and CSS.
- Server-side session handling remains available where useful.

### Negative

- The team must understand server/client component boundaries.
- Framework upgrades remain a maintenance responsibility.

### Neutral

- The current web implementation uses browser-local prototype data behind repository-shaped modules. Connecting those modules to authenticated Supabase commands does not require redesigning the screens.

## Rejected Alternatives

### Native macOS application

Rejected for the MVP because the requested desktop experience is web-based.

### Static HTML-only application

Rejected because authenticated workflows, routing, forms, and future server integration benefit from an application framework.

### Large component framework

Deferred because the visual language is custom and the project does not yet need the dependency or theming overhead.

## Reconsideration Triggers

Revisit this choice if:

- Hosting constraints prohibit the runtime model.
- The web client becomes mostly static and a simpler framework provides meaningful operational value.
- The project team standardizes on another TypeScript framework.

## Related Documents

- [Design specification](../DESIGN_SPEC.md)
- [Architecture](../ARCHITECTURE.md)
- [ADR-005: Client-server authority](./ADR-005-ClientServer.md)
