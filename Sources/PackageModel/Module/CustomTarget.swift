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

import Basics

public final class CustomTarget: Module {
    public override class var typeDescription: String { "customTarget" }

    public init(
        name: String,
        path: AbsolutePath,
        dependencies: [Module.Dependency] = [],
        buildSettings: BuildSettings.AssignmentTable = .init(),
        buildSettingsDescription: [TargetBuildSettingDescription.Setting] = [],
        pluginSettings: [Dependency.ID: [PluginSetting]] = [:]
    ) {
        super.init(
            name: name,
            type: .custom,
            path: path,
            sources: .init(paths: [], root: path),
            dependencies: dependencies,
            packageAccess: true,
            buildSettings: buildSettings,
            buildSettingsDescription: buildSettingsDescription,
            pluginSettings: pluginSettings,
            usesUnsafeFlags: false,
            implicit: false
        )
    }
}
