
# Extending Plugins and External Targets
## Requirements
There are a number of use cases we'd like to extend plugins to support:
- Generating arbitrary outputs
  - Not just source as we have is today
  - Include object code that can be linked with standard Clang/Swift objects
- Incorporate knowledge of the build request
  - Enable plugins to generate commands with knowledge of
    - The triple(s) components
    - The SDK
    - The build configuration
- Provide an intermediate directory for outputs
    - For given combinations of build request properties
- Enable them to copy results to the build products directory
    - Make them available with -show-bin-path
    - So that dependent targets can find the results
- Allow to be the sole provider of the build for a target
    - If a target has no source, headers, modulemap that would map it into a traditional target
- But also apply to traditional targets
    - can product traditional products as well as custom ones
- Allow plugins to specify platform independent commands for "copy" and "touch"

Introduce a new target type, similar to binary targets, but allows incorporating a non-Swift source or binary tree
- Target specifies location for source
    - Local file system, allow outside package
    - Source control, including version ranges
    - Remote source archive with checksum
- Target can also specify location for binaries
    - Remote binary archive with checksum
    - Selected based on condition
- Uses the plugin extensions above to perform any steps necessary to get products in to the products directory.
- Specifies build settings like public header file path needed for consuming targets

External library target to incorporate library products into rest of build.
    - Similar to system libraries except library is located in the build products directory

External executable target to incorporate executable products into rest of build, including use by build tool plugins.
## Design
Introduce variables that can be used in the strings/URLs when the plugin defines a Command
- e.g. `$(SDKROOT)
- Looks like SwiftBuild build setting macros but they're not
    - But can map to them when creating the CustomTask
    - Lets us control what is visible and produce more ergonomic names for them
    - (Also closes a hole where they can sneak in now)
- Add variables for the build products and intermediates directory so the plugins can place files in build specific directories
- provide variables from the copy command and the touch command
    - To copy files to the build products directory
    - To update timestamp on marker files to allow for variable output file list
    - May want more in the future

Add a new `Module` type for non-source targets, i.e. Not Swift or Clang modules.
- Generate AggregateTargets for these and add the CustomTargets for each plugin usage

Add a module type for external targets
- Manages download of archive or checkout of source
- Can we get this at build request time so we only download archives we need

Add module type for external libraries
- Hooks up the library with the same name from a external target dependency

Add module type for external executable.
- Adds the executable to the model.
## Examples
To help confirm we have the desired capability and ergonomics, we'll produce examples in the Examples directory.
- Simple Java compile, produce jar from classes
- SDL that includes an executable that shows calls into SDL working
    - Builds for host and for Android including creating an APK

## Future Work
Can we use external binary targets to generalize prebuilts?
    - Somehow associate an external source target with a list of external binary targets that are prebuilts of the source target.
- If one of the binary targets have successful target conditions, use it, otherwise use the source target

We might want to make the binary target support future work as well until we can figure that out. Source would be fine for now.
