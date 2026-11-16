# Flutter Wrapper
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }
-dontwarn io.flutter.embedding.**

# LiveKit & WebRTC
-keep class com.cloudwebrtc.webrtc.** { *; }
-keep class io.livekit.android.** { *; }
-dontwarn io.livekit.android.**
