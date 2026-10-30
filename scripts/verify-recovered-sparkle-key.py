#!/usr/bin/env python3
"""Check a recovered Sparkle seed against a public key without printing it."""
import argparse
import base64
import getpass
import hmac
from pathlib import Path
import sys
import warnings

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey


def matches(seed_text, public_text):
    try:
        seed = base64.b64decode(seed_text.strip(), validate=True)
        public = base64.b64decode(public_text.strip(), validate=True)
    except (ValueError, TypeError):
        raise ValueError("The key encoding is invalid.") from None
    if len(seed) != 32 or len(public) != 32:
        raise ValueError("The key length is invalid.")
    actual = Ed25519PrivateKey.from_private_bytes(seed).public_key().public_bytes(
        serialization.Encoding.Raw, serialization.PublicFormat.Raw)
    return hmac.compare_digest(actual, public)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--public-key-file", required=True, type=Path)
    args = parser.parse_args()
    if not sys.stdin.isatty() or not sys.stderr.isatty():
        parser.exit(1, "A terminal is required for hidden key entry.\n")
    try:
        public = args.public_key_file.read_text(encoding="ascii")
        with warnings.catch_warnings():
            warnings.simplefilter("error", getpass.GetPassWarning)
            secret = getpass.getpass("Paste recovered Sparkle seed (hidden): ")
        if not matches(secret, public):
            raise ValueError("The recovered key does not match the public key.")
    except (OSError, UnicodeError, ValueError, EOFError, KeyboardInterrupt, getpass.GetPassWarning) as error:
        parser.exit(1, "Recovery verification failed: " + str(error) + "\n")
    print("The recovered key matches the public key.")


if __name__ == "__main__":
    main()
