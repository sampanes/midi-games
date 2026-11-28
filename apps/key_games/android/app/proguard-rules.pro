# JNI looks up these methods by their original Kotlin signatures. In particular,
# Continuation must not be renamed or getAll fails before the first Flutter frame.
-keep,includedescriptorclasses class io.flutter.plugins.sharedpreferences.** { *; }
# JNI also looks up Kotlin coroutine and result classes by name at runtime.
-keep class kotlin.** { *; }
