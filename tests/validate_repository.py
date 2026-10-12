#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Validate evidence references, release facts, license markers, and publication hygiene."""

from __future__ import annotations

import hashlib
import ipaddress
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "results/evidence-manifest.json"
REPORT = ROOT / "FINAL_SECRET_SCAN.txt"

SECRET_PATTERNS = [
    ("github_token", re.compile(rb"\b(?:ghp|github_pat)_[A-Za-z0-9_]{20,}\b")),
    ("huggingface_token", re.compile(rb"\bhf_[A-Za-z0-9]{20,}\b")),
    ("openai_key", re.compile(rb"\bsk-[A-Za-z0-9_-]{20,}\b")),
    ("google_key", re.compile(rb"\bAIza[0-9A-Za-z_-]{30,}\b")),
    ("aws_key", re.compile(rb"\bAKIA[0-9A-Z]{16}\b")),
    ("bearer_credential", re.compile(rb"(?i)\bBearer\s+[A-Za-z0-9._~+/=-]{20,}")),
    ("private_key", re.compile(rb"-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----")),
    ("credential_assignment", re.compile(rb"(?i)\b(?:password|passwd|api[_-]?key|access[_-]?token)\s*[:=]\s*[^\s<>{}\"']{8,}")),
]
PRIVATE_PATH_PATTERNS = [
    ("user_home_path", re.compile(rb"/" + re.escape(b"Users") + rb"/[^/\s:]+")),
    ("linux_home_path", re.compile(rb"/" + re.escape(b"home") + rb"/[^/\s:]+")),
    ("private_service_path", re.compile(rb"/" + re.escape(b"data") + rb"/ai(?:/|\b)")),
    ("private_service_path", re.compile(rb"/" + re.escape(b"opt") + rb"/rccl(?:/|\b)")),
    (
        "private_hostname",
        re.compile(rb"\b[A-Za-z0-9][A-Za-z0-9.-]*\.(?:local|internal|corp|lan)\b", re.IGNORECASE),
    ),
]
IPV4_PATTERN = re.compile(rb"(?<![0-9.])(?:[0-9]{1,3}\.){3}[0-9]{1,3}(?![0-9.])")


def repository_files() -> list[Path]:
    output = subprocess.check_output(
        ["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z"],
        cwd=ROOT,
    )
    paths: list[Path] = []
    for item in output.split(b"\0"):
        if not item:
            continue
        path = ROOT / item.decode("utf-8", "surrogateescape")
        if path.is_file():
            paths.append(path)
    return sorted(set(paths))


def scan_publication(paths: list[Path]) -> tuple[int, list[tuple[str, str]]]:
    findings: list[tuple[str, str]] = []
    for path in paths:
        try:
            content = path.read_bytes()
        except OSError:
            findings.append((path.relative_to(ROOT).as_posix(), "unreadable_file"))
            continue
        rel = path.relative_to(ROOT).as_posix()
        for label, pattern in SECRET_PATTERNS + PRIVATE_PATH_PATTERNS:
            if pattern.search(content):
                findings.append((rel, label))
        for match in IPV4_PATTERN.finditer(content):
            candidate = match.group().decode("ascii", "ignore")
            try:
                address = ipaddress.ip_address(candidate)
            except ValueError:
                continue
            if address.is_private or address.is_loopback or address.is_link_local:
                findings.append((rel, "private_ipv4"))
                break
    return len(paths), findings


def validate_manifest() -> None:
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    if manifest.get("schema_version") != 1:
        raise ValueError("unsupported manifest schema")
    if manifest.get("last_reviewed") != "2026-10-12":
        raise ValueError("manifest review date missing")
    artifacts = manifest.get("artifacts")
    if not isinstance(artifacts, list) or len(artifacts) < 7:
        raise ValueError("manifest must reference the seven archived evidence artifacts")
    seen: set[str] = set()
    for item in artifacts:
        required = {
            "path",
            "sha256",
            "source_capture_sha256",
            "captured_at",
            "evidence_level",
            "test_conditions",
            "summary",
            "limitations",
        }
        if not required.issubset(item):
            raise ValueError(f"manifest item lacks required fields: {item.get('path', '<unknown>')}")
        rel = item["path"]
        if rel in seen or Path(rel).is_absolute() or ".." in Path(rel).parts:
            raise ValueError(f"duplicate or unsafe artifact path: {rel}")
        seen.add(rel)
        path = ROOT / rel
        if not path.is_file():
            raise ValueError(f"manifest artifact missing: {rel}")
        actual = hashlib.sha256(path.read_bytes()).hexdigest()
        if actual != item["sha256"]:
            raise ValueError(f"artifact hash mismatch: {rel}")
        if item["evidence_level"] not in {"FACT", "OBSERVED", "INFERENCE"}:
            raise ValueError(f"unsupported evidence level for {rel}")
        source_hash = item["source_capture_sha256"]
        if source_hash is not None:
            if not re.fullmatch(r"[0-9a-f]{64}", source_hash):
                raise ValueError(f"invalid source capture hash for {rel}")
            header = path.read_text(encoding="utf-8", errors="replace").splitlines()[:12]
            if not any(source_hash in line for line in header):
                raise ValueError(f"source capture hash not present in artifact header: {rel}")
        if not item["summary"] or not item["limitations"]:
            raise ValueError(f"artifact needs a summary and limitation: {rel}")
    if "address_mapping_chain" not in manifest:
        raise ValueError("manifest must declare mapping-chain status")
    if manifest["address_mapping_chain"].get("status") != "OPEN":
        raise ValueError("mapping chain must remain explicitly open")


