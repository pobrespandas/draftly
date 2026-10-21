"""Keep independently imported manual action fixtures from replacing each other."""
import json
from pathlib import Path
import unittest
from uuid import UUID


class ManualActionFixtureTests(unittest.TestCase):
    def test_action_array_fixtures_have_distinct_explicit_identities(self):
        owners = {}
        fixtures = Path(__file__).with_name("fixtures")
        for path in sorted(fixtures.glob("*actions.json")):
            values = json.loads(path.read_text())
            if not isinstance(values, list):
                continue
            for action in values:
                if not isinstance(action, dict) or "uuid" not in action:
                    continue
                identity = UUID(action["uuid"])
                owner = f'{path.name}: {action.get("name", "unnamed")}'
                self.assertTrue(identity not in owners,
                                 f'{owner} replaces {owners.get(identity)} on import')
                owners[identity] = owner
        self.assertTrue(owners, "The check must inspect explicit action identities.")


if __name__ == "__main__":
    unittest.main()
