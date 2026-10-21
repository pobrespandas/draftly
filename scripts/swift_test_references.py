"""Resolve Swift test references within one validation run."""
from pathlib import Path
import re


def swift_code_mask(source):
    # Remove comments and strings. Keep offsets for function boundaries.
    pattern = r'/\*[\s\S]*?\*/|//[^\n]*|(?P<raw>\#+)?"""[\s\S]*?"""(?P=raw)?|(?P<quote>\#+)?"(?:\\.|[^"\\])*"(?P=quote)?'
    return re.sub(pattern, lambda match: re.sub(r"[^\n]", " ", match.group()), source)


class SwiftTestReferences:
    def __init__(self, root):
        self.root = root
        self._sources = {}

    def _masked_source(self, path):
        if path not in self._sources:
            self._sources[path] = swift_code_mask(path.read_text())
        return self._sources[path]

    def issue(self, value):
        if not self.valid(value):
            return None
        pattern = r"\bfunc\s+" + re.escape(value["test"]) + r"\s*\("
        for path in self.paths(value):
            code = self._masked_source(path)
            for match in re.finditer(pattern, code):
                start = code.find("{", match.end())
                if start < 0:
                    continue
                depth, end = 1, start + 1
                while end < len(code) and depth:
                    depth += (code[end] == "{") - (code[end] == "}")
                    end += 1
                for suite in re.finditer(r"@Suite\b([\s\S]*?)\b(?:struct|class|enum)\s+\w+[^\{]*\{", code):
                    if not re.search(r"\.disabled\b", suite.group(1)):
                        continue
                    suite_depth, suite_end = 1, suite.end()
                    while suite_end < len(code) and suite_depth:
                        suite_depth += (code[suite_end] == "{") - (code[suite_end] == "}")
                        suite_end += 1
                    if suite.end() <= match.start() < suite_end:
                        return value["suite"] + "." + value["test"] + " belongs to a disabled suite"
                annotation = code.rfind("@Test", 0, match.start())
                prefix = code[annotation:match.start()] if annotation >= 0 else ""
                if re.search(r"\.disabled\b", prefix) and "func " not in prefix:
                    return value["suite"] + "." + value["test"] + " is disabled"
                if re.search(r"\bwithKnownIssue\s*(?:\(|\{)", code[start:end]):
                    return value["suite"] + "." + value["test"] + " contains withKnownIssue"
        return None

    def valid(self, value):
        if not isinstance(value, dict) or not all(isinstance(value.get(field), str) and value[field] for field in ("suite", "test")):
            return False
        pattern = r"\bfunc\s+" + re.escape(value["test"]) + r"\s*\("
        return any(re.search(pattern, self._masked_source(path)) for path in self.paths(value))

    def paths(self, value):
        tests = (self.root / "Tests").resolve()
        if "file" in value:
            filename = value["file"]
            if not isinstance(filename, str) or not filename:
                return []
            relative = Path(filename)
            if relative.is_absolute() or ".." in relative.parts:
                return []
            path = (self.root / relative).resolve()
            if not path.is_relative_to(tests) or path.suffix != ".swift" or not path.is_file():
                return []
            return [path]
        return list(tests.rglob(value["suite"] + ".swift"))
