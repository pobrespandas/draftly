"""Create a disposable Git repository for script contract tests."""
from contextlib import contextmanager
from pathlib import Path
import subprocess
import tempfile


class GitTestRepository:
    def __init__(self, root):
        self.root = Path(root)
        self.git('init', '-q')
        self.git('config', 'user.email', 'qa@example.invalid')
        self.git('config', 'user.name', 'QA')

    def git(self, *args):
        return subprocess.check_output(
            ['git', '-C', str(self.root), *args], text=True).strip()

    def commit(self, message):
        self.git('add', '-A')
        self.git('commit', '-qm', message)
        return self.git('rev-parse', 'HEAD')


@contextmanager
def temporary_git_repository():
    with tempfile.TemporaryDirectory() as directory:
        yield GitTestRepository(directory)
