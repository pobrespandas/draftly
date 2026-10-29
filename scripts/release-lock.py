#!/usr/bin/env python3
"""Coordinate release writers with a generation-checked object. Never publish."""
import json
import os
from pathlib import Path
import re
import tempfile
import uuid
import urllib.request


class Busy(ValueError):
    pass


def write_journal(path, value, *, new=False):
    path = Path(path)
    data = json.dumps(value, sort_keys=True, indent=2) + "\n"
    if new:
        with path.open("x") as output:
            output.write(data)
            output.flush()
            os.fsync(output.fileno())
        sync_directory(path.parent)
        return
    if path.is_symlink():
        raise ValueError("The lock journal must not be a symlink.")
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", dir=path.parent, prefix=".release-lock-", delete=False) as output:
            temporary = output.name
            output.write(data)
            output.flush()
            os.fsync(output.fileno())
        os.replace(temporary, path)
        temporary = None
        sync_directory(path.parent)
    finally:
        if temporary is not None:
            Path(temporary).unlink(missing_ok=True)


def sync_directory(path):
    descriptor = os.open(path, os.O_RDONLY)
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def validate_scope(value):
    if (not isinstance(value, dict) or set(value) != {"bucket", "object"}
            or not isinstance(value["bucket"], str)
            or not re.fullmatch(r"[a-z0-9][a-z0-9._-]{1,220}[a-z0-9]", value["bucket"])
            or value["object"] != "draftly/site-writer.lock"):
        raise ValueError("The lock scope is invalid.")
    return value


def read_journal(path):
    path = Path(path)
    if path.is_symlink() or not path.is_file() or path.stat().st_size > 65536:
        raise ValueError("The lock journal is invalid.")
    try:
        value = json.loads(path.read_text())
    except (ValueError, UnicodeError) as error:
        raise ValueError("The lock journal is invalid.") from error
    if (not isinstance(value, dict) or value.get("state") not in ("creating", "held", "releasing", "released", "busy", "not_acquired")
            or not isinstance(value.get("owner"), str) or not re.fullmatch(r"[a-f0-9]{32}", value["owner"])):
        raise ValueError("The lock journal is invalid.")
    validate_scope(value.get("scope"))
    if value["state"] in ("held", "releasing", "released"):
        generation = value.get("generation")
        if not isinstance(generation, str) or not re.fullmatch(r"[1-9][0-9]*", generation):
            raise ValueError("The lock generation is invalid.")
    return value


def validate_object(value):
    if (not isinstance(value, dict) or not isinstance(value.get("owner"), str)
            or not re.fullmatch(r"[a-f0-9]{32}", value["owner"])
            or not isinstance(value.get("generation"), str)
            or not re.fullmatch(r"[1-9][0-9]*", value["generation"])):
        raise ValueError("The remote lock is invalid.")
    return {"owner": value["owner"], "generation": value["generation"]}


def acquire(store, journal):
    state = {"state": "creating", "owner": uuid.uuid4().hex, "scope": validate_scope(store.scope())}
    write_journal(journal, state, new=True)
    try:
        value = validate_object(store.create(state["owner"]))
    except Busy:
        state["state"] = "busy"
        write_journal(journal, state)
        raise
    if value["owner"] != state["owner"]:
        raise ValueError("The created lock does not belong to this operation.")
    state.update(value, state="held")
    write_journal(journal, state)
    return value


def recover(store, journal):
    state = read_journal(journal)
    if state["scope"] != validate_scope(store.scope()):
        raise ValueError("The lock scope does not match the journal.")
    if state["state"] not in ("creating", "releasing"):
        raise ValueError("This lock journal has no uncertain operation.")
    current = store.read()
    if current is not None:
        current = validate_object(current)
    if state["state"] == "creating":
        if current is None:
            state["state"] = "not_acquired"
            write_journal(journal, state)
            return None
        if current["owner"] != state["owner"]:
            raise ValueError("The remote lock does not belong to this operation.")
        state.update(current, state="held")
        write_journal(journal, state)
        return current
    if current is not None and current["generation"] == state["generation"]:
        if current["owner"] != state["owner"]:
            raise ValueError("The remote lock does not belong to this operation.")
        state["state"] = "held"
        write_journal(journal, state)
        return current
    state["state"] = "released"
    write_journal(journal, state)
    return None


def check(store, journal):
    state = read_journal(journal)
    if state["scope"] != validate_scope(store.scope()):
        raise ValueError("The lock scope does not match the journal.")
    if state["state"] != "held":
        raise ValueError("The journal does not hold a lock.")
    current = store.read()
    if current is None or validate_object(current) != {"owner": state["owner"], "generation": state["generation"]}:
        raise ValueError("The remote lock does not belong to this operation.")
    return validate_object(current)


