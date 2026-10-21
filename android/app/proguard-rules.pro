# Glance is not used here; keep only what RevenueCat needs (it ships consumer rules).

# Credential Manager finds its Play services provider by reflection.
-if class androidx.credentials.CredentialManager
-keep class androidx.credentials.playservices.** { *; }
