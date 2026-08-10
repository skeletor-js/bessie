# Design asset provenance

## Bessie license

Bessie's own source is licensed under Apache-2.0. Packaged applications include
the complete project license at `Contents/Resources/Bessie-LICENSE.txt`. This
attribution file supplements that license and the third-party notices retained
below; it does not replace them.

## Agent identity

Bessie does not package or display third-party agent or service marks. Agent
identity remains available through the ordinary Herdr-provided pane and process
text already shown by the interface.

Existing Bessie cow/logo/cowprint assets retain their existing project
provenance. No cold-open video is included here; that belongs to plan unit U8.

## Phosphor interface icons

The 30 packaged `Phosphor*.svg` interface icons are SVG adaptations of
Phosphor Icons Web v2.1.1 Thin and Fill artwork. The supplied design source
identifies Phosphor Icons, designers Tobias Fried and Helena Zhang, version
2.1, and the MIT license; Bessie retains that provenance here.

Source and exact license:

- https://github.com/phosphor-icons/web/tree/v2.1.1
- https://github.com/phosphor-icons/web/blob/v2.1.1/LICENSE

MIT License

Copyright (c) 2020-2021 Phosphor Icons

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

## Terminal and update dependencies

Bessie directly depends on
[`libghostty-spm` 1.3.2](https://github.com/Lakr233/libghostty-spm/tree/1.3.2)
for `GhosttyTerminal` and the prebuilt `libghostty` binary. That package is MIT
licensed and pins upstream Ghostty commit
[`35e1a0160c4f6797e1bb1ef8e7a2b8c6b114ab58`](https://github.com/ghostty-org/ghostty/tree/35e1a0160c4f6797e1bb1ef8e7a2b8c6b114ab58),
which is also MIT licensed. Bessie packages exact copies of both authoritative
license files as `libghostty-spm-LICENSE.txt` and `Ghostty-LICENSE.txt`:

- https://github.com/Lakr233/libghostty-spm/blob/1.3.2/LICENSE
- https://github.com/ghostty-org/ghostty/blob/35e1a0160c4f6797e1bb1ef8e7a2b8c6b114ab58/LICENSE

Bessie directly depends on
[`Sparkle` 2.9.5](https://github.com/sparkle-project/Sparkle/tree/2.9.5) for
application updates. Bessie packages Sparkle's complete `LICENSE`, including
the external notices for code incorporated into Sparkle, as
`Sparkle-LICENSE.txt`:

https://github.com/sparkle-project/Sparkle/blob/2.9.5/LICENSE

These references identify dependencies and preserve license handling; they do
not imply that the Ghostty, libghostty-spm, or Sparkle authors endorse Bessie.

## Catppuccin native and terminal palettes

Bessie's native Latte, Frappé, Macchiato, and Mocha palettes use the official
Catppuccin palette v1.8.0 data:

https://github.com/catppuccin/palette/blob/v1.8.0/palette.json

Native semantic assignments follow the Catppuccin style guide pinned at commit
`a310b246a3cfcdadb6f5b174d879743e084e87ea`:

https://github.com/catppuccin/catppuccin/blob/a310b246a3cfcdadb6f5b174d879743e084e87ea/docs/style-guide.md

Thanks to madeofbees for calling attention to Catppuccin semantic fidelity in
Bessie's native chrome.

Bessie also includes adapted terminal palette values from the official
Catppuccin Ghostty port, pinned at commit
`5a58926563ddacbde4a12b4a347464c2c6945393`:

https://github.com/catppuccin/ghostty/tree/5a58926563ddacbde4a12b4a347464c2c6945393

Bessie authors its own native application mappings and bounded accessibility
derivatives around the canonical palette. No Ghostty theme package, editor
extension, font, icon, or marketplace asset is included. Catppuccin and its
contributors do not endorse Bessie.

MIT License

Copyright (c) 2021 Catppuccin

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
