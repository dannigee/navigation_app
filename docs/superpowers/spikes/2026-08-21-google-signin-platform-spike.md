# Google Sign-In platform spike

**Date:** 2026-08-21
**Decision:** Go for macOS and iOS in phase 4. Linux is not a supported Drive
authentication platform; John must confirm its resulting behavior on Linux
before that phase treats the platform boundary as proven.

## Scope and method

This was a dependency-resolution and native-build spike only. `google_sign_in:
^7.2.0` was temporarily added, resolved, and then removed. No production source,
platform configuration, dependency, or lockfile change remains.

## Baseline

- `flutter analyze`: clean (`No issues found!`, exit 0).
- `flutter test --concurrency=1`: 305 passed, all tests passed (exit 0).

The first run in the fresh worktree stopped at 302 passed with
`ink_sparkle.frag` shader-compilation failures in
`multi_device_control_page_test.dart`, `positions_tab_test.dart`, and
`service_tab_test.dart`. Those failures were a transient Material 3 ink-shader
cold-cache artifact, not inherited defects: the full suite passed 305/305 on
rerun in both the main checkout and this worktree, and
`positions_tab_test.dart` passed 11/11 alone in this worktree. Any recurrence
must be investigated as a regression until proven otherwise. The per-task gate
is 305 plus the task's added tests, `All tests passed!`, and zero failures; there
is no known-failure allowlist.

## Resolution and platform result

`flutter pub get` resolved `google_sign_in 7.2.0` successfully. Its declared
federated implementations are:

| Platform | Resolved implementation |
| --- | --- |
| Android | `google_sign_in_android` |
| iOS | `google_sign_in_ios` |
| macOS | `google_sign_in_ios` |
| Web | `google_sign_in_web` |
| Linux | none |

The plugin declaration has no Linux platform or implementation package. This
spike did not build Linux: Flutter cannot cross-compile Linux from macOS, so
such a build would only fail for the host OS and would not answer the plugin
question. The expected behavior of a federated plugin with no Linux
implementation is that it may build but fail at plugin call time with
`MissingPluginException`; that is an expectation, not a finding. John needs to
confirm it on a Linux machine and phase 4 must keep Drive sign-in unavailable
there unless a supported Linux strategy is deliberately added.

## Native build receipts

With the temporary dependency present:

- `flutter build macos --debug`: passed; produced
  `build/macos/Build/Products/Debug/Production Control.app`. Xcode fetched the
  Google Sign-In Swift Package Manager dependencies and emitted its existing
  `Flutter Assemble` run-script warning.
- `flutter build ios --debug --no-codesign`: passed; produced
  `build/ios/iphoneos/Runner.app`. It first reported a concurrent-Xcode-build
  retry, then completed. The usual no-codesign deployment warning was emitted.
- `flutter analyze`: clean after resolution (exit 0).

## Required Apple setup, intentionally absent

Both commands reported zero occurrences:

```text
grep -c CFBundleURLTypes macos/Runner/Info.plist ios/Runner/Info.plist
# macos: 0; ios: 0
grep -c keychain-access-groups macos/Runner/DebugProfile.entitlements macos/Runner/Release.entitlements
# DebugProfile: 0; Release: 0
```

Phase 4 must add the reversed client-ID URL scheme to both Apple
`Info.plist` files and `$(AppIdentifierPrefix)com.google.GIDSignIn` to the
macOS entitlements. This spike made neither change.

## Token storage answer

The 7.2.0 Dart API exposes an ID token and a client authorization **access**
token only; it does not hand the app a refresh token to persist. Its server
authorization API returns a one-time server auth code, explicitly for a backend
to exchange for access or refresh tokens, and its README says server tokens are
managed entirely on that server. Therefore the planned client-only Drive flow
does not require a secure-storage dependency merely to hold a refresh token.
It still must obtain authorization as the plugin requires and handle expired or
revoked access.

## Cleanup and follow-up

After the probe, `google_sign_in` and its transitive packages were removed by
restoring `pubspec.yaml`/`pubspec.lock` and rerunning `flutter pub get`.
Generated SwiftPM workspace caches from the native builds were removed from the
worktree. Phase 4 should add the actual dependency and Apple configuration only
when it implements the auth surface, and ask John for the Linux receipt.

Post-cleanup verification was clean: `flutter analyze` exited 0 and
`flutter test --concurrency=1` passed 305/305.
