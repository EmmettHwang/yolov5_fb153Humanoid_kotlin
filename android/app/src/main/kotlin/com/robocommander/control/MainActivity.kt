package com.robocommander.control

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private lateinit var btPlugin: BluetoothClassicPlugin

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        btPlugin = BluetoothClassicPlugin(applicationContext)

        // MethodChannel — 명령 전달 (getBondedDevices, connect, disconnect, send ...)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            BluetoothClassicPlugin.METHOD_CHANNEL
        ).setMethodCallHandler(btPlugin)

        // EventChannel — 연결/데이터/에러 이벤트 수신
        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            BluetoothClassicPlugin.EVENT_CHANNEL
        ).setStreamHandler(btPlugin)
    }
}
