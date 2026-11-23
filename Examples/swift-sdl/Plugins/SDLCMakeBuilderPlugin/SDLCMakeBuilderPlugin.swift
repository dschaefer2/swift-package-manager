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
import PackagePlugin
import Foundation

@main
struct CMakeBuilderPlugin: BuildToolPlugin {
    func createBuildCommands(
        context: PluginContext,
        target: Target,
        pluginSettings: [PluginSetting]
    ) async throws -> [Command] {
        let builder = try context.tool(named: "SDLCMakeBuilder")
        let buildSubDir = "$(CONFIGURATION)-$(PLATFORM)"
        let buildDir = context.pluginWorkDirectoryURL.appending(path: buildSubDir)
        let sdlArchive = buildDir.appending(path: "libSDL3.a")
        let sdlLib = buildDir.appending(path: "SDL3-static.lib")
        let sdlJar = buildDir.appending(path: "SDL3.jar")

        var environment = ["HOME": ProcessInfo.processInfo.environment["HOME"]!]
        if let developerDir = ProcessInfo.processInfo.environment["DEVELOPER_DIR"] {
            environment["DEVELOPER_DIR"] = developerDir
        }

        let arguments = [
            "--output-dir", buildDir.path,
            "--sysroot", "$(SYSROOT)",
            "--triple", "$(TRIPLE)",
            target.directoryURL.path,
        ]

        return [
            .buildCommand(
                displayName: "CMake Build",
                executable: builder.url,
                arguments: arguments,
                environment: environment,
                outputFiles: [sdlArchive],
                alwaysOutOfDate: true,
                .when(platforms: [.macOS])
            ),
            .buildCommand(
                displayName: "CMake Build",
                executable: builder.url,
                arguments: arguments,
                environment: environment,
                outputFiles: [sdlLib],
                alwaysOutOfDate: true,
                .when(platforms: [.windows])
            ),
            .buildCommand(
                displayName: "CMake Build",
                executable: builder.url,
                arguments: arguments,
                environment: environment,
                outputFiles: [sdlArchive, sdlJar],
                alwaysOutOfDate: true,
                .when(platforms: [.android])
            ),
            .targetInfo(
                cSettings: [
                    .headerSearchPath("include", usage: .public),
                ],
                linkerSettings: [
                    .librarySearchPath(buildSubDir)
                ],
                targetSettings: [
                    .setting(name: "SDL3_DIR", value: buildDir.path),
                    .setting(name: "SDL3_JAR", value: sdlJar.path, .when(platforms: [.android])),
                ]
            )
        ]
    }
}
