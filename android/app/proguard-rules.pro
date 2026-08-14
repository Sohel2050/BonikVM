# ===========================================
# PLAY STORE APP BUNDLE - PROGUARD RULES
# Optimized for OpenVPN Flutter Plugin, AdMob, Firebase
# ===========================================

# -------------------------------
# HDR/GRAPHICS - FIX FOR SMPTE 2094-40 ERRORS
# -------------------------------
# Keep HDR-related classes to prevent gralloc errors
-keep class android.hardware.display.** { *; }
-keep class android.view.Display$HdrCapabilities { *; }
-keep class android.graphics.** { *; }
-dontwarn android.hardware.display.**

# -------------------------------
# OPENVPN FLUTTER PLUGIN - CRITICAL FOR VPN CONNECTION
# -------------------------------
# Keep all OpenVPN core classes - CRITICAL for VPN functionality
-keep class de.blinkt.openvpn.** { *; }
-keep class de.blinkt.openvpn.*$* { *; }
-keep class com.github.nizwar.** { *; }
-keep class net.openvpn.** { *; }

# OpenVPN service and activities - REQUIRED for VPN operations  
-keep class de.blinkt.openvpn.core.OpenVPNService { *; }
-keep class de.blinkt.openvpn.core.OpenVPNService$* { *; }
-keep class de.blinkt.openvpn.core.VPNLaunchHelper { *; }
-keep class de.blinkt.openvpn.core.VpnStatus { *; }
-keep class de.blinkt.openvpn.core.ConnectionStatus { *; }
-keep class de.blinkt.openvpn.core.LogItem { *; }
-keep class de.blinkt.openvpn.VpnProfile { *; }
-keep class de.blinkt.openvpn.LaunchVPN { *; }
-keep class de.blinkt.openvpn.activities.DisconnectVPN { *; }

# OpenVPN native methods - CRITICAL
-keepclasseswithmembernames class * {
    native <methods>;
}

# OpenVPN Flutter plugin - CRITICAL
-keep class com.github.nizwar.** { *; }
-dontwarn de.blinkt.openvpn.**
-dontwarn com.github.nizwar.**

# -------------------------------
# FLUTTER PLUGINS - ESSENTIALS
# -------------------------------
-keep class io.flutter.plugins.GeneratedPluginRegistrant {
    static void registerWith(io.flutter.embedding.engine.FlutterEngine);
}

-keep class io.flutter.embedding.engine.FlutterEngine { *; }

# Specific plugins
-keep class com.baseflow.permissionhandler.** { *; }
-dontwarn com.baseflow.permissionhandler.**

-keep class dev.fluttercommunity.plus.network_info.** { *; }
-dontwarn dev.fluttercommunity.plus.network_info.**

-keep class dev.fluttercommunity.plus.connectivity.** { *; }
-dontwarn dev.fluttercommunity.plus.connectivity.**

-keep class io.flutter.plugins.sharedpreferences.** { *; }
-dontwarn io.flutter.plugins.sharedpreferences.**

-keep class io.flutter.plugins.googlemobileads.** { *; }
-dontwarn io.flutter.plugins.googlemobileads.**

# -------------------------------
# ADMOB & GOOGLE ADS
# -------------------------------
-keep class com.google.android.gms.ads.** { *; }
-dontwarn com.google.android.gms.ads.**

-keep class com.google.ads.** { *; }
-dontwarn com.google.ads.**

# -------------------------------
# FIREBASE (Crashlytics, Analytics)
# -------------------------------
-keep class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**
-dontwarn javax.crypto.**

# -------------------------------
# IN-APP PURCHASES
# -------------------------------
-keep class com.android.billingclient.** { *; }
-dontwarn com.android.billingclient.**

-keep class * implements com.android.billingclient.api.PurchasesUpdatedListener { *; }
-keep class * implements com.android.billingclient.api.BillingClientStateListener { *; }

-keep class com.android.vending.billing.** { *; }
-dontwarn com.android.vending.billing.**

