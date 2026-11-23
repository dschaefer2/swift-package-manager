//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2022 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation

/// A platform supported by Swift Package Manager.
@available(_PackageDescription, introduced: 999.0)
public struct Platform: Equatable, Sendable {

    /// The name of the platform.
    let name: String

    init(name: String) {
        self.name = name
    }

    /// Creates a custom platform.
    ///
    /// Use this function if none of the predefined platform names match the platform you are targeting.
    /// - Parameter platformName: The name of the platform.
    /// - Returns: A `Platform` instance.
    @available(_PackageDescription, introduced: 5.6)
    public static func custom(_ platformName: String) -> Platform {
        return Platform(name: platformName)
    }

    /// The macOS platform.
    public static let macOS: Platform = Platform(name: "macos")

    /// The Mac Catalyst platform.
    public static let macCatalyst: Platform = Platform(name: "maccatalyst")

    /// The iOS platform.
    public static let iOS: Platform = Platform(name: "ios")

    /// The tvOS platform.
    public static let tvOS: Platform = Platform(name: "tvos")

    /// The watchOS platform.
    public static let watchOS: Platform = Platform(name: "watchos")

    /// The visionOS platform.
    public static let visionOS: Platform = Platform(name: "visionos")

    /// The DriverKit platform
    public static let driverKit: Platform = Platform(name: "driverkit")

    /// The Linux platform.
    public static let linux: Platform = Platform(name: "linux")

    /// The Windows platform.
    @available(_PackageDescription, introduced: 5.2)
    public static let windows: Platform = Platform(name: "windows")

    /// The Android platform.
    @available(_PackageDescription, introduced: 5.2)
    public static let android: Platform = Platform(name: "android")

    /// The WebAssembly System Interface platform.
    @available(_PackageDescription, introduced: 5.3)
    public static let wasi: Platform = Platform(name: "wasi")

    /// The OpenBSD platform.
    @available(_PackageDescription, introduced: 5.8)
    public static let openbsd: Platform = Platform(name: "openbsd")

    /// The FreeBSD platform.
    @available(_PackageDescription, introduced: 999.0)
    public static let freebsd: Platform = Platform(name: "freebsd")

    /// Any Apple platform.
    @available(_PackageDescription, introduced: 999.0)
    public static let anyAppleOS: Platform = Platform(name: "anyappleos")
}

/// The build configuration, such as debug or release.
@available(_PackageDescription, introduced: 999.0)
public struct BuildConfiguration: Sendable {
    /// The configuration of the build. Valid values are `debug` and `release`.
    let config: String

    init(_ config: String) {
        self.config = config
    }

    /// The debug build configuration.
    public static let debug: BuildConfiguration = BuildConfiguration("debug")

    /// The release build configuration.
    public static let release: BuildConfiguration = BuildConfiguration("release")
}

/// A condition that limits the application of a build setting.
///
/// By default, build settings are applicable for all platforms and build
/// configurations. Use the `.when` modifier to define a build setting for a
/// specific condition. Invalid usage of `.when` emits an error during manifest
/// parsing. For example, it's invalid to specify a `.when` condition with both
/// parameters as `nil`.
///
/// The following example shows how to use build setting conditions with various
/// APIs:
///
/// ```swift
/// ...
/// .target(
///     name: "MyTool",
///     dependencies: ["Utility"],
///     cSettings: [
///         .headerSearchPath("path/relative/to/my/target"),
///         .define("DISABLE_SOMETHING", .when(platforms: [.iOS], configuration: .release)),
///     ],
///     swiftSettings: [
///         .define("ENABLE_SOMETHING", .when(configuration: .release)),
///     ],
///     linkerSettings: [
///         .linkedLibrary("openssl", .when(platforms: [.linux])),
///     ]
/// ),
/// ```
@available(_PackageDescription, introduced: 999.0)
public struct BuildSettingCondition: Sendable {
    /// The applicable platforms for this build setting condition.
    let platforms: [Platform]?
    /// The applicable build configuration for this build setting condition.
    let config: BuildConfiguration?

    init(platforms: [Platform]?, config: BuildConfiguration?) {
        self.platforms = platforms
        self.config = config
    }

    @available(_PackageDescription, deprecated: 5.7)
    public static func when(
        platforms: [Platform]? = nil,
        configuration: BuildConfiguration? = nil
    ) -> BuildSettingCondition {
        precondition(!(platforms == nil && configuration == nil))
        return BuildSettingCondition(platforms: platforms, config: configuration)
    }

