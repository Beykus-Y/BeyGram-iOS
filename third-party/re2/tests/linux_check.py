#!/usr/bin/env python3
"""Checks the RE2 trigger bridge on Linux.

Builds RE2 (third-party/re2), the Abseil sources the app's Abseil copy needs for it (third-party/webrtc/absl/BUILD)
and bridge/bgre2.cc into a shared library, then runs the shared parity fixtures through the C ABI. The validation
and normalisation here mirror TriggerRegex.swift. This is a Linux check only; the iOS build and the Swift tests run
on a Mac.

    python3 third-party/re2/tests/linux_check.py [--work DIR] [--jobs N]

Exit status is 0 when every fixture passes.
"""

import argparse
import concurrent.futures
import ctypes
import json
import os
import re
import subprocess
import sys
import tempfile
import time
import unicodedata

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
RE2_DIR = os.path.join(ROOT, "third-party", "re2")
ABSL_DIR = os.path.join(ROOT, "third-party", "webrtc", "absl")
WEBRTC_ABSL_BUILD = os.path.join(ABSL_DIR, "BUILD")
FIXTURES = os.path.join(ROOT, "submodules", "BeyGramTriggerWords", "Tests", "Fixtures", "regex_parity.json")
MAX_PATTERN_UTF16 = 120


def starlark_list(build_file, name):
    """The .cc files of the top-level `name = [...]` list in a BUILD file."""
    with open(build_file, encoding="utf-8") as f:
        text = f.read()
    match = re.search(r"^%s = \[(.*?)^\]" % re.escape(name), text, re.S | re.M)
    if match is None:
        raise SystemExit("%s: no list named %s" % (build_file, name))
    return re.findall(r'"([^"]+\.cc)"', match.group(1))


def build_library(work, jobs):
    """Compiles every source and links libbgre2.so with no undefined symbols. Returns its path."""
    objdir = os.path.join(work, "obj")
    os.makedirs(objdir, exist_ok=True)
    sources = []
    for rel in starlark_list(os.path.join(RE2_DIR, "BUILD.bazel"), "re2_sources"):
        sources.append((os.path.join(RE2_DIR, rel), ["-w"]))
    for rel in starlark_list(WEBRTC_ABSL_BUILD, "absl_sources") + starlark_list(WEBRTC_ABSL_BUILD, "absl_re2_sources"):
        sources.append((os.path.join(ABSL_DIR, rel), ["-w"]))
    sources.append((os.path.join(RE2_DIR, "bridge", "bgre2.cc"), ["-Wall", "-Wextra", "-Werror"]))

    def compile_one(index):
        src, flags = sources[index]
        out = os.path.join(objdir, "%03d.o" % index)
        cmd = ["clang++", "-std=c++17", "-O1", "-fPIC", "-pthread", "-DABSL_ALLOCATOR_NOTHROW=1",
               "-I" + RE2_DIR, "-I" + ABSL_DIR] + flags + ["-c", src, "-o", out]
        result = subprocess.run(cmd, capture_output=True, text=True)
        return index, result.returncode, result.stderr

    failed = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=jobs) as pool:
        for index, code, stderr in pool.map(compile_one, range(len(sources))):
            if code != 0:
                failed.append((sources[index][0], stderr[-800:]))
    if failed:
        for src, stderr in failed:
            print("COMPILE FAILED: %s\n%s" % (src, stderr))
        raise SystemExit(1)

    objects = [os.path.join(objdir, "%03d.o" % i) for i in range(len(sources))]
    so = os.path.join(work, "libbgre2.so")
    link = subprocess.run(["clang++", "-shared", "-fPIC", "-pthread", "-Wl,--no-undefined", "-o", so] + objects,
                          capture_output=True, text=True)
    if link.returncode != 0:
        print("LINK FAILED\n" + link.stderr[-2000:])
        raise SystemExit(1)
    print("built %s from %d sources" % (so, len(sources)))
    return so


