#!/usr/bin/env python3
"""
composio.py: the one way the town pipeline calls the Composio CLI, so every caller gets its
quirks handled the same way (BP app codebase-health 06):

- stdin is closed: the CLI waits on an open one until the timeout;
- a banner may come before the JSON, so the answer is read from its first "{";
- a large answer comes back as a pointer to a file (`storedInFile`, at the top or inside
  `data`), which is read in its place;
- `"successful": false` raises, so a failure is never read, or cached, as an empty answer
  (maps.py's "snow removal" went two weeks without places that way, 2026-10).

  execute(slug, args)            a tool's `data`, or ComposioError
  proxy(url, toolkit, method)    an app's own API through Composio's auth; its JSON answer, {} for none

  python3 sources/scripts/composio.py --selftest
"""

import json, subprocess, sys
from pathlib import Path


class ComposioError(RuntimeError):
    pass


def _cli(cmd, timeout):
    """The live CLI. The self-test swaps this for canned answers."""
    try:
        r = subprocess.run(["composio", *cmd], stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=timeout)
    except (OSError, subprocess.TimeoutExpired) as ex:
        raise ComposioError(f"composio {cmd[0]}: {ex}") from None
    return r.returncode, r.stdout, r.stderr


def _answer(what, code, out, err):
    """The CLI's JSON answer, past any banner, with a file pointer followed."""
    if not out.strip() and not code:
        return {}
    for start in (i for i, c in enumerate(out) if c in "{["):
        try:
            d = json.JSONDecoder().raw_decode(out, start)[0]
            break
        except ValueError:
            continue  # a banner's own bracket, "[info] ..."
    else:
        raise ComposioError(f"{what}: no answer (exit {code}): {(err or out).strip()[-200:]}")
    if not isinstance(d, dict):
        return d
    for holder in (d, d.get("data")):
        if isinstance(holder, dict) and holder.get("storedInFile"):
            stored = json.loads(Path(holder["outputFilePath"]).read_text())
            d = stored if holder is d else {**d, "data": stored.get("data", stored)}
            break
    return d


def execute(slug, args, timeout=180):
    """One tool, e.g. execute("FIRECRAWL_SCRAPE", {"url": ...}): its `data`."""
    d = _answer(slug, *_cli(["execute", slug, "-d", json.dumps(args)], timeout))
    if not isinstance(d, dict) or not d or d.get("successful") is False:
        d = d if isinstance(d, dict) else {}
        data = d.get("data") if isinstance(d.get("data"), dict) else {}
        raise ComposioError(f"{slug}: {str(data.get('message') or d.get('error') or 'no answer')[:300]}")
    return d.get("data", d)


def proxy(url, toolkit, method, body=None, timeout=60):
    """An app's REST API through Composio's auth. The app's own errors are its answer to read."""
    cmd = ["proxy", url, "--toolkit", toolkit, "-X", method]
    if body is not None:
        cmd += ["-H", "Content-Type: application/json", "-d", json.dumps(body)]
    return _answer(f"proxy {url}", *_cli(cmd, timeout))


def selftest():
    import tempfile
    global _cli
    live, checks = _cli, []

    def answers(stdout, code=0, stderr=""):
        global _cli
        _cli = lambda cmd, timeout: (code, stdout, stderr)

    def raised(fn, *a):
        try:
            fn(*a)
        except ComposioError as ex:
            return str(ex)
        return ""
    try:
        with tempfile.TemporaryDirectory() as tmp:
            big = Path(tmp) / "answer.json"
            big.write_text(json.dumps({"successful": True, "data": {"results": {"local_results": [1, 2]}}}))
            answers(json.dumps({"storedInFile": True, "outputFilePath": str(big)}))
            checks.append((execute("X", {}) == {"results": {"local_results": [1, 2]}}, "a file pointer is read in its place"))
            big.write_text(json.dumps({"data": {"result": [{"n": 1}]}}))
            answers(json.dumps({"successful": True, "data": {"storedInFile": True, "outputFilePath": str(big)}}))
            checks.append((execute("X", {}) == {"result": [{"n": 1}]}, "so is one inside data"))
        answers('{"successful": false, "error": "getaddrinfo ENOTFOUND backend.composio.dev"}')
        checks.append(("ENOTFOUND" in raised(execute, "X", {}), "an error answer raises, never reads as empty"))
        answers('{"successful": false, "data": {"message": "permission denied"}, "error": null}')
        checks.append(("permission denied" in raised(execute, "X", {}), "the error names the tool's own message"))
        answers('[info] Update available: 0.9.1\n{"successful": true, "data": {"markdown": "# Hi"}}\n')
        checks.append((execute("X", {}) == {"markdown": "# Hi"}, "a banner before the JSON is skipped"))
        answers('[info] Update available\n[{"id": 1}, {"id": 2}]')
        checks.append((proxy("https://api/x", "apify", "GET") == [{"id": 1}, {"id": 2}], "a proxied list is read whole"))
        answers("", 1, "Error: network unreachable")
        checks.append(("network unreachable" in raised(execute, "X", {}), "no JSON at all raises with the CLI's words"))
        answers("")
        checks.append((proxy("https://api/x", "apify", "GET") == {} and raised(execute, "X", {}),
                       "an empty proxy answer is none; an empty tool answer raises"))
        answers('{"error": {"type": "record-not-found"}}')
        checks.append((proxy("https://api/x", "apify", "GET") == {"error": {"type": "record-not-found"}},
                       "an app's own error is the proxy's answer, for its caller to read"))
    finally:
        _cli = live
    failed = [why for ok, why in checks if not ok]
    for why in failed:
        print(f"FAIL {why}")
    print(f"{len(checks) - len(failed)} passed, {len(failed)} failed")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    if sys.argv[1:] == ["--selftest"]:
        selftest()
    else:
        sys.exit(__doc__)
