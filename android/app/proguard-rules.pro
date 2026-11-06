# Flutter
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**

# OneSignal
-keep class com.onesignal.** { *; }
-dontwarn com.onesignal.**

# flutter_secure_storage / AndroidX security-crypto (Tink)
-keep class androidx.security.crypto.** { *; }
-keep class com.google.crypto.tink.** { *; }
-dontwarn com.google.errorprone.annotations.**
-dontwarn javax.annotation.**

# local_auth / biometric
-keep class androidx.biometric.** { *; }

# Play core (deferred components referenced by the Flutter engine)
-dontwarn com.google.android.play.core.**
