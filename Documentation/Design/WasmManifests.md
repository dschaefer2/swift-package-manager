# WASM Manifest Experiment
As the Swift Package ecosystem grows, we need to have a cross-platform sandboxing technique to ensure package manifests and plugin scripts are executed in secure environments. WASM with the help of WasmKit has the potential to provide that.
This experiment was to first get a feel for what it would take to compile the package manifest for Wasm and load it up in an embedded WasmKit in SwiftPM. But the main task was to get a feel for performance. There already is concern for package manifest loading times, how much slower would it be to compile them for Wasm, link them into a static binary, and executed to extract the manifest.
## Lessons Learned
It is indeed slower.
- On my MBP, it takes on average 250 milliseconds to compile a manifest natively and another 250 milliseconds to run it and load up the manifest JSON file.
- For Wasm, I was seeing around 1000 milliseconds to compile and link, around 350 millliseconds to load it into WasmKit, and another 650 milliseconds to get the JSON file written.

Linking Foundation takes a long time and produces a huge 60MB binary.
- Turns out there's only one function we use out of the full Foundation.
- Removing use of that function I was able to build cut the dependency down to only FoundationEssentials
- That resulted in a slightly faster compile and a 20MB binary which improved load time.

## Things for Further Study
Is the performance cost worth the slightly slower performance (relative to a whole build, for example).
- My gut says it probably is.

Can we optimize the interface and serialization when transfering the package description from WasmKit into SwiftPM
- Looks like there are efficient ways of transfering buffers from WasmKit
- We don't really need JSON, what would be an alternative that would be faster?

If we do decide to go this way, we need to get the WASM Swift SDK into the toolchain
We need to keep the current mechanism around as a fallback. Many packages use things out of the platform SDKs which may not be available in the WASM SDK.
- Also what happens if they depend on Foundation, we would need to detect that and add libraries to the link line, or always add them and rely on dead code elimination?

Plugins scripts could also use a cross-platform sandbox. We have plans to move plugin invocation into the package resolution phase which would give it the same security requirements as package manifests.
- Would build plugin tools, i.e. the executable targets that plugins add to the build graph in Commands, benefit from this as well, or would that be overly constraining and have a bigger hit on performance?
