---
name: TravelWise Mobile Rules
description: "Use when changing the Flutter mobile app, Dart widgets, screens, state management, services, platform integration, or mobile tests."
applyTo: "apps/mobile/**/*.dart"
---

# TravelWise Mobile Rules

## Flutter and Dart

- Follow the existing feature structure under `apps/mobile/lib`.
- Reuse shared widgets, services, models and themes before creating duplicates.
- Keep Dart types explicit and handle loading, empty, success and error states.
- Keep network and platform I/O out of widget build methods.
- Dispose controllers, streams, timers and audio resources in the owning widget or service lifecycle.
- Preserve responsive behavior across Android, iOS, web and desktop targets where the existing feature supports them.

## API and voice integration

- Keep request and response models aligned with the FastAPI schemas.
- Surface API and permission failures to the user using the existing notification pattern.
- For voice features, stop recording before playback and prevent overlapping playback or microphone feedback.
- Do not place API keys or other secrets in Dart source or bundled assets.

## Validation

From `apps\mobile` run the narrowest relevant checks:

```powershell
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
```
