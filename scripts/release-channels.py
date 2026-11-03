"""Parse stable, alpha, and beta release tags."""
import re

TAG_PATTERN = re.compile(r"v(?P<version>(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*))(?:-(?P<channel>alpha|beta)\.(?P<sequence>[1-9][0-9]*))?\Z")


def parse(tag):
    match = TAG_PATTERN.fullmatch(tag) if isinstance(tag, str) else None
    if match is None:
        raise ValueError("Use vMAJOR.MINOR.PATCH, optionally followed by -alpha.N or -beta.N.")
    return match.group("version"), match.group("channel") or "stable"


def precedence(tag):
    version, channel = parse(tag)
    numbers = tuple(int(part) for part in version.split('.'))
    rank = {'alpha': 0, 'beta': 1, 'stable': 2}[channel]
    sequence = 0 if channel == 'stable' else int(tag.rsplit('.', 1)[1])
    return numbers + (rank, sequence)
