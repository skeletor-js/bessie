# Review and land

**Status:** Exploring  
**Roadmap horizon:** Post-V1  
**Product area:** Source control and delivery  
**Implementation approval:** Not granted by this document

## Outcome

Support a bounded path from reviewed workspace changes to an explicitly owned delivery action, if that proves better than a visible Herdr pane or external Git tool.

## Why this exists

Beyond diff viewing, the exploration includes staging, test status, commits, push, draft PR, merge/rebase choices, and landing checks.

## First useful slice

- Keep review read-only until Workspace Files and Diff are trustworthy.
- Add test/build status associated with a named revision or working-tree state.
- Explore stage/unstage with exact file or hunk previews and clear Git ownership.
- Prototype a commit composer without push or merge.

## Possible later scope

- Commit and push.
- Draft pull request handoff.
- Merge/rebase selection and landing checks.
- Compare concurrent-agent or unfinished changes.

## Sources of truth and dependencies

Workspace diff foundation, Git ownership model, typed test status, and explicit side-effect contracts; PR actions require repository-host integration.

Bessie must preserve Herdr as the authority for sessions, panes, processes, agents, and durable session state. Any additional owner—filesystem, Git, agent integration, companion plugin, or provider—must be named explicitly in the eventual implementation plan.

## Principal risks

- This can turn Bessie into a blurry Git client or IDE.
- Stage, discard, commit, push, rebase, and merge have very different failure and approval boundaries.

## Open questions

- Which action is materially better in Bessie than in a Herdr pane?
- Should commit be the hard boundary, leaving push and landing external?

## Graduation criteria

Before this idea becomes **Proposed**, validate the first useful slice against the current Herdr contracts, identify local and remote behavior, define failure and empty states, and split any high-risk side effects into separately approved milestones.