def release(store, journal):
    current = check(store, journal)
    state = read_journal(journal)
    if (state["state"] != "held" or state["scope"] != validate_scope(store.scope())
            or current != {"owner": state["owner"], "generation": state["generation"]}):
        raise ValueError("The lock journal changed during verification.")
    state["state"] = "releasing"
    write_journal(journal, state)
    store.delete(state["generation"])
    state["state"] = "released"
    write_journal(journal, state)


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, fp, code, message, headers, new_url):
        return None


class StorageLock:
    OBJECT = "draftly/site-writer.lock"

    def __init__(self, bucket, token):
        if (not isinstance(bucket, str) or not re.fullmatch(r"[a-z0-9][a-z0-9._-]{1,220}[a-z0-9]", bucket)
                or not isinstance(token, str) or not re.fullmatch(r"[A-Za-z0-9._~+/=-]{1,8192}", token)):
            raise ValueError("A valid lock bucket and access token are required.")
        self.bucket = bucket
        self._token = token

    def scope(self):
        return {"bucket": self.bucket, "object": self.OBJECT}

    def request(self, method, path, body=None):
        import urllib.error
        import urllib.request

        url = "https://storage.googleapis.com" + path
        request = urllib.request.Request(url, data=body, method=method,
            headers={"Authorization": "Bearer " + self._token, "Content-Type": "application/json"})
        try:
            with urllib.request.build_opener(NoRedirect()).open(request, timeout=30) as response:
                payload = response.read(65537)
        except urllib.error.HTTPError as error:
            if error.code == 412 and method == "POST":
                raise Busy("Another writer holds the lock.") from error
            if error.code == 404 and method == "GET":
                return None
            raise ValueError("Cloud Storage lock request failed (HTTP " + str(error.code) + ").") from error
        except urllib.error.URLError as error:
            raise ValueError("Cloud Storage lock request failed.") from error
        if len(payload) > 65536:
            raise ValueError("The lock response is too large.")
        try:
            value = json.loads(payload or b"{}")
        except (ValueError, UnicodeError) as error:
            raise ValueError("The lock response is invalid.") from error
        if not isinstance(value, dict):
            raise ValueError("The lock response is invalid.")
        return value

    def metadata(self, value):
        if (not isinstance(value, dict) or value.get("bucket") != self.bucket or value.get("name") != self.OBJECT
                or not isinstance(value.get("generation"), str)
                or not re.fullmatch(r"[1-9][0-9]*", value["generation"])):
            raise ValueError("Cloud Storage returned invalid lock metadata.")
        return value["generation"]

    def create(self, owner):
        from urllib.parse import quote, urlencode
        query = urlencode({"uploadType": "media", "name": self.OBJECT, "ifGenerationMatch": "0"})
        body = json.dumps({"owner": owner}, separators=(",", ":")).encode()
        response = self.request("POST", "/upload/storage/v1/b/" + quote(self.bucket, safe="") + "/o?" + query, body)
        return {"owner": owner, "generation": self.metadata(response)}

    def read(self):
        from urllib.parse import quote, urlencode
        path = "/storage/v1/b/" + quote(self.bucket, safe="") + "/o/" + quote(self.OBJECT, safe="")
        metadata = self.request("GET", path)
        if metadata is None:
            return None
        generation = self.metadata(metadata)
        data = self.request("GET", path + "?" + urlencode({"alt": "media", "generation": generation}))
        if not isinstance(data, dict) or set(data) != {"owner"}:
            raise ValueError("The remote lock content is invalid.")
        return validate_object({"owner": data["owner"], "generation": generation})

    def delete(self, generation):
        from urllib.parse import quote, urlencode
        path = "/storage/v1/b/" + quote(self.bucket, safe="") + "/o/" + quote(self.OBJECT, safe="")
        self.request("DELETE", path + "?" + urlencode({"ifGenerationMatch": generation}))


def main():
    import argparse

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("operation", choices=("acquire", "recover", "check", "release"))
    parser.add_argument("--bucket", required=True)
    parser.add_argument("--journal", required=True)
    args = parser.parse_args()
    try:
        store = StorageLock(args.bucket, os.environ.get("DRAFTLY_RELEASE_LOCK_TOKEN"))
        result = {"acquire": acquire, "recover": recover, "check": check, "release": release}[args.operation](store, args.journal)
        print(json.dumps({"result": result, "state": read_journal(args.journal)["state"]}))
    except (ValueError, OSError) as error:
        raise SystemExit("Release lock failed: " + str(error))


if __name__ == "__main__":
    main()
