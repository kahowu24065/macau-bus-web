# 保護 WorkManager 同 Room Database 唔被 R8 混淆器刪除或改名
-keep class androidx.work.** { *; }
-keep class androidx.room.** { *; }
-keep class androidx.sqlite.** { *; }
-keepclassmembers class * extends androidx.room.RoomDatabase {
    <init>();
}
# Google Mobile Ads ships already-optimized bytecode. Re-optimizing it with
# R8 (AGP 9) produced an invalid register allocation in an ads class in 1.0.8
# (VerifyError 'Expected initialization on uninitialized reference' on the
# AdWorker thread -> crash on launch). Keep it out of R8 optimization; still
# allow shrinking/obfuscation so the APK size stays the same.
-keep,allowshrinking,allowobfuscation class com.google.android.gms.internal.ads.** { *; }
-keep,allowshrinking,allowobfuscation class com.google.android.gms.ads.** { *; }
