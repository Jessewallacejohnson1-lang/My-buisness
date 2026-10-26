"""The pipeline's one client for the project's REST and Storage APIs, with the service key
from the environment (never from the repo).

A failed call raises DbError with the real status and body; the caller decides whether that
ends the run or is one line in its report. Only a missing key ends the run here.
"""
import json, os, sys
import urllib.request, urllib.error, urllib.parse


class DbError(RuntimeError):
    def __init__(self, method, path, status, body):
        self.method, self.path, self.status, self.body = method, path, status, body
        super().__init__(f"Supabase {method} {path} failed {status}: {body[:400]}")


class Db:
    def __init__(self, missing="needs SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY in env. Never put the key in the repo.",
                 timeout=30):
        self.timeout = timeout
        self.url = os.environ.get("SUPABASE_URL", "").rstrip("/")
        self.key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")
        if not self.url or not self.key:
            sys.exit(missing)

    def _send(self, method, path, data, headers):
        headers = {"apikey": self.key, "Authorization": f"Bearer {self.key}", **headers}
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
