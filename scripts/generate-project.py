#!/usr/bin/env python3
"""Generate the Xcode app target. Keep the core in the local Swift package."""
from pathlib import Path
import hashlib

root = Path(__file__).resolve().parent.parent
def uid(name):
    return hashlib.sha256(name.encode()).hexdigest()[:24].upper()
objects = []
def add(name, body):
    objects.append(f"{uid(name)} = {{ {body} }};")
    return uid(name)

sources = []
references = []
for path in sorted((root / "Sources/Draftly").glob("*.swift")):
    ref = add(str(path.name), f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "{path.name}"; sourceTree = "<group>";')
    references.append(ref)
    sources.append(add("build:" + path.name, f"isa = PBXBuildFile; fileRef = {ref};"))
app = add("product", 'isa = PBXFileReference; explicitFileType = wrapper.application; path = Draftly.app; sourceTree = BUILT_PRODUCTS_DIR;')
local = add("package", 'isa = XCLocalSwiftPackageReference; relativePath = .;')
sparkle_package = add("sparkle-package", 'isa = XCRemoteSwiftPackageReference; repositoryURL = "https://github.com/sparkle-project/Sparkle"; requirement = { kind = exactVersion; version = 2.9.6; };')
sparkle = add("sparkle", f'isa = XCSwiftPackageProductDependency; package = {sparkle_package}; productName = Sparkle;')
sparklebuild = add("sparklebuild", f'isa = PBXBuildFile; productRef = {sparkle};')
core = add("core", f'isa = XCSwiftPackageProductDependency; package = {local}; productName = DraftlyCore;')
corebuild = add("corebuild", f'isa = PBXBuildFile; productRef = {core};')
contracts = add("contracts", f'isa = XCSwiftPackageProductDependency; package = {local}; productName = AgentContracts;')
contractsbuild = add("contractsbuild", f'isa = PBXBuildFile; productRef = {contracts};')
agentsecurity = add("agentsecurity", f'isa = XCSwiftPackageProductDependency; package = {local}; productName = AgentLocalSecurity;')
agentsecuritybuild = add("agentsecuritybuild", f'isa = PBXBuildFile; productRef = {agentsecurity};')
sourcegroup = add("sourcegroup", 'isa = PBXGroup; path = Sources/Draftly; sourceTree = "<group>"; children = (' + ','.join(references) + ');')
products = add("products", f'isa = PBXGroup; name = Products; sourceTree = "<group>"; children = ({app});')
group = add("group", f'isa = PBXGroup; sourceTree = "<group>"; children = ({sourcegroup},{products});')
sourcephase = add("sources", 'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (' + ','.join(sources) + '); runOnlyForDeploymentPostprocessing = 0;')
frameworks = add("frameworks", f'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = ({corebuild},{contractsbuild},{agentsecuritybuild},{sparklebuild}); runOnlyForDeploymentPostprocessing = 0;')
icon = add("appicon", 'isa = PBXFileReference; lastKnownFileType = image.icns; path = Resources/Draftly.icns; sourceTree = SOURCE_ROOT;')
iconbuild = add("appiconbuild", f'isa = PBXBuildFile; fileRef = {icon};')
menuicon = add("menuicon", 'isa = PBXFileReference; lastKnownFileType = image.pdf; path = Resources/DraftlyMenuMark.pdf; sourceTree = SOURCE_ROOT;')
menuiconbuild = add("menuiconbuild", f'isa = PBXBuildFile; fileRef = {menuicon};')
resources = add("resources", f'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ({iconbuild},{menuiconbuild}); runOnlyForDeploymentPostprocessing = 0;')
signing = add("signing", 'isa = PBXFileReference; lastKnownFileType = text.xcconfig; path = Configuration/App.xcconfig; sourceTree = SOURCE_ROOT;')
for config in ["Debug", "Release"]:
    active = 'YES' if config == 'Debug' else 'NO'
    add("project:" + config, f'isa = XCBuildConfiguration; name = {config}; buildSettings = {{ SDKROOT = macosx; MACOSX_DEPLOYMENT_TARGET = 26.0; SWIFT_VERSION = 6.0; CLANG_ENABLE_MODULES = YES; ONLY_ACTIVE_ARCH = {active}; }};')
    settings = 'CODE_SIGN_STYLE = "$(DRAFTLY_CODE_SIGN_STYLE)"; PROVISIONING_PROFILE_SPECIFIER = "$(DRAFTLY_PROVISIONING_PROFILE)"; CODE_SIGN_ENTITLEMENTS = Configuration/Draftly.entitlements; INFOPLIST_FILE = Configuration/Info.plist; GENERATE_INFOPLIST_FILE = NO; PRODUCT_NAME = Draftly; ENABLE_HARDENED_RUNTIME = YES; LD_RUNPATH_SEARCH_PATHS = "$(inherited) @executable_path/../Frameworks"; SWIFT_EMIT_LOC_STRINGS = YES; OTHER_SWIFT_FLAGS = "$(inherited) -package-name draftly";'
    settings += ' SWIFT_OPTIMIZATION_LEVEL = "' + ('-Onone' if config == 'Debug' else '-O') + '";'
    add("app:" + config, f'isa = XCBuildConfiguration; name = {config}; baseConfigurationReference = {signing}; buildSettings = {{ {settings} }};')
projectconfigs = add("projectconfigs", 'isa = XCConfigurationList; buildConfigurations = (' + ','.join(uid('project:' + c) for c in ['Debug','Release']) + '); defaultConfigurationIsVisible = 0; defaultConfigurationName = Debug;')
appconfigs = add("appconfigs", 'isa = XCConfigurationList; buildConfigurations = (' + ','.join(uid('app:' + c) for c in ['Debug','Release']) + '); defaultConfigurationIsVisible = 0; defaultConfigurationName = Debug;')
target = add("target", f'isa = PBXNativeTarget; buildConfigurationList = {appconfigs}; buildPhases = ({sourcephase},{frameworks},{resources}); buildRules = (); dependencies = (); name = Draftly; productName = Draftly; productReference = {app}; productType = "com.apple.product-type.application"; packageProductDependencies = ({core},{contracts},{agentsecurity},{sparkle});')
project = add("project", f'isa = PBXProject; attributes = {{ BuildIndependentTargetsInParallel = YES; LastUpgradeCheck = 2710; }}; buildConfigurationList = {projectconfigs}; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en,Base); mainGroup = {group}; productRefGroup = {products}; projectDirPath = ""; projectRoot = ""; targets = ({target}); packageReferences = ({local},{sparkle_package});')
directory = root / 'Draftly.xcodeproj'
directory.mkdir(exist_ok=True)
(directory / 'project.pbxproj').write_text('// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n' + '\n'.join(objects) + f'\n}}; rootObject = {project}; }}\n')
schemes = directory / 'xcshareddata/xcschemes'
schemes.mkdir(parents=True, exist_ok=True)
(schemes / 'Draftly.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2710" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="Draftly.app" BlueprintName="Draftly" ReferencedContainer="container:Draftly.xcodeproj"/></BuildActionEntry></BuildActionEntries></BuildAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="Draftly.app" BlueprintName="Draftly" ReferencedContainer="container:Draftly.xcodeproj"/></BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release"/><AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>''')
