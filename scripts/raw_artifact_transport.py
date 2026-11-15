#!/usr/bin/env python3
"""Preserve an original GitHub artifact ZIP as byte parts, never repack it."""
import argparse
import hashlib
import json
import os
import pathlib
import re
import sys
import tempfile
import urllib.error
import urllib.parse
import urllib.request

PART_BYTES = 240 * 1024 * 1024
MAX_PARTS = 4
USER_AGENT = "la-grilla-original-artifact-byte-transport"


class TransportError(Exception):
    pass


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, file_pointer, code, message, headers, new_url):
        return None


def require(condition, message):
    if not condition:
        raise TransportError(message)


def file_hash(path):
    value = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()


def api_request(repository, suffix, token):
    return urllib.request.Request("https://api.github.com/repos/" + repository + suffix,
        headers={"Authorization": "Bearer " + token, "Accept": "application/vnd.github+json",
                 "X-GitHub-Api-Version": "2022-11-28", "User-Agent": USER_AGENT})


def api_json(repository, suffix, token):
    # Metadata endpoints should not redirect. Never forward auth to another host.
    with urllib.request.build_opener(NoRedirect()).open(api_request(repository, suffix, token), timeout=60) as response:
        return json.load(response)


def raw_response(repository, artifact_id, token):
    request = api_request(repository, f"/actions/artifacts/{artifact_id}/zip", token)
    try:
        return urllib.request.build_opener(NoRedirect()).open(request, timeout=60)
    except urllib.error.HTTPError as error:
        if error.code not in (301, 302, 303, 307, 308):
            raise TransportError("GitHub raw archive endpoint returned HTTP " + str(error.code)) from None
        location = error.headers.get("Location", "")
        error.close()
    parsed = urllib.parse.urlsplit(location)
    require(parsed.scheme == "https" and parsed.hostname and not parsed.username and not parsed.password,
            "GitHub did not provide a valid HTTPS storage redirect")
    # New request: NO Authorization/API token follows the signed storage URL.
    # The temporary URL exists only in memory and is never printed or persisted.
    return urllib.request.urlopen(urllib.request.Request(location, headers={"User-Agent": USER_AGENT}), timeout=60)


def split_bytes(original, destination, part_bytes=PART_BYTES):
    parts, offset = [], 0
    with original.open("rb") as source:
        while offset < original.stat().st_size:
            index = len(parts)
            require(index < MAX_PARTS, "Raw ZIP exceeds this reviewed four-part transport limit")
            folder = destination / f"part-{index:03d}"
            folder.mkdir()
            filename = f"original-artifact.part-{index:03d}.bin"
            path = folder / filename
            digest, count = hashlib.sha256(), 0
            with path.open("xb") as output:
                while count < part_bytes:
                    block = source.read(min(1024 * 1024, part_bytes - count))
                    if not block:
                        break
                    output.write(block)
                    digest.update(block)
                    count += len(block)
            parts.append({"index": index, "filename": filename, "offset": offset,
                          "bytes": count, "sha256": digest.hexdigest()})
            offset += count
    return parts


