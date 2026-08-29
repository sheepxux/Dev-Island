# App Bundle Dependency Closure

Dev Island treats the packaged `.app`, rather than a successful Swift build,
as the release boundary. A binary can compile and sign correctly while still
terminating in `dyld` before application code runs if a framework is absent,
thin, unreachable through its runpaths, or linked to a developer-machine path.

## Enforced contract

`scripts/release/verify-app-bundle-dependencies.rb --app PATH` walks every
regular file under `Contents`, discovers every Mach-O image, and fails unless:

- the bundle contains a main Mach-O executable under `Contents/MacOS`;
- every executable, framework binary, XPC service, app helper, and dynamic
  library contains exactly `arm64` and `x86_64`;
- every non-system install name resolves to an existing Mach-O inside the
  bundle through a supported `@rpath`, `@loader_path`, or
  `@executable_path` chain;
- no dependency or runtime search path points to Homebrew, Xcode, another
  absolute developer location, an unknown token, or outside the bundle; and
- every bundle symlink has a non-dangling real target that remains inside the
  root `.app`.

System-path checks normalize `.` and `..` components before applying the
macOS allowlist. Merely naming a text file `.dylib` does not satisfy the
dependency contract.

## Where it runs

- `scripts/build-app.sh` removes the known Xcode-only Swift runtime rpath,
  rejects any unknown rpath, and verifies the completed bundle before its
  local ad-hoc signature.
- Pull-request CI runs the attack fixtures and repeats the verifier against
  the actual production-mode Universal app.
- Tagged releases run the fixtures before loading release credentials, then
  repeat dependency verification after the app build and before Developer ID
  signing, notarization, packaging, or publication.
- `verify-security-invariants.sh` and `verify-release-foundation.sh` pin these
  workflow boundaries so the checks cannot silently disappear.

## Negative fixtures

Run:

```sh
./scripts/ci/verify-app-bundle-dependencies.sh
```

The suite builds a valid two-architecture app fixture, proves it passes, and
then proves rejection of:

1. a missing bundled dynamic library;
2. a single-architecture executable;
3. a Homebrew absolute dependency;
4. an absolute dependency disguised with a `/usr/lib/../..` prefix;
5. an Xcode/developer-machine runtime search path;
6. an escaping `@loader_path` dependency;
7. a non-Mach-O file substituted for a dynamic library; and
8. a dangling or bundle-escaping symbolic link.

## Release limitation

This gate proves static architecture and loader closure for the bytes in one
bundle. It does not replace Developer ID signing, Apple notarization,
Gatekeeper assessment, a real Launch Services cold start, or an installed
old-to-new Sparkle update. Those remain separate release acceptance gates.
