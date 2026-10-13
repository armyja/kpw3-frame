"""Mirror the current git commit to GitHub through the REST API.

Why: on some networks `github.com:443` is unreachable (git push just times out)
while `api.github.com` works fine. This script rebuilds the commit from the git
data API instead, so you can still publish.

It creates a single root commit from the current HEAD tree, with the message of
the current HEAD commit, and force-updates the branch. Commit history is
therefore flattened - fine for a snapshot, not for collaborative work.

Usage:
    python tools/push_via_api.py <owner>/<repo> [work-tree] [branch] [message-file]

Requires the GitHub CLI (`gh`) to be authenticated - the token it stores is
reused. Nothing here needs the `git` remote or github.com.
"""

import base64
import json
import subprocess
import sys
import urllib.error
import urllib.request

if len(sys.argv) < 2:
    sys.exit(__doc__)

repo = sys.argv[1]
work = sys.argv[2] if len(sys.argv) > 2 else "."
branch = sys.argv[3] if len(sys.argv) > 3 else "main"
message_file = sys.argv[4] if len(sys.argv) > 4 else None

API = "https://api.github.com"
token = subprocess.run(["gh", "auth", "token"], capture_output=True, text=True, check=True).stdout.strip()


def call(method, path, payload=None):
    body = json.dumps(payload).encode() if payload is not None else None
    req = urllib.request.Request(
        API + path,
        data=body,
        method=method,
        headers={
            "Authorization": "Bearer " + token,
            "Accept": "application/vnd.github+json",
            "User-Agent": "push-via-api",
            "Content-Type": "application/json",
        },
    )
    with urllib.request.urlopen(req, timeout=90) as resp:
        raw = resp.read().decode()
    return json.loads(raw) if raw else {}


def git(*args, binary=False):
    kwargs = {} if binary else {"text": True}
    return subprocess.run(["git", "-C", work, *args], capture_output=True,
                          check=True, **kwargs).stdout


def ref_exists():
    try:
        call("GET", f"/repos/{repo}/git/ref/heads/{branch}")
        return True
    except urllib.error.HTTPError as exc:
        # 404 = no such ref, 409 = "Git Repository is empty"
        if exc.code in (404, 409):
            return False
        raise


# The git data API refuses to work on a repository with no commits at all, so
# seed one; its history is thrown away a moment later.
if not ref_exists():
    call("PUT", f"/repos/{repo}/contents/.gitattributes",
         {"message": "seed", "content": base64.b64encode(b"# seed\n").decode()})
    print("  seeded an initial commit so the git data API will talk to us")

entries = []
for line in git("ls-tree", "-r", "HEAD").splitlines():
    meta, path = line.split("\t", 1)
    mode, _kind, sha = meta.split()
    blob = git("cat-file", "-p", sha, binary=True)
    created = call("POST", f"/repos/{repo}/git/blobs",
                   {"content": base64.b64encode(blob).decode(), "encoding": "base64"})
    entries.append({"path": path, "mode": mode, "type": "blob", "sha": created["sha"]})
    print(f"  blob {path}")

tree = call("POST", f"/repos/{repo}/git/trees", {"tree": entries})
message = (
    open(message_file, encoding="utf-8").read()
    if message_file
    else git("log", "-1", "--pretty=%B")
)
commit = call("POST", f"/repos/{repo}/git/commits", {"message": message, "tree": tree["sha"]})
call("PATCH", f"/repos/{repo}/git/refs/heads/{branch}", {"sha": commit["sha"], "force": True})
try:
    call("PATCH", f"/repos/{repo}", {"default_branch": branch})
except urllib.error.HTTPError:
    pass

print(f"pushed {len(entries)} files to {repo}@{branch} as {commit['sha'][:12]}")
