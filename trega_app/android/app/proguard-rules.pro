# Trega ProGuard rules — kept minimal; Firebase/Cashfree SDKs ship their
# own consumer rules. These cover the Flutter embedding + app entry point.

-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# MainActivity entry point
-keep class com.trega.trega.MainActivity { *; }

# Cashfree PG SDK (platform-channel native side)
-keep class com.cashfree.** { *; }
-dontwarn com.cashfree.**
