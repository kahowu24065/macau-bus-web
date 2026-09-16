# 保護 WorkManager 同 Room Database 唔被 R8 混淆器刪除或改名
-keep class androidx.work.** { *; }
-keep class androidx.room.** { *; }
-keep class androidx.sqlite.** { *; }
-keepclassmembers class * extends androidx.room.RoomDatabase {
    <init>();
}