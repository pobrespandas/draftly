// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Draftly",
    platforms: [.macOS(.v26)],
    products: [.library(name: "AgentContracts", targets: ["AgentContracts"]), .library(name: "AgentLocalSecurity", targets: ["AgentLocalSecurity"]), .library(name: "DraftlyCore", targets: ["DraftlyCore"]), .executable(name: "Draftly", targets: ["Draftly"]), .executable(name: "DraftlyLibraryBenchmark", targets: ["LibraryBenchmark"])],
    dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.6")],
    targets: [
        .target(name: "CMultiMarkdown", path: "Vendor/CMultiMarkdown", exclude: ["LICENSE"], sources: ["src"], publicHeadersPath: "include", cSettings: [.headerSearchPath("src"), .define("DISABLE_OBJECT_POOL")]),
        .target(name: "CGFM", path: "Vendor/CGFM", exclude: ["COPYING", "src/case_fold_switch.inc", "src/entities.inc"], sources: ["src", "extensions"], publicHeadersPath: "include", cSettings: [.headerSearchPath("src"), .headerSearchPath("extensions"), .define("CMARK_GFM_STATIC_DEFINE"), .define("CMARK_GFM_EXTENSIONS_STATIC_DEFINE")]),
        .target(name: "AgentContracts"),
        .target(name: "AgentLocalSecurity", dependencies: ["AgentContracts"]),
        .testTarget(name: "AgentContractsTests", dependencies: ["AgentContracts", "DraftlyCore"], resources: [.copy("required-operations.txt")]),
        .testTarget(name: "AgentContractsConsumerTests", dependencies: ["AgentContracts"]),
        .target(name: "DraftlyCore", dependencies: ["CMultiMarkdown", "CGFM"], resources: [.process("Resources")]),
        .executableTarget(name: "Draftly", dependencies: ["DraftlyCore", "AgentContracts", "AgentLocalSecurity", .product(name: "Sparkle", package: "Sparkle")]),
        .executableTarget(name: "LibraryBenchmark", dependencies: ["DraftlyCore"], path: "Tools/LibraryBenchmark"),
        .testTarget(name: "DraftlyCoreTests", dependencies: ["DraftlyCore"], resources: [.copy("Fixtures")]),
        .testTarget(name: "DraftlyTests", dependencies: ["Draftly", "DraftlyCore", "AgentContracts", "AgentLocalSecurity"])
    ],
    swiftLanguageModes: [.v6]
)
