#!/usr/bin/env python3
import re
import signal
import subprocess
import sys
import time
import xml.etree.ElementTree as ET
from pathlib import Path


FAIL_PATTERNS = [
    ("Out Of Memory", re.compile(r"Out Of Memory", re.I)),
    ("Encountered an app crash", re.compile(r"Encountered an app crash", re.I)),
    ("app crash", re.compile(r"\bapp crash\b", re.I)),
    ("No such resource", re.compile(r"No such resource", re.I)),
    ("Resource not found", re.compile(r"Resource not found", re.I)),
    ("Unhandled Exception", re.compile(r"Unhandled Exception", re.I)),
]


def parse_manifest_devices(manifest_path: Path):
    ns = {"iq": "http://www.garmin.com/xml/connectiq"}
    root = ET.parse(manifest_path).getroot()
    return [e.attrib["id"] for e in root.findall(".//iq:products/iq:product", ns)]


def find_latest_sdk_dir() -> Path:
    sdk_root = Path.home() / "Library/Application Support/Garmin/ConnectIQ/Sdks"
    candidates = sorted(sdk_root.glob("connectiq-sdk-*"))
    if not candidates:
        raise RuntimeError(f"No SDK found in {sdk_root}")
    return candidates[-1]


def run_cmd(args, cwd: Path, timeout=None):
    return subprocess.run(
        args,
        cwd=str(cwd),
        text=True,
        capture_output=True,
        timeout=timeout,
        check=False,
    )


def ensure_simulator_open(sdk_dir: Path):
    subprocess.run(["open", str(sdk_dir / "bin" / "ConnectIQ.app")], check=False)
    time.sleep(8)


def run_monkeydo_for_device(sdk_dir: Path, repo: Path, prg_rel: str, device_id: str, timeout_sec: int):
    monkeydo = sdk_dir / "bin" / "monkeydo"
    proc = subprocess.Popen(
        [str(monkeydo), prg_rel, device_id],
        cwd=str(repo),
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    timed_out = False
    try:
        out, _ = proc.communicate(timeout=timeout_sec)
    except subprocess.TimeoutExpired:
        timed_out = True
        proc.terminate()
        try:
            out, _ = proc.communicate(timeout=2)
        except subprocess.TimeoutExpired:
            proc.kill()
            out, _ = proc.communicate()
    return proc.returncode, timed_out, out or ""


def detect_failure(output: str):
    for label, pattern in FAIL_PATTERNS:
        if pattern.search(output):
            return label
    return None


def main():
    repo = Path.cwd()
    manifest = repo / "manifest.xml"
    logs_dir = repo / "logs" / "verify"
    logs_dir.mkdir(parents=True, exist_ok=True)
    summary_path = logs_dir / "summary.tsv"

    devices = parse_manifest_devices(manifest)
    if not devices:
        print("No devices found in manifest.xml", file=sys.stderr)
        return 1

    print("设备列表（来自 manifest.xml）:")
    for d in devices:
        print(d)

    sdk_dir = find_latest_sdk_dir()
    monkeyc = sdk_dir / "bin" / "monkeyc"
    compile_device = "fenix7s" if "fenix7s" in devices else devices[0]
    prg_rel = "bin/verify.prg"

    print(f"\nSDK_DIR={sdk_dir}")
    print(f"编译一次 PRG（目标设备用于编译：{compile_device}）...")
    build = run_cmd(
        [str(monkeyc), "-f", "monkey.jungle", "-o", prg_rel, "-y", "developer_key", "-d", compile_device],
        cwd=repo,
    )
    sys.stdout.write(build.stdout)
    sys.stderr.write(build.stderr)
    if build.returncode != 0:
        print("\n编译失败，停止验证。", file=sys.stderr)
        return build.returncode

    print("\n开始逐机型 monkeydo 运行验证（每台 8 秒）...")

    rows = []
    for device_id in devices:
        ensure_simulator_open(sdk_dir)
        rc, timed_out, output = run_monkeydo_for_device(sdk_dir, repo, prg_rel, device_id, timeout_sec=8)
        log_path = logs_dir / f"{device_id}.log"
        log_path.write_text(output, encoding="utf-8")

        fail_reason = detect_failure(output)
        if fail_reason:
            status = "FAIL"
            reason = fail_reason
        elif timed_out:
            status = "PASS"
            reason = "-"
        elif rc == 0:
            status = "PASS"
            reason = "-"
        else:
            status = "FAIL"
            reason = f"Exit {rc}"

        rows.append((device_id, status, reason, str(log_path.relative_to(repo))))
        print(f"{device_id}: {status} ({reason})")

    with summary_path.open("w", encoding="utf-8") as f:
        for row in rows:
            f.write("\t".join(row) + "\n")

    print("\n汇总表:")
    print("deviceId | PASS/FAIL | 失败原因关键字（若有） | 日志文件路径")
    for d, s, r, p in rows:
        print(f"{d} | {s} | {r} | {p}")
    print(f"\nsummary.tsv: {summary_path.relative_to(repo)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