    /// Creates a build setting condition.
    ///
    /// - Parameters:
    ///   - platforms: The applicable platforms for this build setting condition.
    ///   - configuration: The applicable build configuration for this build setting condition.
    @available(_PackageDescription, introduced: 5.7)
    public static func when(platforms: [Platform], configuration: BuildConfiguration) -> BuildSettingCondition {
        BuildSettingCondition(platforms: platforms, config: configuration)
    }

    /// Creates a build setting condition.
    ///
    /// - Parameter platforms: The applicable platforms for this build setting condition.
    @available(_PackageDescription, introduced: 5.7)
    public static func when(platforms: [Platform]) -> BuildSettingCondition {
        BuildSettingCondition(platforms: platforms, config: .none)
    }

    /// Creates a build setting condition.
    ///
    /// - Parameter configuration: The applicable build configuration for this build setting condition.
    @available(_PackageDescription, introduced: 5.7)
    public static func when(configuration: BuildConfiguration) -> BuildSettingCondition {
        BuildSettingCondition(platforms: .none, config: configuration)
    }
}

@available(_PackageDescription, introduced: 999.0)
public enum BuildSettingUsage: Sendable {
    /// The setting is used only by the target
    case `private`

    /// The setting is used by the target and imparted to dependents that link with that target
    case `public`

    /// The setting is only used by dependents
    case interface
}

/// The underlying build setting data.
struct BuildSettingData {
    /// The name of the build setting.
    let name: String

    /// The value of the build setting.
    let value: [String]

    /// How the build setting is used by the target and/or it's dependents.
    let usage: BuildSettingUsage?

    /// A condition that restricts the application of the build setting.
    let condition: BuildSettingCondition?
}

/// A C language build setting.
@available(_PackageDescription, introduced: 999.0)
public struct CSetting: Sendable {
    /// The abstract build setting data.
    let data: BuildSettingData

    private init(name: String, value: [String], usage: BuildSettingUsage? = nil, condition: BuildSettingCondition?) {
        self.data = BuildSettingData(name: name, value: value, usage: usage, condition: condition)
    }

    /// Provides a header search path relative to the plugin output directory.
    ///
    /// Use this setting to add a search path for headers for your target
    /// and it's link dependencies. You can't use absolute paths and
    /// the path must be a directory inside the plugin output directory.
    ///
    /// - Since: First available in PackageDescription 6.5.
    ///
    /// - Parameters:
    ///   - path: The path of the directory that contains the headers. The path is relative to the target's directory.
    ///   - usage: Where the path is used either by the target itself, it's transitive link dependencies or both.
    ///   - condition: A condition that restricts the use of the build setting.
    @available(_PackageDescription, introduced: 999.0)
    public static func headerSearchPath(_ path: String, usage: BuildSettingUsage, _ condition: BuildSettingCondition? = nil) -> CSetting {
        return CSetting(name: "headerSearchPath", value: [path], usage: usage, condition: condition)
    }
}

/// A CXX-language build setting.
@available(_PackageDescription, introduced: 999.0)
public struct CXXSetting: Sendable {
    /// The data store for the CXX build setting.
    let data: BuildSettingData

    private init(name: String, value: [String], usage: BuildSettingUsage? = nil, condition: BuildSettingCondition?) {
        self.data = BuildSettingData(name: name, value: value, usage: usage, condition: condition)
    }

    /// Provides a header search path relative to the plugin output directory.
    ///
    /// Use this setting to add a search path for headers for your target
    /// and it's link dependencies. You can't use absolute paths and
    /// the path must be a directory inside the plugin output directory.
    ///
    /// - Since: First available in PackageDescription 6.5.
    ///
    /// - Parameters:
    ///   - path: The path of the directory that contains the headers. The path is relative to the target's directory.
    ///   - usage: Where the path is used either by the target itself, it's transitive link dependencies or both.
    ///   - condition: A condition that restricts the use of the build setting.
    @available(_PackageDescription, introduced: 999.0)
    public static func headerSearchPath(_ path: String, usage: BuildSettingUsage, _ condition: BuildSettingCondition? = nil) -> CXXSetting {
        return CXXSetting(name: "headerSearchPath", value: [path], usage: usage, condition: condition)
    }
}

