//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation
import Basics
import PackageModel
import SourceControl
import TSCBasic
import TSCUtility
import WasmKit
import WasmKitWASI
import WASI
import SystemPackage

public final class WASMManifestLoader: ManifestLoaderProtocol {
    public typealias Delegate = Int

    private let toolchain: UserToolchain

    public init(
        toolchain: UserToolchain,
        serializedDiagnostics: Bool = false,
        isManifestSandboxEnabled: Bool = true,
        useInMemoryCache: Bool = true,
        cacheDir: Basics.AbsolutePath? = .none,
        extraManifestFlags: [String]? = .none,
        importRestrictions: (startingToolsVersion: ToolsVersion, allowedImports: [String])? = .none,
        delegate: Delegate? = .none,
        pruneDependencies: Bool = false
    ) {
        self.toolchain = toolchain
    }

    public func load(
        manifestPath: Basics.AbsolutePath,
        manifestToolsVersion: ToolsVersion,
        packageIdentity: PackageIdentity,
        packageKind: PackageReference.Kind,
        packageLocation: String,
        packageVersion: (version: Version?, revision: String?)?,
        identityResolver: any IdentityResolver,
        dependencyMapper: any DependencyMapper,
        fileSystem: any FileSystem,
        observabilityScope: ObservabilityScope,
        delegateQueue: DispatchQueue
    ) async throws -> PackageModel.Manifest {
        var cmd: [String] = []
        cmd += [self.toolchain.swiftCompilerPathForManifests.pathString]

        cmd += [
            "-package-description-version", manifestToolsVersion.description,
            "-I", "/Users/dschaefer2/swift/work/wasmManifests/swift-package-manager/.build/out/Products/Debug-webassembly-wasm32",
            "-L", "/Users/dschaefer2/swift/work/wasmManifests/swift-package-manager/.build/out/Products/Debug-webassembly-wasm32",
            "-lPackageDescription",
            "-lswiftSwiftOnoneSupport",
            "-lswiftCore",
            "-lswiftObservation",
            "-lswift_Concurrency",
            "-lswift_StringProcessing",
            "-lswift_RegexParser",
            "-lswiftSynchronization",
            "-lswiftWASILibc",
            "-lFoundationEssentials",
            "-l_FoundationCShims",
            "-l_FoundationCollections",
            "-lwasi-emulated-getpid",
            "-lwasi-emulated-mman",
            "-lwasi-emulated-signal",
            "-target", "wasm32-unknown-wasip1",
            "-sdk", "/Users/dschaefer2/Library/org.swift.swiftpm/swift-sdks/swift-6.4.x-DEVELOPMENT-SNAPSHOT-2026-08-14-a_wasm.artifactbundle/swift-6.4.x-DEVELOPMENT-SNAPSHOT-2026-08-14-a_wasm/wasm32-unknown-wasip1/WASI.sdk",
            "-static-stdlib",
            "-resource-dir",
            "/Users/dschaefer2/Library/org.swift.swiftpm/swift-sdks/swift-6.4.x-DEVELOPMENT-SNAPSHOT-2026-08-14-a_wasm.artifactbundle/swift-6.4.x-DEVELOPMENT-SNAPSHOT-2026-08-14-a_wasm/wasm32-unknown-wasip1/swift.xctoolchain/usr/lib/swift_static",
            "-Xclang-linker", "-resource-dir",
            "-Xclang-linker",
            "/Users/dschaefer2/Library/org.swift.swiftpm/swift-sdks/swift-6.4.x-DEVELOPMENT-SNAPSHOT-2026-08-14-a_wasm.artifactbundle/swift-6.4.x-DEVELOPMENT-SNAPSHOT-2026-08-14-a_wasm/wasm32-unknown-wasip1/swift.xctoolchain/usr/lib/swift_static/clang",
        ]

        cmd += [manifestPath._normalized]

        // Compile the manifest in a temporary directory
        return try await Basics.withTemporaryDirectory(removeTreeOnDeinit: true) { tmpDir in
            let compiledManifestFile = tmpDir.appending("\(packageIdentity)-manifest.wasm")
            cmd += ["-o", compiledManifestFile.pathString]

            // Compile the manifest.
            let compileStart = Date.now
            let compilerResult = try await AsyncProcess.popen(arguments: cmd, environment: self.toolchain.swiftCompilerEnvironment)
            let compileDuration = Date.now.timeIntervalSince(compileStart)
            print(compiledManifestFile, "duration: \(compileDuration)s")
            print(try (compilerResult.utf8Output() + compilerResult.utf8stderrOutput()).spm_chuzzle() ?? "")

            // Set up the args
            let jsonOutputFile = tmpDir.appending("\(packageIdentity)-output.json")
            print(jsonOutputFile.pathString)
            var runCmd = [compiledManifestFile.pathString]
            #if os(Windows)
            // NOTE: `_get_osfhandle` returns a non-owning, unsafe,
            // unretained HANDLE.  DO NOT invoke `CloseHandle` on `hFile`.
            let hFile: Int = _get_osfhandle(_fileno(jsonOutputFileDesc))
            runCmd += ["-handle", "\(String(hFile, radix: 16))"]
            #else
            runCmd += ["-file", jsonOutputFile.pathString]
            #endif

            do {
                let packageDirectory = manifestPath.parentDirectory.pathString

                let gitInformation: ContextModel.GitInformation?
                do {
                    let repo = GitRepository(path: manifestPath.parentDirectory)
                    async let tag = repo.getCurrentTag()
                    async let commit = try repo.getCurrentRevision().identifier
                    async let uncommitted = repo.hasUncommittedChanges()
                    gitInformation = try await ContextModel.GitInformation(
                        currentTag: tag,
                        currentCommit: commit,
                        hasUncommittedChanges: uncommitted
                    )
                } catch {
                    // Ignore errors getting git info
                    gitInformation = nil
                }

                let contextModel = ContextModel(
                    packageDirectory: packageDirectory,
                    gitInformation: gitInformation
                )
                runCmd += ["-context", try contextModel.encode()]
            } catch {
                throw error // Re-throw encoding errors
            }

            do {
                let wasi = try WASIBridgeToHost(
                    args: runCmd,
                    preopens: [
                        .init(guestPath: "/", hostPath: "/"),
                    ],
                )

                let loadStart = Date.now
                guard let wasm = FileManager.default.contents(atPath: compiledManifestFile.pathString) else {
                    fatalError("compiled manifest not found")
                }
                let module = try parseWasm(bytes: Array(wasm))
                let engine = Engine()
                let store = Store(engine: engine)
                var imports = Imports()
                wasi.link(to: &imports, store: store)

                let instance = try module.instantiate(store: store, imports: imports)
                print("loaded duration: \(Date.now.timeIntervalSince(loadStart))s")
                let runStart = Date.now
                let exitCode = try wasi.start(instance)
                print("exitCode:", exitCode, "duration: \(Date.now.timeIntervalSince(runStart))s")
                try wasi.close()
            } catch {
                print(error.localizedDescription)
            }
            fatalError()
        }
    }

    public func resetCache(observabilityScope: Basics.ObservabilityScope) async {
    }
    
    public func purgeCache(observabilityScope: Basics.ObservabilityScope) async {
    }
}
