package com.apex.vaulty.vaulty

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// FragmentActivity is required by local_auth for the biometric prompt.
class MainActivity : FlutterFragmentActivity() {
    private var calendar: CalendarBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val bridge = CalendarBridge(this)
        calendar = bridge
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CalendarBridge.CHANNEL).setMethodCallHandler(bridge)
    }

    @Deprecated("Still how a FragmentActivity hears back from requestPermissions")
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        calendar?.onPermissionResult(requestCode)
    }
}
