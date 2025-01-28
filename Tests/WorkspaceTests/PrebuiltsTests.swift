//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

///
/// Tests for the macro prebuilts features that will use a prebuilt library for swift-syntax dependencies for macros.
///

import Basics
import struct TSCBasic.SHA256
import struct TSCBasic.ByteString
import struct TSCUtility.Version
import PackageGraph
import PackageModel
import Workspace
import XCTest
import _InternalTestSupport

final class PrebuiltsTests: XCTestCase {
    let swiftVersion = "\(SwiftVersion.current.major).\(SwiftVersion.current.minor)"
    let rootName = "Foo"

    /// Returns the root package and the workspace
    func initWorkspace(
        fs: InMemoryFileSystem,
        sandbox: AbsolutePath,
        httpClient: HTTPClient?,
        archiver: Archiver?,
        swiftSyntaxVersion: String,
        swiftSyntaxURL: String? = nil,
        triple: Triple? = nil
    ) async throws -> MockWorkspace {
        let swiftSyntaxURL = swiftSyntaxURL ?? "https://github.com/swiftlang/swift-syntax"

        let rootPackage = try MockPackage(
            name: rootName,
            targets: [
                MockTarget(
                    name: "FooMacros",
                    dependencies: [
                        .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                        .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
                    ],
                    type: .macro
                ),
                MockTarget(
                    name: "Foo",
                    dependencies: ["FooMacros"]
                ),
                MockTarget(
                    name: "FooClient",
                    dependencies: ["Foo"],
                    type: .executable
                ),
                MockTarget(
                    name: "FooTests",
                    dependencies: [
                        "FooMacros",
                        .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
                    ],
                    type: .test
                ),
            ],
            dependencies: [
                .sourceControl(
                    url: swiftSyntaxURL,
                    requirement: .exact(try XCTUnwrap(Version(swiftSyntaxVersion)))
                )
            ]
        )

        let swiftSyntax = try MockPackage(
            name: "swift-syntax",
            url: swiftSyntaxURL,
            targets: [
                MockTarget(name: "SwiftSyntaxMacrosTestSupport"),
                MockTarget(name: "SwiftCompilerPlugin"),
                MockTarget(name: "SwiftSyntaxMacros"),
            ],
            products: [
                MockProduct(name: "SwiftSyntaxMacrosTestSupport", modules: ["SwiftSyntaxMacrosTestSupport"]),
                MockProduct(name: "SwiftCompilerPlugin", modules: ["SwiftCompilerPlugin"]),
                MockProduct(name: "SwiftSyntaxMacros", modules: ["SwiftSyntaxMacros"]),
            ],
            versions: ["600.0.1", "600.0.2", "601.0.0"]
        )

        return try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                rootPackage
            ],
            packages: [
                swiftSyntax
            ],
            prebuiltsManager: .init(
                httpClient: httpClient,
                archiver: archiver
            ),
            customHostTriple: triple ?? Triple("arm64-apple-macosx15.0")
        )
    }

    func checkSettings(_ rootPackage: ResolvedPackage, _ targetName: String, _ swiftSyntaxVersion: String?) throws {
        let target = try XCTUnwrap(rootPackage.underlying.modules.first(where: { $0.name == targetName }))
        if let swiftSyntaxVersion {
            let swiftFlags = try XCTUnwrap(target.buildSettings.assignments[.OTHER_SWIFT_FLAGS]).flatMap({ $0.values })
            XCTAssertTrue(swiftFlags.contains("-I/tmp/ws/.build/prebuilts/swift-syntax/\(swiftSyntaxVersion)/\(self.swiftVersion)-MacroSupport-macos_aarch64/Modules".fixwin))
            XCTAssertTrue(swiftFlags.contains("-I/tmp/ws/.build/prebuilts/swift-syntax/\(swiftSyntaxVersion)/\(self.swiftVersion)-MacroSupport-macos_aarch64/include/_SwiftSyntaxCShims".fixwin))
            let ldFlags = try XCTUnwrap(target.buildSettings.assignments[.OTHER_LDFLAGS]).flatMap({ $0.values })
            XCTAssertTrue(ldFlags.contains("/tmp/ws/.build/prebuilts/swift-syntax/\(swiftSyntaxVersion)/\(self.swiftVersion)-MacroSupport-macos_aarch64/lib/libMacroSupport.a".fixwin))
        } else {
            XCTAssertNil(target.buildSettings.assignments[.OTHER_SWIFT_FLAGS])
            XCTAssertNil(target.buildSettings.assignments[.OTHER_LDFLAGS])
        }
    }

    func testSuccessPath() async throws {
        let sandbox = AbsolutePath("/tmp/ws")
        let fs = InMemoryFileSystem()

        let httpClient = HTTPClient { request, progressHandler in
            guard case .download(let fileSystem, let destination) = request.kind else {
                throw StringError("invalid request \(request.kind)")
            }

            if request.url == "https://download.swift.org/prebuilts/swift-syntax/600.0.1/\(self.swiftVersion)-MacroSupport-macos_aarch64.zip" {
                try fileSystem.writeFileContents(destination, data: Data())
                return .okay()
            } else {
                XCTFail("Unexpected URL \(request.url)")
                return .notFound()
            }
        }

        let archiver = MockArchiver(handler: { _, archivePath, destination, completion in
            XCTAssertEqual(archivePath.pathString, "/tmp/ws/.build/prebuilts/swift-syntax/600.0.1/\(self.swiftVersion)-MacroSupport-macos_aarch64.zip".fixwin)
            XCTAssertEqual(destination.pathString, "/tmp/ws/.build/prebuilts/swift-syntax/600.0.1/\(self.swiftVersion)-MacroSupport-macos_aarch64".fixwin)
            completion(.success(()))
        })

        let workspace = try await initWorkspace(
            fs: fs,
            sandbox: sandbox,
            httpClient: httpClient,
            archiver: archiver,
            swiftSyntaxVersion: "600.0.1"
        )

        try await workspace.checkPackageGraph(roots: [rootName]) { modulesGraph, diagnostics in
            XCTAssertTrue(diagnostics.filter({ $0.severity == .error || $0.severity == .warning }).isEmpty)
            let rootPackage = try XCTUnwrap(modulesGraph.rootPackages.first)
            try checkSettings(rootPackage, "FooMacros", "600.0.1")
            try checkSettings(rootPackage, "FooTests", "600.0.1")
            try checkSettings(rootPackage, "Foo", nil)
            try checkSettings(rootPackage, "FooClient", nil)
        }
    }

    func testVersionChange() async throws {
        let sandbox = AbsolutePath("/tmp/ws")
        let fs = InMemoryFileSystem()

        let httpClient = HTTPClient { request, progressHandler in
            guard case .download(let fileSystem, let destination) = request.kind else {
                throw StringError("invalid request \(request.kind)")
            }

            if request.url == "https://download.swift.org/prebuilts/swift-syntax/600.0.1/\(self.swiftVersion)-MacroSupport-macos_aarch64.zip" {
                try fileSystem.writeFileContents(destination, data: Data())
                return .okay()
            } else {
                // make sure it's the updated one
                XCTAssertEqual(
                    request.url,
                    "https://download.swift.org/prebuilts/swift-syntax/601.0.0/\(self.swiftVersion)-MacroSupport-macos_aarch64.zip"
                )
                return .notFound()
            }
        }

        let archiver = MockArchiver(handler: { _, archivePath, destination, completion in
            XCTAssertEqual(archivePath.pathString, "/tmp/ws/.build/prebuilts/swift-syntax/600.0.1/\(self.swiftVersion)-MacroSupport-macos_aarch64.zip".fixwin)
            XCTAssertEqual(destination.pathString, "/tmp/ws/.build/prebuilts/swift-syntax/600.0.1/\(self.swiftVersion)-MacroSupport-macos_aarch64".fixwin)
            completion(.success(()))
        })

        let workspace = try await initWorkspace(
            fs: fs,
            sandbox: sandbox,
            httpClient: httpClient,
            archiver: archiver,
            swiftSyntaxVersion: "600.0.1"
        )

        try await workspace.checkPackageGraph(roots: [rootName]) { modulesGraph, diagnostics in
            XCTAssertTrue(diagnostics.filter({ $0.severity == .error || $0.severity == .warning }).isEmpty)
            let rootPackage = try XCTUnwrap(modulesGraph.rootPackages.first)
            try checkSettings(rootPackage, "FooMacros", "600.0.1")
            try checkSettings(rootPackage, "FooTests", "600.0.1")
            try checkSettings(rootPackage, "Foo", nil)
            try checkSettings(rootPackage, "FooClient", nil)
        }

        // Change the version of swift syntax to one that doesn't have prebuilts
        try workspace.closeWorkspace(resetState: false, resetResolvedFile: false)
        let key = MockManifestLoader.Key(url: sandbox.appending(components: "roots", rootName).pathString)
        let oldManifest = try XCTUnwrap(workspace.manifestLoader.manifests[key])
        let oldSCM: PackageDependency.SourceControl
        if case let .sourceControl(scm) = oldManifest.dependencies[0] {
            oldSCM = scm
        } else {
            XCTFail("not source control")
            return
        }
        let newDep = PackageDependency.sourceControl(
            identity: oldSCM.identity,
            nameForTargetDependencyResolutionOnly: oldSCM.nameForTargetDependencyResolutionOnly,
            location: oldSCM.location,
            requirement: .exact(try XCTUnwrap(Version("601.0.0"))),
            productFilter: oldSCM.productFilter
        )
        let newManifest = oldManifest.with(dependencies: [newDep])
        workspace.manifestLoader.manifests[key] = newManifest

        try await workspace.checkPackageGraph(roots: [rootName]) { modulesGraph, diagnostics in
            XCTAssertTrue(diagnostics.filter({ $0.severity == .error || $0.severity == .warning }).isEmpty)
            let rootPackage = try XCTUnwrap(modulesGraph.rootPackages.first)
            try checkSettings(rootPackage, "FooMacros", nil)
            try checkSettings(rootPackage, "FooTests", nil)
            try checkSettings(rootPackage, "Foo", nil)
            try checkSettings(rootPackage, "FooClient", nil)
        }

        // Change it back
        try workspace.closeWorkspace(resetState: false, resetResolvedFile: false)
        workspace.manifestLoader.manifests[key] = oldManifest

        try await workspace.checkPackageGraph(roots: [rootName]) { modulesGraph, diagnostics in
            XCTAssertTrue(diagnostics.filter({ $0.severity == .error || $0.severity == .warning }).isEmpty)
            let rootPackage = try XCTUnwrap(modulesGraph.rootPackages.first)
            try checkSettings(rootPackage, "FooMacros", "600.0.1")
            try checkSettings(rootPackage, "FooTests", "600.0.1")
            try checkSettings(rootPackage, "Foo", nil)
            try checkSettings(rootPackage, "FooClient", nil)
        }
    }

    func testSSHURL() async throws {
        let sandbox = AbsolutePath("/tmp/ws")
        let fs = InMemoryFileSystem()

        let httpClient = HTTPClient { request, progressHandler in
            guard case .download(let fileSystem, let destination) = request.kind else {
                throw StringError("invalid request \(request.kind)")
            }

            if request.url == "https://download.swift.org/prebuilts/swift-syntax/600.0.1/\(self.swiftVersion)-MacroSupport-macos_aarch64.zip" {
                try fileSystem.writeFileContents(destination, data: Data())
                return .okay()
             } else {
                XCTFail("Unexpected URL \(request.url)")
                return .notFound()
            }
        }

        let archiver = MockArchiver(handler: { _, archivePath, destination, completion in
            XCTAssertEqual(archivePath.pathString, "/tmp/ws/.build/prebuilts/swift-syntax/600.0.1/\(self.swiftVersion)-MacroSupport-macos_aarch64.zip".fixwin)
            XCTAssertEqual(destination.pathString, "/tmp/ws/.build/prebuilts/swift-syntax/600.0.1/\(self.swiftVersion)-MacroSupport-macos_aarch64".fixwin)
            completion(.success(()))
        })

        let workspace = try await initWorkspace(
            fs: fs,
            sandbox: sandbox,
            httpClient: httpClient,
            archiver: archiver,
            swiftSyntaxVersion: "600.0.1",
            swiftSyntaxURL: "git@github.com:swiftlang/swift-syntax.git"
        )

        try await workspace.checkPackageGraph(roots: ["Foo"]) { modulesGraph, diagnostics in
            XCTAssertTrue(diagnostics.filter({ $0.severity == .error }).isEmpty)
            let rootPackage = try XCTUnwrap(modulesGraph.rootPackages.first)
            try checkSettings(rootPackage, "FooMacros", "600.0.1")
            try checkSettings(rootPackage, "FooTests", "600.0.1")
            try checkSettings(rootPackage, "Foo", nil)
            try checkSettings(rootPackage, "FooClient", nil)
        }
    }

    func testCachedArtifact() async throws {
        let sandbox = AbsolutePath("/tmp/ws")
        let fs = InMemoryFileSystem()

        let artifact = Data()
        let cacheFile = try AbsolutePath(validating: "/home/user/caches/org.swift.swiftpm/prebuilts/swift-syntax/600.0.1/\(self.swiftVersion)-MacroSupport-macos_aarch64.zip")
        try fs.writeFileContents(cacheFile, data: artifact)

        let httpClient = HTTPClient { request, progressHandler in
            guard case .download(let fileSystem, let destination) = request.kind else {
                throw StringError("invalid request \(request.kind)")
            }

            if request.url == "https://download.swift.org/prebuilts/swift-syntax/600.0.1/\(self.swiftVersion)-MacroSupport-macos_aarch64.zip" {
                XCTFail("Unexpect download of archive")
                try fileSystem.writeFileContents(destination, data: artifact)
                return .okay()
             } else {
                XCTFail("Unexpected URL \(request.url)")
                return .notFound()
            }
        }

        let archiver = MockArchiver(handler: { _, archivePath, destination, completion in
            XCTAssertEqual(archivePath.pathString, "/tmp/ws/.build/prebuilts/swift-syntax/600.0.1/\(self.swiftVersion)-MacroSupport-macos_aarch64.zip".fixwin)
            XCTAssertEqual(destination.pathString, "/tmp/ws/.build/prebuilts/swift-syntax/600.0.1/\(self.swiftVersion)-MacroSupport-macos_aarch64".fixwin)
            completion(.success(()))
        })

        let workspace = try await initWorkspace(
            fs: fs,
            sandbox: sandbox,
            httpClient: httpClient,
            archiver: archiver,
            swiftSyntaxVersion: "600.0.1"
        )

        try await workspace.checkPackageGraph(roots: [rootName]) { modulesGraph, diagnostics in
            XCTAssertTrue(diagnostics.filter({ $0.severity == .error }).isEmpty)
            let rootPackage = try XCTUnwrap(modulesGraph.rootPackages.first)
            try checkSettings(rootPackage, "FooMacros", "600.0.1")
            try checkSettings(rootPackage, "FooTests", "600.0.1")
            try checkSettings(rootPackage, "Foo", nil)
            try checkSettings(rootPackage, "FooClient", nil)
        }
    }

    func testUnsupportedSwiftSyntaxVersion() async throws {
        let sandbox = AbsolutePath("/tmp/ws")
        let fs = InMemoryFileSystem()
        let secondFetch = SendableBox(false)

        let httpClient = HTTPClient { request, progressHandler in
            if request.url == "https://download.swift.org/prebuilts/swift-syntax/600.0.2/\(self.swiftVersion)-MacroSupport-macos_aarch64.zip" {
                let secondFetch = await secondFetch.value
                XCTAssertFalse(secondFetch, "unexpected second fetch")
                return .notFound()
            } else {
                XCTFail("Unexpected URL \(request.url)")
                return .notFound()
            }
        }

        let archiver = MockArchiver(handler: { _, archivePath, destination, completion in
            XCTFail("Unexpected call to archiver")
            completion(.success(()))
        })

        let workspace = try await initWorkspace(
            fs: fs,
            sandbox: sandbox,
            httpClient: httpClient,
            archiver: archiver,
            swiftSyntaxVersion: "600.0.2"
        )

        try await workspace.checkPackageGraph(roots: ["Foo"]) { modulesGraph, diagnostics in
            XCTAssertTrue(diagnostics.filter({ $0.severity == .error }).isEmpty)
            let rootPackage = try XCTUnwrap(modulesGraph.rootPackages.first)
            try checkSettings(rootPackage, "FooMacros", nil)
            try checkSettings(rootPackage, "FooTests", nil)
            try checkSettings(rootPackage, "Foo", nil)
            try checkSettings(rootPackage, "FooClient", nil)
        }

        await secondFetch.set(true)

        try await workspace.checkPackageGraph(roots: ["Foo"]) { modulesGraph, diagnostics in
            XCTAssertTrue(diagnostics.filter({ $0.severity == .error }).isEmpty)
            let rootPackage = try XCTUnwrap(modulesGraph.rootPackages.first)
            try checkSettings(rootPackage, "FooMacros", nil)
            try checkSettings(rootPackage, "FooTests", nil)
            try checkSettings(rootPackage, "Foo", nil)
            try checkSettings(rootPackage, "FooClient", nil)
        }
    }

    func testUnsupportedArch() async throws {
        let sandbox = AbsolutePath("/tmp/ws")
        let fs = InMemoryFileSystem()

        let httpClient = HTTPClient { request, progressHandler in
            guard case .download(let fileSystem, _) = request.kind else {
                throw StringError("invalid request \(request.kind)")
            }

            XCTFail("Unexpected URL \(request.url)")
            return .notFound()
        }

        let archiver = MockArchiver(handler: { _, archivePath, destination, completion in
            XCTFail("Unexpected call to archiver")
            completion(.success(()))
        })

        let workspace = try await initWorkspace(
            fs: fs,
            sandbox: sandbox,
            httpClient: httpClient,
            archiver: archiver,
            swiftSyntaxVersion: "600.0.1",
            triple: Triple("86_64-unknown-linux-gnu")
        )

        try await workspace.checkPackageGraph(roots: [rootName]) { modulesGraph, diagnostics in
            XCTAssertTrue(diagnostics.filter({ $0.severity == .error }).isEmpty)
            let rootPackage = try XCTUnwrap(modulesGraph.rootPackages.first)
            try checkSettings(rootPackage, "FooMacros", nil)
            try checkSettings(rootPackage, "FooTests", nil)
            try checkSettings(rootPackage, "Foo", nil)
            try checkSettings(rootPackage, "FooClient", nil)
        }
    }

    func testUnsupportedSwiftVersion() async throws {
        let sandbox = AbsolutePath("/tmp/ws")
        let fs = InMemoryFileSystem()

        let httpClient = HTTPClient { request, progressHandler in
            if request.url == "https://download.swift.org/prebuilts/swift-syntax/600.0.1/\(self.swiftVersion)-MacroSupport-macos_aarch64.zip" {
                // Pretend we're a different swift version
                return .notFound()
             } else {
                XCTFail("Unexpected URL \(request.url)")
                return .notFound()
            }
        }

        let archiver = MockArchiver(handler: { _, archivePath, destination, completion in
            XCTFail("Unexpected call to archiver")
            completion(.success(()))
        })

        let workspace = try await initWorkspace(
            fs: fs,
            sandbox: sandbox,
            httpClient: httpClient,
            archiver: archiver,
            swiftSyntaxVersion: "600.0.1"
        )

        try await workspace.checkPackageGraph(roots: [rootName]) { modulesGraph, diagnostics in
            XCTAssertTrue(diagnostics.filter({ $0.severity == .error }).isEmpty)
            let rootPackage = try XCTUnwrap(modulesGraph.rootPackages.first)
            try checkSettings(rootPackage, "FooMacros", nil)
            try checkSettings(rootPackage, "FooTests", nil)
            try checkSettings(rootPackage, "Foo", nil)
            try checkSettings(rootPackage, "FooClient", nil)
        }
    }

    func testDisabled() async throws {
        let sandbox = AbsolutePath("/tmp/ws")
        let fs = InMemoryFileSystem()

        let workspace = try await initWorkspace(
            fs: fs,
            sandbox: sandbox,
            httpClient: nil,
            archiver: nil,
            swiftSyntaxVersion: "600.0.1"
        )

        try await workspace.checkPackageGraph(roots: ["Foo"]) { modulesGraph, diagnostics in
            XCTAssertTrue(diagnostics.filter({ $0.severity == .error }).isEmpty)
            let rootPackage = try XCTUnwrap(modulesGraph.rootPackages.first)
            try checkSettings(rootPackage, "FooMacros", nil)
            try checkSettings(rootPackage, "FooTests", nil)
            try checkSettings(rootPackage, "Foo", nil)
            try checkSettings(rootPackage, "FooClient", nil)
        }
    }
}

extension String {
    var fixwin: String {
        #if os(Windows)
        return self.replacingOccurrences(of: "/", with: "\\")
        #else
        return self
        #endif
    }
}
