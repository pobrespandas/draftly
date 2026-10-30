"""Test Developer ID backup checks with temporary test certificates."""
import datetime
import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch
import warnings

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.serialization import pkcs12
from cryptography.x509.oid import NameOID

spec = importlib.util.spec_from_file_location('verify_developer_id', Path(__file__).with_name('verify-developer-id-backup.py'))
verify = importlib.util.module_from_spec(spec)
spec.loader.exec_module(verify)


def fixture(team=verify.TEAM):
    key = ec.generate_private_key(ec.SECP256R1())
    name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, 'Developer ID Application: Test'),
                      x509.NameAttribute(NameOID.ORGANIZATIONAL_UNIT_NAME, team)])
    now = datetime.datetime.now(datetime.timezone.utc)
    cert = (x509.CertificateBuilder().subject_name(name).issuer_name(name).public_key(key.public_key())
            .serial_number(x509.random_serial_number()).not_valid_before(now - datetime.timedelta(days=1))
            .not_valid_after(now + datetime.timedelta(days=1)).sign(key, hashes.SHA256()))
    archive = pkcs12.serialize_key_and_certificates(b'fixture', key, cert, None,
        serialization.BestAvailableEncryption(b'fixture-password'))
    return archive, cert.public_bytes(serialization.Encoding.PEM)


class BackupTests(unittest.TestCase):
    def test_matching_identity_and_private_key(self):
        archive, certificate = fixture()
        self.assertIsNone(verify.verify_backup(archive, b'fixture-password', certificate))

    def test_wrong_password_or_certificate_rejected(self):
        archive, certificate = fixture()
        _, other = fixture()
        for password, expected in ((b'wrong', certificate), (b'fixture-password', other)):
            with self.subTest(password=password), self.assertRaises(ValueError):
                verify.verify_backup(archive, password, expected)

    def test_other_team_and_malformed_archive_rejected(self):
        archive, certificate = fixture('OTHERTEAM')
        with self.assertRaises(ValueError):
            verify.verify_backup(archive, b'fixture-password', certificate)
        with self.assertRaises(ValueError):
            verify.verify_backup(b'bad', b'fixture-password', certificate)

    def test_no_terminal_refuses_to_prompt(self):
        with patch.object(verify.sys, 'argv', ['verify', '--backup', 'x', '--certificate', 'y']), \
             patch.object(verify.sys.stdin, 'isatty', return_value=False), \
             patch.object(verify.getpass, 'getpass') as prompt:
            with self.assertRaises(SystemExit):
                verify.main()
            prompt.assert_not_called()

    def test_echo_enabled_fallback_is_rejected(self):
        def unsafe(_):
            warnings.warn('Cannot disable echo', verify.getpass.GetPassWarning)
        with patch.object(verify.sys, 'argv', ['verify', '--backup', 'x', '--certificate', 'y']), \
             patch.object(verify.sys.stdin, 'isatty', return_value=True), \
             patch.object(verify.sys.stderr, 'isatty', return_value=True), \
             patch.object(verify.getpass, 'getpass', side_effect=unsafe):
            with self.assertRaises(SystemExit):
                verify.main()
