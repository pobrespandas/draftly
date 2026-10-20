#!/usr/bin/env python3
"""Measure the native word tokenizer. Do not launch or change an app."""
import argparse
import ctypes as C
import datetime
import hashlib
import json
import platform
from pathlib import Path
import statistics
import subprocess
import sys
import time


FIXTURE = """Prueba visual 50 — Referencia con Unicode 🐼 café

Español: áéíóú ñ. 日本語。 Emoji: 🐼 🌿 🚀.

Una segunda línea para comprobar Unicode.

visual-qa-20261019"""


class Range(C.Structure):
    _fields_ = [("location", C.c_ulong), ("length", C.c_ulong)]


class Descriptor(C.Structure):
    _fields_ = [("reserved", C.c_ulong), ("size", C.c_ulong)]


class Block(C.Structure):
    _fields_ = [("isa", C.c_void_p), ("flags", C.c_int),
                ("reserved", C.c_int), ("invoke", C.c_void_p),
                ("descriptor", C.POINTER(Descriptor))]


class NativeTokenizer:
    def __init__(self):
        foundation = C.CDLL("/System/Library/Frameworks/Foundation.framework/Foundation")
        objc = C.CDLL("/usr/lib/libobjc.A.dylib")
        system = C.CDLL("/usr/lib/libSystem.B.dylib")
        objc.objc_getClass.argtypes = [C.c_char_p]
        objc.objc_getClass.restype = C.c_void_p
        objc.sel_registerName.argtypes = [C.c_char_p]
        objc.sel_registerName.restype = C.c_void_p
        self.cls = lambda name: objc.objc_getClass(name.encode())
        self.sel = lambda name: objc.sel_registerName(name.encode())
        address = C.cast(objc.objc_msgSend, C.c_void_p).value
        self.object = C.CFUNCTYPE(C.c_void_p, C.c_void_p, C.c_void_p)(address)
        self.one = C.CFUNCTYPE(C.c_void_p, C.c_void_p, C.c_void_p, C.c_void_p)(address)
        self.string = C.CFUNCTYPE(C.c_void_p, C.c_void_p, C.c_void_p, C.c_char_p)(address)
        self.length = C.CFUNCTYPE(C.c_ulong, C.c_void_p, C.c_void_p)(address)
        self.init = C.CFUNCTYPE(C.c_void_p, C.c_void_p, C.c_void_p, C.c_void_p, C.c_ulong)(address)
        self.put = C.CFUNCTYPE(None, C.c_void_p, C.c_void_p, C.c_void_p)(address)
        self.enumerate = C.CFUNCTYPE(None, C.c_void_p, C.c_void_p, Range, C.c_ulong,
                                    C.c_void_p, C.c_ulong, C.POINTER(Block))(address)
        self.invoke_type = C.CFUNCTYPE(None, C.c_void_p, C.c_void_p, Range, C.POINTER(C.c_bool))
        self.stack_block = C.addressof((C.c_void_p * 32).in_dll(system, "_NSConcreteStackBlock"))
        self.scheme = C.c_void_p.in_dll(foundation, "NSLinguisticTagSchemeTokenType").value
        self.schemes = self.one(self.cls("NSArray"), self.sel("arrayWithObject:"), self.scheme)
        self.object(self.scheme, self.sel("retain"))
        self.object(self.schemes, self.sel("retain"))
        self.allocate = self.sel("alloc")
        self.initialize = self.sel("init")
        self.drain = self.sel("drain")
        self.release = self.sel("release")
        self.initialize_tagger = self.sel("initWithTagSchemes:options:")
        self.set_string = self.sel("setString:")
        self.enumerate_tags = self.sel("enumerateTagsInRange:unit:scheme:options:usingBlock:")
        self.make_string = self.sel("stringWithUTF8String:")
        self.get_length = self.sel("length")

    def sample(self, text):
        pool = self.object(self.object(self.cls("NSAutoreleasePool"), self.allocate), self.initialize)
        value = self.string(self.cls("NSString"), self.make_string, text.encode())
        length = self.length(value, self.get_length)
        words = 0
        callbacks = 0
        overlaps = 0
        empty = 0
        non_monotonic = 0
        previous = None
        last_location = None

        @self.invoke_type
        def invoke(_block, _tag, token, _stop):
            nonlocal words, callbacks, overlaps, empty, previous, last_location, non_monotonic
            callbacks += 1
            if token.length == 0:
                empty += 1
                return
            start, end = token.location, token.location + token.length
            if last_location is not None and start < last_location:
                non_monotonic += 1
            last_location = start
            if previous and min(previous[1], end) > max(previous[0], start):
                overlaps += 1
                previous = min(previous[0], start), max(previous[1], end)
            else:
                words += 1
                previous = start, end

        descriptor = Descriptor(0, C.sizeof(Block))
        block = Block(self.stack_block, 0, 0, C.cast(invoke, C.c_void_p).value, C.pointer(descriptor))
        start = time.perf_counter_ns()
        tagger = self.init(self.object(self.cls("NSLinguisticTagger"), self.allocate), self.initialize_tagger, self.schemes, 0)
        self.put(tagger, self.set_string, value)
        # Word unit is 0. Omit punctuation and whitespace; keep other symbols.
        self.enumerate(tagger, self.enumerate_tags, Range(0, length), 0, self.scheme, 6, C.pointer(block))
        self.object(tagger, self.release)
        milliseconds = (time.perf_counter_ns() - start) / 1_000_000
        self.object(pool, self.drain)
        return {"wordCount": words, "utf16Units": length, "milliseconds": milliseconds,
                "callbackCount": callbacks, "overlapFragments": overlaps,
                "emptyCallbacks": empty, "nonMonotonicTokenStarts": non_monotonic}


