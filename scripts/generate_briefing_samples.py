#!/usr/bin/env python3
"""Generate BriefingSample.swift from the fixture files.

The DEBUG previews render from the SAME JSON the contract tests assert against,
so a preview and a test can never disagree about what a payload looks like.
Edit fixtures/, re-run this, never hand-edit the generated Swift.

Run from the repo root:  python3 scripts/generate_briefing_samples.py
"""

import json
import pathlib

NAMES = [
    "briefing_sample", "briefing_one_event", "briefing_zero_events",
    "briefing_voted", "briefing_none", "briefing_degraded",
]

TARGET = pathlib.Path("BlockParty/Features/Home/Briefing/BriefingSample.swift")

HEADER = '''//
//  BriefingSample.swift
//  Block Party — DEBUG-only canned briefings for headless verification.
//
//  GENERATED from fixtures/*.json by scripts/generate_briefing_samples.py.
//  Do not hand-edit: edit the fixture and regenerate, so the previews and the
//  contract tests can never disagree about what a payload looks like.
//
//  These decode through the real `SupabaseCoding.decoder`, so a preview exercises
//  the same decode path the network does.
//

#if DEBUG
import Foundation

// MainActor-isolated: it reads the shared `SupabaseCoding.decoder`, which is.
enum BriefingSample {
    /// Decodes a named sample, or nil if the JSON no longer matches the contract.
    static func payload(_ name: String) -> BriefingPayload? {
        guard let json = raw[name] else { return nil }
        return try? SupabaseCoding.decoder.decode(BriefingPayload.self, from: Data(json.utf8))
    }

    static let names = Array(raw.keys).sorted()

    private static let raw: [String: String] = ['''


def main() -> None:
    lines = [HEADER]
    for name in NAMES:
        payload = json.load(open(f"fixtures/{name}.json"))
        compact = json.dumps(payload, separators=(",", ":"))
        key = name.replace("briefing_", "")
        lines.append(f'        "{key}": #"""\n{compact}\n"""#,')
    lines.append("    ]\n}\n#endif")
    TARGET.write_text("\n".join(lines) + "\n")
    print(f"generated {TARGET} with {len(NAMES)} payloads")


if __name__ == "__main__":
    main()
