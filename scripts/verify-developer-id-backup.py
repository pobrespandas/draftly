#!/usr/bin/env python3
"""Verify a Developer ID PKCS#12 backup against its public certificate."""
import argparse
import getpass
import hmac
from pathlib import Path
import sys
import warnings

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.serialization import pkcs12
from cryptography.x509.oid import NameOID

TEAM = 'NM92LU2KKV'


def verify_backup(archive, password, expected_pem):
    if not archive or len(archive) > 1024 * 1024 or not password:
        raise ValueError('The backup or password is invalid.')
    try:
        key, cert, _ = pkcs12.load_key_and_certificates(archive, password)
        expected = x509.load_pem_x509_certificate(expected_pem)
    except (ValueError, TypeError):
        raise ValueError('The backup could not be opened.') from None
    if key is None or cert is None:
        raise ValueError('The backup must contain a private key and certificate.')
    subject = cert.subject
    names = subject.get_attributes_for_oid(NameOID.COMMON_NAME)
    teams = subject.get_attributes_for_oid(NameOID.ORGANIZATIONAL_UNIT_NAME)
    if (len(names) != 1 or not names[0].value.startswith('Developer ID Application: ')
            or len(teams) != 1 or teams[0].value != TEAM):
        raise ValueError('The certificate is not the expected Developer ID team.')
    if not hmac.compare_digest(cert.fingerprint(hashes.SHA256()), expected.fingerprint(hashes.SHA256())):
        raise ValueError('The certificate does not match the expected identity.')
    encoding = serialization.Encoding.DER
    fmt = serialization.PublicFormat.SubjectPublicKeyInfo
    if not hmac.compare_digest(key.public_key().public_bytes(encoding, fmt), cert.public_key().public_bytes(encoding, fmt)):
        raise ValueError('The private key does not match the certificate.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--backup', required=True, type=Path)
    parser.add_argument('--certificate', required=True, type=Path)
    args = parser.parse_args()
    if not sys.stdin.isatty() or not sys.stderr.isatty():
        parser.exit(1, 'A terminal is required for hidden password entry.\n')
    try:
        with warnings.catch_warnings():
            warnings.simplefilter('error', getpass.GetPassWarning)
            password = getpass.getpass('Backup password (hidden): ').encode('utf-8')
        verify_backup(args.backup.read_bytes(), password, args.certificate.read_bytes())
    except (OSError, ValueError, EOFError, KeyboardInterrupt, getpass.GetPassWarning) as error:
        parser.exit(1, 'Developer ID backup verification failed: ' + str(error) + '\n')
    print('The backup contains the private key for the expected Developer ID certificate.')


if __name__ == '__main__':
    main()