def validate_readmes() -> None:
    required = [
        "v0.2.0",
        "8086:6f00",
        "10.29",
        "9.49",
        "31.28",
        "docs/upstream-status.md",
        "docs/high-address-p2p-investigation.md",
        "results/evidence-manifest.json",
        "DIRECT_P2P_READY = INCONCLUSIVE",
    ]
    for name in ("README.md", "README.zh-CN.md"):
        content = (ROOT / name).read_text(encoding="utf-8")
        missing = [fact for fact in required if fact not in content]
        if missing:
            raise ValueError(f"{name} missing canonical facts or links: {', '.join(missing)}")
        for destination in re.findall(r"\]\(([^)]+)\)", content):
            destination = destination.strip().strip("<>")
            if not destination or destination.startswith("#") or "://" in destination or destination.startswith("mailto:"):
                continue
            local_path = destination.split("#", 1)[0]
            if not local_path:
                continue
            target = (ROOT / local_path).resolve()
            if not target.exists():
                raise ValueError(f"{name} has a broken local link: {destination}")
    status = (ROOT / "docs/upstream-status.md").read_text(encoding="utf-8")
    for milestone in ("Submitted", "Maintainer applied", "Merged to Linus", "Released"):
        if milestone not in status:
            raise ValueError(f"upstream status lacks milestone: {milestone}")
    for target in (
        ROOT / "docs/high-address-p2p-investigation.md",
        ROOT / "docs/dma-addressing.md",
        ROOT / "RELEASE_NOTES_v0.2.0.md",
        MANIFEST,
    ):
        if not target.is_file():
            raise ValueError(f"required release artifact missing: {target.relative_to(ROOT)}")


def validate_licenses_and_ci() -> None:
    if "MIT License" not in (ROOT / "LICENSE").read_text(encoding="utf-8"):
        raise ValueError("repository MIT license text missing")
    code_files = [
        ROOT / "scripts/lib/diagnose-common.sh",
        ROOT / "scripts/lib/hip-ipc-parser.awk",
        ROOT / "scripts/lib/transferbench-parser.awk",
        ROOT / "tests/run-offline-tests.sh",
        ROOT / "tests/validate_repository.py",
        ROOT / ".github/workflows/ci.yml",
    ]
    for path in code_files:
        if "SPDX-License-Identifier: MIT" not in path.read_text(encoding="utf-8")[:500]:
            raise ValueError(f"missing SPDX marker: {path.relative_to(ROOT)}")
    workflow = (ROOT / ".github/workflows/ci.yml").read_text(encoding="utf-8").lower()
    forbidden_ci = ("sudo ", "/dev/kfd", "rocminfo", "rocm-smi", "run-transferbench.sh", "run-rccl.sh")
    for token in forbidden_ci:
        if token in workflow:
            raise ValueError(f"CI must remain offline and GPU-free; found {token}")


def write_scan_report(path_count: int, findings: list[tuple[str, str]]) -> None:
    private_count = sum(label in {name for name, _ in PRIVATE_PATH_PATTERNS} | {"private_ipv4"} for _, label in findings)
    secret_count = len(findings) - private_count
    report = (
        "# Final Secret & Privacy Scan Report\n\n"
        "SCAN_SCOPE = tracked and non-ignored untracked repository files, excluding .git\n"
        "FILES_SCANNED = " + str(path_count) + "\n"
        "PRIVATE_PATH_OR_IP_MATCHES = " + str(private_count) + "\n"
        "SECRET_MATCHES = " + str(secret_count) + "\n"
        "RESULT = " + ("PASS" if not findings else "FAIL") + "\n"
    )
    REPORT.write_text(report, encoding="utf-8")
    if findings:
        for filename, label in findings:
            print(f"SCAN_FINDING file={filename} category={label}", file=sys.stderr)
        raise ValueError("publication scan failed")


def main() -> int:
    try:
        files = repository_files()
        count, findings = scan_publication(files)
        if findings:
            for filename, label in findings:
                print(f"SCAN_FINDING file={filename} category={label}", file=sys.stderr)
            raise ValueError("publication scan failed")
        validate_manifest()
        validate_readmes()
        validate_licenses_and_ci()
        if "--write-secret-report" in sys.argv:
            write_scan_report(count, findings)
        print("MANIFEST_VALIDATION=PASS")
        print("README_FACTS_AND_LINKS=PASS")
        print("LICENSE_AND_CI_SCOPE=PASS")
        print(f"SECRET_SCAN=PASS FILES_SCANNED={count}")
        return 0
    except (OSError, ValueError, json.JSONDecodeError, subprocess.CalledProcessError) as error:
        print(f"VALIDATION=FAIL {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
