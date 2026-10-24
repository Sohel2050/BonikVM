package com.albonik.vpn

import android.app.Activity
import android.content.Intent
import android.net.VpnService
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.axevpn.flutter.openvpn.AxeVPNFlutterPlugin

class MainActivity : FlutterFragmentActivity() {
    private val CHANNEL = "axe_vpn/vpn_permission"
    private val VPN_REQUEST_CODE = 24

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "isVpnPermissionGranted" -> {
                    val intent = VpnService.prepare(this)
                    result.success(intent == null)
                }
                "requestVpnPermission" -> {
                    val intent = VpnService.prepare(this)
                    if (intent != null) {
                        startActivityForResult(intent, VPN_REQUEST_CODE)
                        pendingResult = result
                    } else {
                        result.success(true)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private var pendingResult: MethodChannel.Result? = null

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        // Handle AxeVPN plugin permission
        AxeVPNFlutterPlugin.connectWhileGranted(requestCode == 24 && resultCode == Activity.RESULT_OK)
        
        if (requestCode == VPN_REQUEST_CODE) {
            // Handle our VPN permission request directly without calling super
            pendingResult?.success(resultCode == Activity.RESULT_OK)
            pendingResult = null
            return
        }
        
        // Only call super for other requests
        super.onActivityResult(requestCode, resultCode, data)
    }
}
