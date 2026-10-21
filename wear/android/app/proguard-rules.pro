# Health Services bundles protobuf-lite, which reads message fields by name at
# runtime. Without these rules R8 renames them and the app crashes on start
# ("Field name_ for x.B not found").
-keep class androidx.health.services.client.** { *; }
-keepclassmembers class * extends **.GeneratedMessageLite { <fields>; }