def load(so):
    lib = ctypes.CDLL(so)
    lib.bgre2_compile.argtypes = [ctypes.c_char_p, ctypes.c_size_t, ctypes.c_int]
    lib.bgre2_compile.restype = ctypes.c_void_p
    lib.bgre2_partial_match.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_size_t]
    lib.bgre2_partial_match.restype = ctypes.c_int
    lib.bgre2_free.argtypes = [ctypes.c_void_p]
    lib.bgre2_free.restype = None
    return lib


def normalize(text):
    """NFKC, then invisible format characters (category Cf) removed, as TriggerRegex.normalizeText does."""
    return "".join(ch for ch in unicodedata.normalize("NFKC", text) if unicodedata.category(ch) != "Cf")


class Regex:
    def __init__(self, lib, pattern, ignore_case):
        data = pattern.encode("utf-8")
        self._lib = lib
        self._handle = lib.bgre2_compile(data, len(data), 0 if ignore_case else 1)
        if not self._handle:
            raise ValueError(pattern)

    def matches(self, text):
        data = normalize(text).encode("utf-8")
        return self._lib.bgre2_partial_match(self._handle, data, len(data)) != 0

    def close(self):
        if self._handle:
            self._lib.bgre2_free(self._handle)
            self._handle = None


def validate(lib, pattern, ignore_case):
    """OK, EMPTY, TOO_LONG, BAD_REGEX or REGEX_MATCHES_EMPTY, checked in the order TriggerRegexValidator uses."""
    trimmed = pattern.strip()
    if not trimmed:
        return "EMPTY"
    if len(trimmed.encode("utf-16-le")) // 2 > MAX_PATTERN_UTF16:
        return "TOO_LONG"
    try:
        regex = Regex(lib, trimmed, ignore_case)
    except ValueError:
        return "BAD_REGEX"
    try:
        return "REGEX_MATCHES_EMPTY" if regex.matches("") or regex.matches(" ") else "OK"
    finally:
        regex.close()


def run_fixtures(lib):
    with open(FIXTURES, encoding="utf-8") as f:
        fixtures = json.load(f)
    if fixtures["schema"] != 1:
        raise SystemExit("unexpected fixture schema %r" % fixtures["schema"])
    failures = []
    cases = 0
    for case in fixtures["validate"]:
        cases += 1
        got = validate(lib, case["pattern"], case["ignoreCase"])
        if got != case["expect"]:
            failures.append("validate %r ignoreCase=%s: got %s, expected %s (%s)" % (
                case["pattern"], case["ignoreCase"], got, case["expect"], case["source"]))
    slowest = 0.0
    for case in fixtures["matches"]:
        cases += 1
        try:
            regex = Regex(lib, case["pattern"], case["ignoreCase"])
        except ValueError:
            failures.append("match %r: RE2 rejected the pattern (%s)" % (case["pattern"], case["source"]))
            continue
        text = case["text"] * case["repeat"] + case["suffix"]
        started = time.monotonic()
        fired = regex.matches(text)
        slowest = max(slowest, time.monotonic() - started)
        regex.close()
        if fired != case["fires"]:
            failures.append("match %r on %d repetitions: fired=%s, expected %s (%s)" % (
                case["pattern"], case["repeat"], fired, case["fires"], case["source"]))
    return cases, failures, slowest


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--work", help="build directory (default: a new temporary directory)")
    parser.add_argument("--jobs", type=int, default=os.cpu_count() or 4)
    args = parser.parse_args()
    work = args.work or tempfile.mkdtemp(prefix="bgre2-")
    so = build_library(work, args.jobs)
    cases, failures, slowest = run_fixtures(load(so))
    print("fixtures: %d cases, %d failures, slowest match %.1f ms" % (cases, len(failures), slowest * 1000))
    for failure in failures:
        print("FAIL " + failure)
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