def command(*arguments):
    return subprocess.check_output(arguments, text=True).strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runs", type=int, default=9)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    if sys.platform != "darwin" or platform.machine() != "arm64":
        parser.error("Run this benchmark on an Apple silicon Mac.")
    if args.runs < 2:
        parser.error("Use at least two runs.")
    tokenizer = NativeTokenizer()
    cases = [("neutral-unicode-149", FIXTURE),
             ("mixed-unicode-100000", (FIXTURE * 672)[:100000]),
             ("latin-100000", "word " * 20000),
             ("latin-99999-no-trailing-space", ("word " * 20000).rstrip()),
             ("single-latin-word-100000", "a" * 100000)]
    measurements = []
    for name, text in cases:
        samples = [tokenizer.sample(text) for _ in range(args.runs)]
        counts = {sample["wordCount"] for sample in samples}
        if len(counts) != 1:
            raise RuntimeError("The tokenizer returned different counts between runs.")
        milliseconds = [sample["milliseconds"] for sample in samples]
        measurements.append({"fixture": name, "sha256UTF8": hashlib.sha256(text.encode()).hexdigest(),
                             "codePoints": len(text), "utf16Units": samples[0]["utf16Units"], "wordCount": samples[0]["wordCount"],
                             "callbackCount": samples[0]["callbackCount"], "overlapFragments": samples[0]["overlapFragments"],
                             "emptyCallbacks": samples[0]["emptyCallbacks"], "nonMonotonicTokenStarts": samples[0]["nonMonotonicTokenStarts"],
                             "samplesMs": milliseconds, "firstMs": milliseconds[0],
                             "warmMedianMs": statistics.median(milliseconds[1:]),
                             "warmMinimumMs": min(milliseconds[1:]), "warmMaximumMs": max(milliseconds[1:])})
    report = {"capturedAt": datetime.datetime.now(datetime.timezone.utc).isoformat(),
              "hardware": {"model": command("/usr/sbin/sysctl", "-n", "hw.model"),
                           "chip": command("/usr/sbin/sysctl", "-n", "machdep.cpu.brand_string"),
                           "memoryBytes": int(command("/usr/sbin/sysctl", "-n", "hw.memsize"))},
              "runtime": {"macOS": command("/usr/bin/sw_vers", "-productVersion"),
                          "build": command("/usr/bin/sw_vers", "-buildVersion"),
                          "architecture": platform.machine(), "python": sys.version, "executable": sys.executable},
              "method": "NSLinguisticTagger.enumerateTags: word unit, tokenType, omit punctuation and whitespace; keep other symbols; ignore empty ranges and count overlapping fragments once",
              "scriptSHA256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
              "runsPerFixture": args.runs, "measurements": measurements,
              "limits": ["This is a native tokenizer benchmark with a Python Objective-C bridge.",
                         "The timer includes tagger creation, enumeration, release, and Python callbacks.",
                         "The timer excludes NSString creation and Swift character counting.",
                         "This is not a full UI, typing, rendering, save, or cached-redraw measurement.",
                         "The first run of each fixture may reuse framework data loaded by an earlier fixture.",
                         "Content changes still require tokenization. Memoization only removes unchanged-content work."]}
    output = json.dumps(report, ensure_ascii=False, indent=2) + "\n"
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(output)
    else:
        print(output, end="")


if __name__ == "__main__":
    main()
