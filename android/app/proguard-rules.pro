# DeliveryFlow release R8 rules.
#
# Why this file exists (v27.2.1): AGP 9 runs R8 minification/obfuscation by
# default in release builds. Without these keeps, R8 renamed Gson and stripped
# the generic Signature metadata that flutter_local_notifications relies on:
# its loadScheduledNotifications() does
#   new TypeToken<ArrayList<NotificationDetails>>() {}.getType()
# which then threw "Missing type parameter" at runtime, so EVERY
# zonedSchedule call crashed in release builds and no scheduled notification
# ever worked. The Gson set below is the one shipped in the plugin's own
# example app (flutter_local_notifications 17.2.4), kept verbatim.

## Gson rules
# Gson uses generic type information stored in a class file when working with fields. Proguard
# removes such information by default, so configure it to keep all of it.
-keepattributes Signature

# For using GSON @Expose annotation
-keepattributes *Annotation*

# Gson specific classes
-dontwarn sun.misc.**
#-keep class com.google.gson.stream.** { *; }

# Prevent proguard from stripping interface information from TypeAdapter, TypeAdapterFactory,
# JsonSerializer, JsonDeserializer instances (so they can be used in @JsonAdapter)
-keep class * extends com.google.gson.TypeAdapter
-keep class * implements com.google.gson.TypeAdapterFactory
-keep class * implements com.google.gson.JsonSerializer
-keep class * implements com.google.gson.JsonDeserializer

# Prevent R8 from leaving Data object members always null
-keepclassmembers,allowobfuscation class * {
  @com.google.gson.annotations.SerializedName <fields>;
}

# Retain generic signatures of TypeToken and its subclasses with R8 version 3.0 and higher.
-keep,allowobfuscation,allowshrinking class com.google.gson.reflect.TypeToken
-keep,allowobfuscation,allowshrinking class * extends com.google.gson.reflect.TypeToken

# flutter_local_notifications serializes/deserializes these model classes with
# Gson by reflection; keep them (and their members) fully intact.
-keep class com.dexterous.flutterlocalnotifications.models.** { *; }
