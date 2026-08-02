#!/usr/bin/env python3
"""Durable static guards for the generated CLI/MCP projections."""

from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parent.parent


def fail(message: str) -> None:
    print(f"intent parity check failed: {message}", file=sys.stderr)
    raise SystemExit(1)


registry = (ROOT / "Sources/BessieCore/AgentIntentRegistry.swift").read_text()
cli = (ROOT / "Sources/BessieCLI/BessieCLI.swift").read_text()
mcp = (ROOT / "Sources/BessieMCP/BessieMCP.swift").read_text()
package = (ROOT / "Package.swift").read_text()
skill = (ROOT / ".agents/skills/operating-bessie/SKILL.md").read_text()

try:
    catalog_body = registry.split("public static let catalog", 1)[1].split(
        "public static func definition", 1
    )[0]
except IndexError:
    fail("could not locate the registry catalog")
names = re.findall(r'intent\(\s*"([a-z0-9_.-]+)"', catalog_body)
if not names or len(names) != len(set(names)):
    fail("registry intent names must exist and be unique")
if any(not re.fullmatch(r"[a-z][a-z0-9_.-]{0,63}", name) for name in names):
    fail("registry intent names must be MCP-safe")

destructive_blocks = re.findall(r'intent\(\s*"[^"]+".*?risk:\s*\.destructive,(.*?)(?=\n\s*\),)', catalog_body, re.S)
if not destructive_blocks or any("confirmation:" not in block for block in destructive_blocks):
    fail("every destructive registry entry must declare confirmation metadata")

for source_name, source in (("CLI", cli), ("MCP", mcp)):
    domain_names = [name for name in names if name not in {"intents.list", "app.status"} and f'"{name}"' in source]
    if domain_names:
        fail(f"{source_name} contains hard-coded domain intents: {', '.join(domain_names)}")
if "BessieIntentRegistry.catalog" not in cli or "effectiveCatalog().intents.map" not in mcp:
    fail("CLI and MCP must remain generic registry projections")

for product in ("BessieCore", "bessie", "bessie-mcp"):
    if f'name: "{product}"' not in package:
        fail(f"missing Package product {product}")
for target in ("BessieCore", "BessieCLI", "BessieMCP", "BessieCLITests", "BessieMCPTests"):
    if f'name: "{target}"' not in package:
        fail(f"missing Package target {target}")

anchors = {
    "Tests/BessieCLITests/BessieCLIArgumentsTests.swift": "liveIntentDiscoveryUsesExactEffectiveCatalog",
    "Tests/BessieMCPTests/BessieMCPTests.swift": "toolsListNamesEqualCustomEffectiveCatalog",
}
for path, anchor in anchors.items():
    if anchor not in (ROOT / path).read_text():
        fail(f"missing Swift parity test anchor {anchor}")

if "bessie intents" not in skill or "bessie server" not in skill or "There is no `bessie server`" not in skill:
    fail("skill must teach discovery and explicitly reject bessie server")

print(f"Intent parity checks passed for {len(names)} registry intents.")
