# Credits

Bessie exists because a lot of people made thoughtful things before it.

## The name

A warm thank-you to [@madeofbees](https://github.com/madeofbees) for the **Bessie** name idea. It gave this native Herdr companion its friendly identity—and made the cowprints inevitable.

## The foundation

Bessie is built around [Herdr](https://github.com/herdrdev/herdr). Thank you to [Oğulcan Çelik](https://github.com/ogulcancelik) and every Herdr contributor for the runtime, public state and control surfaces, agent model, and plugin ecosystem that make a native client possible. Bessie bundles an exact Herdr runtime under Apache-2.0; its complete license is included in the app at `Contents/Resources/Herdr/LICENSE`.

## Community projects that shaped V1

Herdr's community explored many of the jobs Bessie brings together. In particular:

- [AltanS/collie](https://github.com/AltanS/collie) inspired attention-first agent grouping, actionable disconnected states, reconnect behavior, and restrained notification policy.
- [dcolinmorgan/herdr-remote (Herdi)](https://github.com/dcolinmorgan/herdr-remote) showed the value of ambient native macOS status, menu-bar awareness, and clear remote lifecycle states.
- [cobanov/herdr-ntfysh](https://github.com/cobanov/herdr-ntfysh) informed notification deduplication, diagnostics, secret-conscious delivery, and failure isolation.
- [smarzban/herdr-file-viewer](https://github.com/smarzban/herdr-file-viewer) informed Bessie's read-only, Git-aware file tree and diff-first viewing, including bounded and stale-safe repository reads.
- [persiyanov/herdr-reviewr](https://github.com/persiyanov/herdr-reviewr) inspired changed-file navigation, preservation of work through send failures, and explicit stale-state handling.
- [dwarvesf/herdr-quicklook](https://github.com/dwarvesf/herdr-quicklook) inspired path-and-line handoff and the progression from a lightweight preview to a persistent viewer or external editor.
- [thanhdat77/herdr-navigator](https://github.com/thanhdat77/herdr-navigator) informed dense entity rows, reuse-first navigation, jump-back behavior, and an entity-aware command palette.
- [yuk1ty/herdr-spreader](https://github.com/yuk1ty/herdr-spreader) informed deterministic layout application, previewable plans, and reconciliation through public Herdr operations.
- [cloudmanic/herdr-plus](https://github.com/cloudmanic/herdr-plus) provided prior art for approachable project recipes and context-aware actions.
- [JanTvrdik/herdr-command-palette](https://github.com/JanTvrdik/herdr-command-palette) highlighted stable action identity and preserving the context from which a command palette was opened.
- [nikok6/herdr-mirror](https://github.com/nikok6/herdr-mirror) informed named remote connections, compatibility and reconnect states, and the important distinction between observing, controlling, detaching, and terminating.

These are acknowledgments of ideas and interaction lessons—not claims that those projects are Bessie dependencies or that their code was copied into Bessie. V1 is an independent native Swift implementation built against Herdr's public surfaces. Project names and links identify the prior art; their inclusion does not imply endorsement of Bessie by any author or contributor.

## Direct dependencies and assets

Thank you to the people behind the software and design resources Bessie directly ships or uses:

- [Herdr](https://github.com/herdrdev/herdr), the bundled Apache-2.0 runtime and product foundation.
- [libghostty-spm](https://github.com/Lakr233/libghostty-spm) and [Ghostty](https://github.com/ghostty-org/ghostty), which provide Bessie's real terminal surfaces, under their verified MIT licenses.
- [Sparkle](https://github.com/sparkle-project/Sparkle), which provides application updates under its distribution's license and included external notices.
- [Phosphor Icons](https://phosphoricons.com/), whose MIT-licensed Thin and Fill artwork supplies Bessie's interface icons.
- [Catppuccin](https://github.com/catppuccin) and the [Catppuccin Ghostty port](https://github.com/catppuccin/ghostty), whose MIT-licensed palettes informed Bessie's native themes and terminal palette values.

The packaged [`ATTRIBUTION.md`](Sources/BessieApp/Resources/ATTRIBUTION.md) records exact provenance, pinned versions or revisions, license references, and the separate status of product/service marks. Exact license files for libghostty-spm, Ghostty, and Sparkle ship beside it in `Contents/Resources`.

## Legal note

Credits are gratitude, not a license grant, endorsement, sponsorship, or transfer of ownership. All project names, service names, and marks remain the property of their respective owners.

Bessie's own source is available under the [Apache License 2.0](LICENSE). Packaged applications include that license at `Contents/Resources/Bessie-LICENSE.txt`. Nothing in this credits document substitutes for the third-party notices that accompany redistributed components and assets.
