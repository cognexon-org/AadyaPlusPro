# Release builds shrink code with R8. Plugins that look classes up by name or
# rely on generic type information break if those classes are renamed or
# stripped, and that shows up as a crash or black screen right at launch.

# Flutter engine and plugin registrant.
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**
-dontwarn com.google.android.play.core.**

# flutter_local_notifications stores its state with Gson, which needs the
# generic signatures R8 removes by default.
-keep class com.dexterous.** { *; }
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes EnclosingMethod,InnerClasses
-keep class com.google.gson.** { *; }
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken
-keep class * extends com.google.gson.TypeAdapter
-keep class * implements com.google.gson.TypeAdapterFactory
-keep class * implements com.google.gson.JsonSerializer
-keep class * implements com.google.gson.JsonDeserializer

# Firebase / Google Play services (push).
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

# OneSignal (push).
-keep class com.onesignal.** { *; }
-dontwarn com.onesignal.**

# mobile_scanner (ML Kit barcode scanning).
-keep class com.google.mlkit.** { *; }
-dontwarn com.google.mlkit.**
