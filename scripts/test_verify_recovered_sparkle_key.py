"""Check recovery verification with disposable keys only."""
import base64
import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch
import warnings

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

spec = importlib.util.spec_from_file_location("recovered_sparkle", Path(__file__).with_name("verify-recovered-sparkle-key.py"))
verify = importlib.util.module_from_spec(spec)
spec.loader.exec_module(verify)


class RecoveryTests(unittest.TestCase):
    def test_matching_and_different_keys(self):
        first, second = Ed25519PrivateKey.generate(), Ed25519PrivateKey.generate()
        seed = base64.b64encode(first.private_bytes(serialization.Encoding.Raw,
            serialization.PrivateFormat.Raw, serialization.NoEncryption())).decode()
        def public(key):
            return base64.b64encode(key.public_key().public_bytes(serialization.Encoding.Raw,
                serialization.PublicFormat.Raw)).decode()
        self.assertTrue(verify.matches(seed, public(first)))
        self.assertFalse(verify.matches(seed, public(second)))

    def test_invalid_encoding_and_lengths_are_rejected(self):
        public = base64.b64encode(bytes(32)).decode()
        for seed in ("not base64!", base64.b64encode(bytes(31)).decode()):
            with self.subTest(seed=seed), self.assertRaises(ValueError):
                verify.matches(seed, public)
        with self.assertRaises(ValueError):
            verify.matches(public, "bad!")

    def test_rejects_nonterminal_without_asking_for_secret(self):
        with patch.object(verify.sys, "argv", ["verify", "--public-key-file", "public"]), \
             patch.object(verify.sys.stdin, "isatty", return_value=False), \
             patch.object(verify.getpass, "getpass") as getpass:
            with self.assertRaises(SystemExit):
                verify.main()
            getpass.assert_not_called()

    def test_unsafe_getpass_fallback_fails_closed(self):
        def unsafe(_prompt):
            warnings.warn("Cannot disable echo", verify.getpass.GetPassWarning)
        with patch.object(verify.sys, "argv", ["verify", "--public-key-file", "public"]), \
             patch.object(verify.sys.stdin, "isatty", return_value=True), \
             patch.object(verify.sys.stderr, "isatty", return_value=True), \
             patch.object(verify.Path, "read_text", return_value="public"), \
             patch.object(verify.getpass, "getpass", side_effect=unsafe):
            with self.assertRaises(SystemExit):
                verify.main()