def download(args):
    require(re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", args.repository), "Invalid owner/repository")
    require(re.fullmatch(r"[a-f0-9]{40}", args.source_sha), "Require the actual full source SHA")
    token = os.environ.get("GH_TOKEN")
    require(bool(token), "Ephemeral GitHub Actions GH_TOKEN is missing")
    artifact = api_json(args.repository, f"/actions/artifacts/{args.artifact_id}", token)
    run = api_json(args.repository, f"/actions/runs/{args.source_run}", token)
    require(artifact.get("id") == args.artifact_id and artifact.get("name") == "ios-verification" and artifact.get("expired") is False,
            "Original artifact ID/name/expiry does not match")
    origin = artifact.get("workflow_run", {})
    require(origin.get("id") == args.source_run and origin.get("head_sha") == args.source_sha,
            "Original artifact source/run mismatch")
    require(run.get("id") == args.source_run and run.get("head_sha") == args.source_sha,
            "Actual source-run API record does not match")
    digest, size = artifact.get("digest", ""), artifact.get("size_in_bytes")
    require(re.fullmatch(r"sha256:[a-f0-9]{64}", digest), "Original API artifact digest is missing")
    require(isinstance(size, int) and 0 < size <= PART_BYTES * MAX_PARTS,
            "Raw archive is empty or exceeds the reviewed960MiB transport bound")
    args.output.mkdir(parents=True, exist_ok=False)
    original = args.output / "original-raw.zip"
    count, value = 0, hashlib.sha256()
    with raw_response(args.repository, args.artifact_id, token) as response, original.open("xb") as output:
        for block in iter(lambda: response.read(1024 * 1024), b""):
            count += len(block)
            require(count <= size, "Raw download exceeded original API byte size")
            output.write(block)
            value.update(block)
    require(count == size and "sha256:" + value.hexdigest() == digest,
            "Original raw ZIP does not match its API digest/size")
    parts = split_bytes(original, args.output)
    metadata = {key: artifact[key] for key in ("id", "name", "size_in_bytes", "digest", "workflow_run")}
    manifest = {"schema": 1, "repository": args.repository, "original_artifact": metadata,
                "original_run": {key: run.get(key) for key in ("id", "head_sha", "head_branch", "status", "conclusion", "run_attempt")},
                "transport_run_id": os.environ.get("GITHUB_RUN_ID"),
                "transport_run_attempt": os.environ.get("GITHUB_RUN_ATTEMPT"),
                "transport_source_sha": os.environ.get("GITHUB_SHA"),
                "downloaded_raw_zip_sha256": value.hexdigest(), "downloaded_raw_zip_bytes": count,
                "original_api_digest_and_size_verified": True, "part_bytes": PART_BYTES, "parts": parts,
                "raw_byte_split_not_repack": True, "new_app_capture": False,
                "release_acceptance_established": False, "signed_urls_or_tokens_retained": False}
    encoded = json.dumps(manifest, indent=2) + "\n"
    (args.output / "manifest.json").write_text(encoded)
    for part in parts:
        (args.output / f"part-{part['index']:03d}" / "manifest.json").write_text(encoded)
    original.unlink()
    if os.environ.get("GITHUB_OUTPUT"):
        with open(os.environ["GITHUB_OUTPUT"], "a") as output:
            for index in range(MAX_PARTS):
                output.write(f"has_part_{index:03d}={'true' if index < len(parts) else 'false'}\n")
    print(json.dumps({"original_artifact_id": args.artifact_id, "original_source_run": args.source_run,
                      "raw_zip_bytes": count, "original_zip_sha256": value.hexdigest(), "parts": len(parts),
                      "original_run_conclusion": run.get("conclusion"), "new_capture": False}))


def join(args):
    manifest_bytes = args.manifest.read_bytes()
    manifest = json.loads(manifest_bytes)
    artifact = manifest["original_artifact"]
    independent = json.loads(args.api_record.read_text())
    if "artifacts" in independent:
        matches = [a for a in independent["artifacts"] if a.get("id") == artifact["id"]]
        require(len(matches) == 1, "Independent API list does not identify exactly one original artifact")
        independent = matches[0]
    for key in ("id", "name", "size_in_bytes", "digest"):
        require(independent.get(key) == artifact.get(key), "Independent ORIGINAL API metadata differs: " + key)
    for key in ("id", "head_sha"):
        require(independent.get("workflow_run", {}).get(key) == artifact["workflow_run"].get(key),
                "Independent original source/run differs")
    require(manifest.get("raw_byte_split_not_repack") is True and manifest.get("original_api_digest_and_size_verified") is True,
            "Manifest does not describe a verified raw-byte transfer")
    require(not args.output.exists(), "Output already exists; original/historical archives are never overwritten")
    require(1 <= len(manifest["parts"]) <= MAX_PARTS, "Invalid part count")
    candidates = list(args.parts.rglob("original-artifact.part-*.bin"))
    require(len(candidates) == len(manifest["parts"]), "Missing/extra/duplicate raw part files")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(prefix=".assembling-raw-", dir=args.output.parent, delete=False) as output:
            temporary = pathlib.Path(output.name)
            combined, total = hashlib.sha256(), 0
            for index, part in enumerate(manifest["parts"]):
                require(part["index"] == index and part["offset"] == total and 0 < part["bytes"] <= PART_BYTES,
                        "Raw parts are not consecutive/bounded")
                require(part["filename"] == f"original-artifact.part-{index:03d}.bin", "Invalid raw part basename")
                matches = [p for p in candidates if p.name == part["filename"]]
                require(len(matches) == 1, "Raw part is missing or ambiguous")
                path = matches[0]
                require((path.parent / "manifest.json").read_bytes() == manifest_bytes,
                        "Chunk manifest differs from the chosen original provenance")
                require(path.stat().st_size == part["bytes"] and file_hash(path) == part["sha256"], "Raw part digest/size mismatch")
                with path.open("rb") as source:
                    for block in iter(lambda: source.read(1024 * 1024), b""):
                        output.write(block)
                        combined.update(block)
                        total += len(block)
            require(total == artifact["size_in_bytes"] and "sha256:" + combined.hexdigest() == artifact["digest"],
                    "Reconstructed ORIGINAL ZIP digest/size mismatch")
        require(total == manifest["downloaded_raw_zip_bytes"] and combined.hexdigest() == manifest["downloaded_raw_zip_sha256"],
                "Original download receipt disagrees with reconstruction")
        # Same-directory hard-link creation is atomic and refuses an existing
        # destination, including a file created after the first existence check.
        os.link(temporary, args.output)
        temporary.unlink()
        print(json.dumps({"original_artifact_id": artifact["id"], "source_sha": artifact["workflow_run"]["head_sha"],
                          "original_source_run": artifact["workflow_run"]["id"], "bytes": total,
                          "sha256": combined.hexdigest(), "original_api_digest_matches": True,
                          "original_run_conclusion": manifest["original_run"].get("conclusion"),
                          "new_capture": False, "release_acceptance_established": False}))
    finally:
        if temporary is not None and temporary.exists():
            temporary.unlink()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    get = sub.add_parser("download")
    get.add_argument("--repository", required=True)
    get.add_argument("--artifact-id", type=int, required=True)
    get.add_argument("--source-run", type=int, required=True)
    get.add_argument("--source-sha", required=True)
    get.add_argument("--output", type=pathlib.Path, required=True)
    assemble = sub.add_parser("join")
    assemble.add_argument("--manifest", type=pathlib.Path, required=True)
    assemble.add_argument("--api-record", type=pathlib.Path, required=True)
    assemble.add_argument("--parts", type=pathlib.Path, required=True)
    assemble.add_argument("--output", type=pathlib.Path, required=True)
    args = parser.parse_args()
    try:
        download(args) if args.command == "download" else join(args)
    except TransportError as error:
        print("Raw artifact transport refused: " + str(error), file=sys.stderr)
        return 1
    except Exception as error:
        # HTTP/socket exceptions can retain signed URLs; never print details.
        print("Raw artifact transport failed (" + type(error).__name__ + "); no token/URL details logged.", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
