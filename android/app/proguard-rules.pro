# Flutter specific rules
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.embedding.** { *; }

# Play Core (missing classes suppression)
-dontwarn com.google.android.play.core.**
-keep class com.google.android.play.core.** { *; }

# Bluetooth Serial
-keep class com.github.douglasjunior.** { *; }

# Keep application class
-keep class com.robocommander.control.** { *; }

# Keep Dart entry points
-keep class com.robocommander.control.MainActivity { *; }

# General Android rules
-keepattributes *Annotation*
-keepattributes SourceFile,LineNumberTable
-keep public class * extends java.lang.Exception

# Kotlin
-keep class kotlin.** { *; }
-keep class kotlin.Metadata { *; }
-dontwarn kotlin.**
-keepclassmembers class **$WhenMappings {
    <fields>;
}
