# --- Google ML Kit text recognition ---------------------------------------
# The plugin references every script recognizer, but Vaulty only bundles the
# Latin model. The other option classes are intentionally absent.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**

# ML Kit wires its internals (image utils, loggers, model registrars) together
# through reflection and Firebase-style component discovery declared in the
# manifest. R8 full mode strips/renames those pieces, which surfaces at runtime
# as a NullPointerException inside InputImage.fromFilePath(). Keep them whole.
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_** { *; }
-keep class com.google.android.datatransport.** { *; }
-keep class com.google.firebase.components.** { *; }
-keep class * implements com.google.firebase.components.ComponentRegistrar { *; }
-keep class com.google_mlkit_commons.** { *; }
-keep class com.google_mlkit_text_recognition.** { *; }

# --- SQLCipher --------------------------------------------------------------
# Native code looks these classes and members up by name over JNI.
-keep class net.zetetic.database.** { *; }
-keep class net.zetetic.database.sqlcipher.** { *; }

# --- flutter_local_notifications --------------------------------------------
# Scheduled notifications are persisted with Gson and restored after reboot.
-keep class com.dexterous.** { *; }
-keepattributes Signature
-keepattributes *Annotation*
-keep class * extends com.google.gson.TypeAdapter
-keep class * implements com.google.gson.TypeAdapterFactory
-keep class * implements com.google.gson.JsonSerializer
-keep class * implements com.google.gson.JsonDeserializer
-keep,allowobfuscation,allowshrinking class com.google.gson.reflect.TypeToken
-keep,allowobfuscation,allowshrinking class * extends com.google.gson.reflect.TypeToken
