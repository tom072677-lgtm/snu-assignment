---
tags: [sharap, moc]
---
# sharap — Project Wiki 🏠

The knowledge base for **sharap** (the SNU student app). This `docs/` folder is an **Obsidian vault**: open it in Obsidian for linking + graph + search, and let terminal **Claude Code** read and update it as you work.

> Quick machine-readable facts live in the project [CLAUDE.md](../CLAUDE.md) (auto-loaded by Claude Code). This wiki is the **narrative** layer — the *why*, the decisions, and the war-stories.

## Map
- [[Architecture]] — monorepo layout, build/deploy, the dead-folder rule
- [[Department Notices]] — the notice-scraping feature, per-department status, and the add-a-department runbook
- [[Decisions]] — decision log (server vs client vs headless, the cert pin, …)
- [[Debugging Notes]] — war-stories & reusable lessons (the anthropology TLS saga, the stale-folder trap, …)

## How to use this with Claude Code
- From the terminal, `cd` into the repo (or this `docs/` folder) and Claude reads these notes for context from the first message.
- After solving something tricky, tell Claude: *"write up what we just learned in [[Debugging Notes]]"* or *"update [[Department Notices]] with the new dept."* — the wiki **compounds** instead of evaporating when the chat ends.
- Capture outside reading (articles, videos, docs) with the **Obsidian Web Clipper** into a *separate* personal vault; this `docs/` vault is for the project specifically.

## Current focus
Make **every** SNU department's notices viewable in-app (like the existing PE-dept tab). Live per-department status: [[Department Notices]].
