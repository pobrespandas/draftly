"""Check the standalone app's internal package dependencies."""
import hashlib
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


class GeneratedProjectTests(unittest.TestCase):
    def test_app_links_internal_contracts_with_the_same_package_identity(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "scripts").mkdir()
            (root / "Sources/Draftly").mkdir(parents=True)
            (root / "Sources/Draftly/Fixture.swift").write_text("import AgentContracts\nimport AgentLocalSecurity\n")
            generator = root / "scripts/generate-project.py"
            shutil.copyfile(Path(__file__).with_name("generate-project.py"), generator)
            subprocess.run(["python3", str(generator)], check=True, capture_output=True)
            project = (root / "Draftly.xcodeproj/project.pbxproj").read_text()
            def identifier(name):
                return hashlib.sha256(name.encode()).hexdigest()[:24].upper()
            contracts = identifier("contracts")
            build = identifier("contractsbuild")
            security = identifier("agentsecurity")
            security_build = identifier("agentsecuritybuild")
            self.assertIn(f"productRef = {contracts}", project)
            self.assertIn("productName = AgentContracts", project)
            self.assertIn(f"productRef = {security}", project)
            self.assertIn("productName = AgentLocalSecurity", project)
            self.assertIn(f"files = ({identifier('corebuild')},{build},{security_build},{identifier('sparklebuild')})", project)
            self.assertIn(f"packageProductDependencies = ({identifier('core')},{contracts},{security},{identifier('sparkle')})", project)
            self.assertEqual(project.count('-package-name draftly'), 2)
            self.assertIn("Fixture.swift", project)


if __name__ == "__main__":
    unittest.main()
