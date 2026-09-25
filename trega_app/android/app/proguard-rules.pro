# Trega ProGuard rules — hardened for no-device-testing safety.
# Firebase SDKs ship their own consumer-rules.pro (auto-applied); these cover
# the Flutter embedding, all plugins, and reflection-heavy SDKs.

# --- Flutter embedding & all plugins (platform channels are string-based,
# --- but keep the native side intact to be safe) ---
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# --- App entry point ---
-keep class com.trega.trega.MainActivity { *; }

# --- Cashfree PG SDK (native side uses reflection for JSON/models) ---
-keep class com.cashfree.** { *; }
-dontwarn com.cashfree.**

# --- Firebase (belt-and-suspenders; SDKs already bundle consumer rules) ---
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

# --- Serialization (Gson/Moshi used by plugins & SDKs) ---
-keepattributes Signature, InnerClasses, EnclosingMethod
-keepattributes *Annotation*
-keep class com.google.gson.** { *; }
-keep class com.squareup.moshi.** { *; }
-dontwarn com.google.gson.**
-dontwarn com.squareup.moshi.**

# --- Native methods & enums (R8 must not strip/rename these) ---
-keepclasseswithmembernames class * {
    native <methods>;
}
-keepclassmembers class * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}

# --- Parcelable (Android IPC) ---
-keep class * implements android.os.Parcelable {
  public static final android.os.Parcelable$Creator *;
}