# -------------------------------
# GSON - JSON SERIALIZATION
# -------------------------------
-keepattributes Signature, RuntimeVisibleAnnotations, AnnotationDefault
-keep class com.google.gson.** { *; }
-keep class com.google.gson.reflect.TypeToken { *; }
-dontwarn com.google.gson.**

# Keep fields with @SerializedName
-keepclassmembers class * {
    @com.google.gson.annotations.SerializedName <fields>;
}

# -------------------------------
# PARCELABLE & SERIALIZABLE
# -------------------------------
-keep class * implements android.os.Parcelable {
    public static final android.os.Parcelable$Creator *;
}

-keepclassmembers class * implements java.io.Serializable {
    static final long serialVersionUID;
    private static final java.io.ObjectStreamField[] serialPersistentFields;
    private void writeObject(java.io.ObjectOutputStream);
    private void readObject(java.io.ObjectInputStream);
    java.lang.Object writeReplace();
    java.lang.Object readResolve();
}

# -------------------------------
# NATIVE METHODS
# -------------------------------
-keepclassmembers class * {
    native <methods>;
}

# -------------------------------
# NETWORK & SYSTEM
# -------------------------------
-keep class java.net.NetworkInterface { *; }
-keep class java.net.InetAddress { *; }
-keep class java.net.Socket { *; }
-keep class java.net.DatagramSocket { *; }

# -------------------------------
# STRIPE FLUTTER PLUGIN
# -------------------------------
-keep class com.stripe.** { *; }
-keep class com.reactnativestripesdk.** { *; }
-keep class com.flutter.stripe.** { *; }
-dontwarn com.stripe.**
-dontwarn com.reactnativestripesdk.**
-dontwarn com.flutter.stripe.**

# Keep Stripe payment method classes
-keep class com.stripe.android.model.** { *; }
-keep class com.stripe.android.payments.** { *; }
-keep class com.stripe.android.paymentsheet.** { *; }

# Keep AppCompat theme classes for Stripe
-keep class androidx.appcompat.** { *; }
-keep class androidx.core.content.ContextCompat { *; }
-dontwarn androidx.appcompat.**

# -------------------------------
# IN-APP UPDATES - GOOGLE PLAY CORE
# -------------------------------
# Keep Google Play Core classes for in-app updates
-keep class com.google.android.play.core.** { *; }
-keep class com.google.android.play.core.appupdate.** { *; }
-keep class com.google.android.play.core.install.** { *; }
-keep class com.google.android.play.core.tasks.** { *; }
-dontwarn com.google.android.play.core.**

# Keep in-app update Flutter plugin classes
-keep class dev.flutterplaza.in_app_update.** { *; }
-dontwarn dev.flutterplaza.in_app_update.**

# -------------------------------
# V2RAY / AXEVPN V2RAY PLUGIN
# -------------------------------
# libv2ray classes are loaded via native Go binding at runtime (gomobile AAR)
# R8 cannot see them during compilation — suppress missing class errors
-dontwarn libv2ray.Libv2ray
-dontwarn libv2ray.V2RayPoint
-dontwarn libv2ray.V2RayVPNServiceSupportsSet
-keep class libv2ray.** { *; }
-keep class com.axevpn.flutter.v2ray.** { *; }

# -------------------------------
# UNITY LEVELPLAY (IRONSOURCE) SDK
# -------------------------------
-keep class com.ironsource.** { *; }
-keep class com.ironsource.mediationsdk.** { *; }
-keep class com.ironsource.adapters.** { *; }
-dontwarn com.ironsource.**
-dontwarn com.ironsource.mediationsdk.**
-dontwarn com.ironsource.adapters.**

# Keep LevelPlay webview activity and SDK internals
-keepclassmembers class com.ironsource.mediationsdk.utils.IronSourceWebViewActivity { *; }
-keep public class com.google.android.gms.ads.identifier.AdvertisingIdClient { *; }
-keep public class com.google.android.gms.ads.identifier.AdvertisingIdClient$Info { *; }

# Reflection used by the IronSource SDK
-keepattributes JavascriptInterface
-keepclassmembers class * {
    @android.webkit.JavascriptInterface <methods>;
}