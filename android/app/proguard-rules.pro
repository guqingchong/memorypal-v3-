# ML Kit Text Recognition
-keep class com.google.mlkit.vision.text.** { *; }
-keep class com.google.mlkit.vision.text.chinese.** { *; }
-keep class com.google.mlkit.vision.text.devanagari.** { *; }
-keep class com.google.mlkit.vision.text.japanese.** { *; }
-keep class com.google.mlkit.vision.text.korean.** { *; }

# Keep all ML Kit related classes
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit.** { *; }
-dontwarn com.google.mlkit.**
