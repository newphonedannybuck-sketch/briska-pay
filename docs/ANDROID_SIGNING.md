# Android Release Signing

Briska Pay's Android package id is `com.berkzerker.briska`.

Release signing uses `android/key.properties` when that file exists. The keystore and `key.properties` file must not be committed.

Losing the release signing key can prevent future updates to the same Google Play app. Store the keystore and passwords securely, with an offline backup.

## Suggested Keystore Location
Store the private keystore outside the repository, for example:

`C:\Users\danbe\keystores\briska-upload.jks`

## Generate A Keystore
Run this only when ready to create the real upload key:

```powershell
keytool -genkey -v -keystore C:\Users\danbe\keystores\briska-upload.jks -storetype JKS -keyalg RSA -keysize 2048 -validity 10000 -alias briska-upload
```

## Create android/key.properties
Create `android/key.properties` locally:

```properties
storeFile=C:\\Users\\danbe\\keystores\\briska-upload.jks
storePassword=YOUR_STORE_PASSWORD
keyAlias=briska-upload
keyPassword=YOUR_KEY_PASSWORD
```

Do not paste passwords into chat, logs or documentation. Do not commit this file.

## Build
```powershell
flutter build apk --release
flutter build appbundle --release
```

If `android/key.properties` is missing, local release builds fall back to the debug signing key so development can continue. Create the real keystore before distributing a Play Store beta.
