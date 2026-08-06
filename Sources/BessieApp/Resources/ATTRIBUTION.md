# Design asset provenance

## Original Pre-v1 named marks

The four named agent marks were extracted from the compressed SVG asset records
in the user-supplied `Bessie Pre-v1 UI Update.html` design source. Packaging only
normalizes SVG markup and adds missing accessible titles; path geometry is the
embedded source geometry:

| Packaged file | Embedded asset ID | Upstream owner / license status |
| --- | --- | --- |
| `AgentClaude.svg` | `d4fadd6a-e121-4ced-85ae-4023a3f84a7f` | Anthropic Claude Code mark; trademarked; no standalone license was supplied |
| `AgentCodex.svg` | `a4d7865e-8453-4e93-9207-659294800903` | OpenAI Codex mark; trademarked; no standalone license was supplied |
| `AgentGrok.svg` | `6e6995e3-9398-4b45-8fbb-441934ad34a1` | xAI Grok mark; trademarked; no standalone license was supplied |
| `AgentAmp.svg` | `33f2f2a8-be73-4be4-b812-b7eb69a35fbb` | Sourcegraph Amp mark; trademarked; no standalone license was supplied |

They are included solely to identify the corresponding service in Bessie. No
ownership or endorsement is claimed. Distribution approval should include a
trademark/license review because the supplied design artifact did not grant a
general redistribution license.

## Extended Herdr agent marks (2026-08-04)

Additional marks were supplied by Jordan into the Bessie workstream inbox and
packaged into `Sources/BessieApp/Resources/` for the remaining Herdr-supported
agent kinds (plus OpenClaw). Packaging normalizes titles and drops fixed
width/height when a viewBox is present; path/geometry is otherwise as supplied.

| Packaged file | Inbox source | Notes |
| --- | --- | --- |
| `AgentPi.svg` | `pi.svg` | Herdr kind `pi` |
| `AgentOmp.svg` | `Oh My Pi.svg` | Herdr kind `omp` |
| `AgentCursor.svg` | `cursor.svg` | Herdr kind `cursor` |
| `AgentDevin.svg` | `Devin AI.svg` | Herdr kind `devin` |
| `AgentAgy.svg` | `antigravity.svg` | Herdr kind `agy` |
| `AgentCline.svg` | `cline.svg` | Herdr kind `cline` |
| `AgentMastraCode.svg` | `Mastra Logo.svg` | Herdr kind `mastracode`; true vector paths (replaced prior PNG-in-SVG drop) |
| `AgentKimi.svg` | `kimi.svg` | Herdr kind `kimi` |
| `AgentKiro.svg` | `kiro.svg` | Herdr kind `kiro` |
| `AgentDroid.svg` | `Droid.svg` | Herdr kind `droid` |
| `AgentKilo.svg` | `kilocode.svg` | Herdr kind `kilo` |
| `AgentQodercli.svg` | `Quodercli.svg` | Herdr kind `qodercli` |
| `AgentMaki.svg` | `Maki.svg` | Herdr kind `maki` |
| `AgentOpenClaw.svg` | `openclaw.svg` | Not a current Herdr `--kind`; packaged for forward use |
| `AgentHermes.svg` | (prior package) | Inbox also had `nousresearch.svg`; existing Hermes mark retained |
| `AgentGemini.svg` / `AgentOpenCode.svg` / `AgentCopilot.svg` | (prior package) | Already present before this inbox drop |

All of the above product marks are trademarked by their respective owners unless
otherwise noted. They are used solely for in-product identification. No
ownership or endorsement is claimed. Distribution approval should include a
trademark/license review.

`AgentGeneric.svg` is an original simple person silhouette authored for Bessie
in this repository. It is covered by Bessie's repository license and is the
fallback for unknown agent IDs. Shell and non-agent processes do not use it.

Existing Bessie cow/logo/cowprint assets retain their existing project
provenance. No cold-open video is included here; that belongs to plan unit U8.

## Catppuccin terminal palettes

Bessie includes adapted terminal palette values for Catppuccin Latte, Frappé,
Macchiato, and Mocha from the official Catppuccin Ghostty port, pinned at commit
`5a58926563ddacbde4a12b4a347464c2c6945393`:

https://github.com/catppuccin/ghostty/tree/5a58926563ddacbde4a12b4a347464c2c6945393

Bessie authors its own native application mappings around those palette values.
No Ghostty theme package, editor extension, font, icon, or marketplace asset is
included. Catppuccin does not endorse Bessie.

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