/// A linker build setting.
public struct LinkerSetting: Sendable {
    /// The data store for the Linker setting.
    let data: BuildSettingData

    private init(name: String, value: [String], usage: BuildSettingUsage? = nil, condition: BuildSettingCondition?) {
        self.data = BuildSettingData(name: name, value: value, usage: usage, condition: condition)
    }

    /// Declares linkage to a system library.
    ///
    /// This setting is most useful when the library can't be linked
    /// automatically, such as C++ based libraries and non-modular libraries.
    ///
    /// - Since: First available in PackageDescription 5.0.
    ///
    /// - Parameters:
    ///   - library: The library name.
    ///   - condition: A condition that restricts the application of the build
    /// setting.
    @available(_PackageDescription, introduced: 5.0)
    public static func linkedLibrary(_ library: String, _ condition: BuildSettingCondition? = nil) -> LinkerSetting {
        return LinkerSetting(name: "linkedLibrary", value: [library], condition: condition)
    }

    @available(_PackageDescription, introduced: 999.0)
    public static func librarySearchPath(_ path: String, _ condition: BuildSettingCondition? = nil) -> LinkerSetting {
        return LinkerSetting(name: "librarySearchPath", value: [path], usage: .public, condition: condition)
    }

    /// Declares linkage to a system framework.
    ///
    /// This setting is most useful when the framework can't be linked
    /// automatically, such as C++ based frameworks and non-modular frameworks.
    ///
    /// - Since: First available in PackageDescription 5.0.
    ///
    /// - Parameters:
    ///   - framework: The framework name.
    ///   - condition: A condition that restricts the application of the build
    /// setting.
    @available(_PackageDescription, introduced: 5.0)
    public static func linkedFramework(_ framework: String, _ condition: BuildSettingCondition? = nil) -> LinkerSetting {
        return LinkerSetting(name: "linkedFramework", value: [framework], condition: condition)
    }

    @available(_PackageDescription, introduced: 999.0)
    public static func frameworkSearchPath(_ path: String, _ condition: BuildSettingCondition? = nil) -> LinkerSetting {
        return LinkerSetting(name: "frameworkSearchPath", value: [path], usage: .public, condition: condition)
    }
}

/// Specifies a build product file produced for a custom target.
@available(_PackageDescription, introduced: 999.0)
public struct BuildProduct: Sendable {
    /// The output file location for the build product
    let url: URL

    /// An optional sub directory in the build product directory to copy the file.
    let subDir: String?

    /// A condition that restricts when this file is available
    let condition: BuildSettingCondition?

    public init(_ url: URL, subDir: String? = nil, _ condition: BuildSettingCondition? = nil) {
        self.url = url
        self.subDir = subDir
        self.condition = condition
    }
}

@available(_PackageDescription, introduced: 999.0)
public struct CommandCondition: Sendable {
    /// The applicable platforms for this build command.
    let platforms: [Platform]?

    private init(platforms: [Platform]?) {
        self.platforms = platforms
    }

    public static func when(
        platforms: [Platform],
    ) -> CommandCondition {
        return CommandCondition(platforms: platforms)
    }
}

/// Parameters passed into the plugin from the package manifest.
@available(_PackageDescription, introduced: 999.0)
public struct PluginSetting: Sendable {
    /// The name of the build setting.
    public var name: String

    /// The value of the build setting.
    public var value: [String]

    /// A condition that restricts the application of the build setting.
    public var condition: BuildSettingCondition?
}

/// Settings the plugin attaches to the target
@available(_PackageDescription, introduced: 999.0)
public struct TargetSetting: Sendable {
    /// The name of the build setting.
    public var name: String

    /// The value of the build setting.
    public var value: [String]

    /// A condition that restricts the application of the build setting.
    public var condition: BuildSettingCondition?

    public init(name: String, value: [String], condition: BuildSettingCondition? = nil) {
        self.name = name
        self.value = value
        self.condition = condition
    }

    public static func setting(name: String, value: String, _ condition: BuildSettingCondition? = nil) -> TargetSetting {
        return TargetSetting(name: name, value: [value], condition: condition)
    }

    public static func setting(name: String, values: [String], _ condition: BuildSettingCondition? = nil) -> TargetSetting {
        return TargetSetting(name: name, value: values, condition: condition)
    }
}
