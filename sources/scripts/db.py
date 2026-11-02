"""The pipeline's one client for the project's REST and Storage APIs, with a key from the
environment (never from the repo).

A failed call raises DbError with the real status and body; the caller decides whether that
ends the run or is one line in its report. Only a missing key ends the run here.
"""
import json, os, sys
import urllib.request, urllib.error, urllib.parse

KEYS = ("SUPABASE_PUBLISHABLE_KEY (in the cloud, with the Watch key as the network secret) "
        "or SUPABASE_SERVICE_ROLE_KEY (on a Mac). Never put a key in the repo.")


def key_headers(env=os.environ):
    """The key headers, or None when no key is set. A Mac sends the service key. A cloud routine
    sends only the public key, and the environment's network secret adds the Watch key on the way
    out, so the run never holds a key that can delete or reach accounts (BP app loopholes 12)."""
    service, public = env.get("SUPABASE_SERVICE_ROLE_KEY"), env.get("SUPABASE_PUBLISHABLE_KEY")
    if service:
        return {"apikey": service, "Authorization": f"Bearer {service}"}
    return {"apikey": public} if public else None


class DbError(RuntimeError):
    def __init__(self, method, path, status, body):
        self.method, self.path, self.status, self.body = method, path, status, body
        super().__init__(f"Supabase {method} {path} failed {status}: {body[:400]}")


class Db:
    def __init__(self, missing=f"needs SUPABASE_URL and a key in env: {KEYS}", timeout=30, env=os.environ):
        """`env` is where the URL and key come from: the environment, or the skill's key held in memory."""
        self.timeout = timeout
        self.url = env.get("SUPABASE_URL", "").rstrip("/")
        self.keys = key_headers(env)
        if not self.url or not self.keys:
            sys.exit(missing)

    def _send(self, method, path, data, headers):
        headers = {**self.keys, **headers}
        req = urllib.request.Request(self.url + path, data=data, headers=headers, method=method)
        try:
            with urllib.request.urlopen(req, timeout=self.timeout) as r:
                return r.read().decode()
        except urllib.error.HTTPError as e:
            raise DbError(method, path, e.code, e.read().decode(errors="replace")) from None
        except (urllib.error.URLError, ConnectionError, TimeoutError) as e:  # no answer: no status
            raise DbError(method, path, None, str(getattr(e, "reason", e))) from None

    def rest(self, method, path, body=None, prefer=None):
        """PostgREST: `path` is what follows /rest/v1/, e.g. "sources?select=url"."""
        headers = {"Content-Type": "application/json", **({"Prefer": prefer} if prefer else {})}
        data = json.dumps(body, default=str).encode() if body is not None else None
        txt = self._send(method, f"/rest/v1/{path}", data, headers)
        return json.loads(txt) if txt.strip() else None

    def storage_put(self, path, data, content_type="image/webp"):
        """Upload `data` to Storage at `path` ("<bucket>/<name>"). Never overwrites (a name
        already taken raises DbError 400 or 409), so a file is cached for a year."""
        self._send("POST", f"/storage/v1/object/{urllib.parse.quote(path)}", data,
                   {"Content-Type": content_type, "x-upsert": "false", "cache-control": "max-age=31536000"})
