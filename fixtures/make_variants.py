#!/usr/bin/env python3
"""Derive the BriefingPayload edge-case fixtures from briefing_sample.json.

The Phase 3 gate requires every module state to render from a fixture with the
network off: 0 / 1 / 3 featured events, poll voted and unvoted, and a degraded
payload where every optional module is absent. Deriving them from the one base
fixture keeps them from drifting apart as the contract evolves.

Run from the repo root:  python3 fixtures/make_variants.py
"""

import copy
import json
import pathlib

FIXTURES = pathlib.Path(__file__).parent
BASE = FIXTURES / "briefing_sample.json"

EVERGREEN_FALLBACK = {
    "kind": "evergreen",
    "title": "The Lake Wobegon Trail is open",
    "body": "Sixty-two paved miles, and the trailhead is four blocks from here.",
    "deeplink": "activities",
}


def write(name: str, payload: dict) -> None:
    path = FIXTURES / name
    path.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n")
    print(f"wrote {path.relative_to(FIXTURES.parent)}")


def main() -> None:
    base = json.loads(BASE.read_text())

    # 1 featured event -> the full-width hero variant.
    one = copy.deepcopy(base)
    one["featured"] = [base["featured"][0]]
    write("briefing_one_event.json", one)

    # 0 featured events -> the evergreen slot carries the slot instead.
    zero = copy.deepcopy(base)
    zero["featured"] = []
    zero["featured_fallback"] = EVERGREEN_FALLBACK
    write("briefing_zero_events.json", zero)

    # The poll after this user has voted. Their vote is already in the counts.
    voted = copy.deepcopy(base)
    voted["touch"]["my_vote"] = 0
    write("briefing_voted.json", voted)

    # No briefing published for this date. The 6 AM routine did not run, or ran
    # and failed. Distinct from `degraded`: there is no row at all, so there is no
    # town_line and no fallback copy to fall back to. The screen must still render
    # the header, the utility row, and the caught-up footer.
    none = copy.deepcopy(base)
    none["status"] = "none"
    none["published_at"] = None
    none["almanac"] = None
    none["weather"] = None
    none["featured"] = []
    none["featured_fallback"] = None
    none["touch"] = None
    none["spotlight"] = None
    write("briefing_none.json", none)

    # Partial failure: every optional module absent, briefing still renders.
    # Mirrors the existing HomeModel rule that a feed outage must not take the
    # rest of Today down with it.
    degraded = copy.deepcopy(base)
    degraded["almanac"] = None
    degraded["weather"] = None
    degraded["featured"] = []
    degraded["featured_fallback"] = EVERGREEN_FALLBACK
    degraded["touch"] = None
    degraded["spotlight"] = None
    write("briefing_degraded.json", degraded)


if __name__ == "__main__":
    main()
