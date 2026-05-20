package com.robocommander.control

import android.Manifest
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothSocket
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Settings
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.util.UUID

/**
 * BluetoothClassicPlugin
 *
 * MethodChannel  : "com.robocommander/bluetooth"
 * EventChannel   : "com.robocommander/bluetooth_events"
 *
 * 연결 전략:
 *   1순위 — reflection createRfcommSocket(channel=1)  ← fb153 필수
 *   2순위 — createRfcommSocketToServiceRecord(SPP UUID) fallback
 */
class BluetoothClassicPlugin(private val context: Context) :
    MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    companion object {
        const val METHOD_CHANNEL = "com.robocommander/bluetooth"
        const val EVENT_CHANNEL  = "com.robocommander/bluetooth_events"
        private val SPP_UUID = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")
    }

    // ── BT 어댑터 ─────────────────────────────────────────────────
    private val btAdapter: BluetoothAdapter? by lazy {
        val mgr = context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
        mgr?.adapter
    }

    // ── 연결 상태 ─────────────────────────────────────────────────
    private var socket: BluetoothSocket? = null
    private var inputStream: InputStream? = null
    private var outputStream: OutputStream? = null
    private var readThread: Thread? = null

    // ── EventChannel 싱크 (Flutter로 이벤트 전달) ─────────────────
    private var eventSink: EventChannel.EventSink? = null

    // ── EventChannel.StreamHandler ────────────────────────────────
    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    // ── MethodChannel.MethodCallHandler ───────────────────────────
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getBondedDevices"      -> handleGetBondedDevices(result)
            "connect"               -> handleConnect(call, result)
            "disconnect"            -> handleDisconnect(result)
            "send"                  -> handleSend(call, result)
            "isConnected"           -> result.success(socket?.isConnected == true)
            "isBluetoothEnabled"    -> result.success(btAdapter?.isEnabled == true)
            "openBluetoothSettings" -> handleOpenBtSettings(result)
            else                    -> result.notImplemented()
        }
    }

    // ── getBondedDevices ──────────────────────────────────────────
    private fun handleGetBondedDevices(result: MethodChannel.Result) {
        if (!hasPermission(Manifest.permission.BLUETOOTH_CONNECT)) {
            result.error("PERMISSION_DENIED", "BLUETOOTH_CONNECT 권한 없음", null)
            return
        }
        try {
            val devices = btAdapter?.bondedDevices?.map { d ->
                mapOf(
                    "name"    to (d.name ?: "알 수 없는 기기"),
                    "address" to d.address,
                    "type"    to d.bluetoothClass?.deviceClass.toString()
                )
            } ?: emptyList<Map<String, String>>()
            result.success(devices)
        } catch (e: Exception) {
            result.error("SCAN_FAILED", e.message, null)
        }
    }

    // ── connect ───────────────────────────────────────────────────
    private fun handleConnect(call: MethodCall, result: MethodChannel.Result) {
        val address = call.argument<String>("address")
            ?: return result.error("INVALID_ARG", "address 누락", null)

        if (!hasPermission(Manifest.permission.BLUETOOTH_CONNECT)) {
            result.error("PERMISSION_DENIED", "BLUETOOTH_CONNECT 권한 없음", null)
            return
        }

        Thread {
            try {
                // 기존 연결 해제
                closeConnection()

                val device = btAdapter?.getRemoteDevice(address)
                    ?: throw IOException("기기를 찾을 수 없음: $address")

                btAdapter?.cancelDiscovery()

                // ── 1순위: reflection channel 1 ──────────────────
                val sock = connectViaReflection(device)
                    ?: connectViaUuid(device)   // ── 2순위: UUID SPP
                    ?: throw IOException("채널1 reflection + UUID SPP 모두 실패")

                socket       = sock
                inputStream  = sock.inputStream
                outputStream = sock.outputStream

                sendEvent(mapOf("type" to "connected", "address" to address))
                result.success(true)

                // 수신 루프 시작
                startReadLoop()

            } catch (e: Exception) {
                closeConnection()
                sendEvent(mapOf("type" to "error", "message" to (e.message ?: "연결 실패")))
                result.error("CONNECT_FAILED", e.message, null)
            }
        }.start()
    }

    /** Reflection으로 채널 1 직결 (fb153 필수) */
    private fun connectViaReflection(device: BluetoothDevice): BluetoothSocket? {
        return try {
            val method = device.javaClass.getMethod("createRfcommSocket", Int::class.java)
            val sock = method.invoke(device, 1) as BluetoothSocket
            sock.connect()
            sock
        } catch (e: Exception) {
            null
        }
    }

    /** 표준 UUID SPP 연결 (fallback) */
    private fun connectViaUuid(device: BluetoothDevice): BluetoothSocket? {
        return try {
            val sock = device.createRfcommSocketToServiceRecord(SPP_UUID)
            sock.connect()
            sock
        } catch (e: Exception) {
            null
        }
    }

    // ── disconnect ────────────────────────────────────────────────
    private fun handleDisconnect(result: MethodChannel.Result) {
        closeConnection()
        sendEvent(mapOf("type" to "disconnected"))
        result.success(true)
    }

    // ── send ──────────────────────────────────────────────────────
    private fun handleSend(call: MethodCall, result: MethodChannel.Result) {
        val bytes = call.argument<ByteArray>("data")
            ?: return result.error("INVALID_ARG", "data 누락", null)

        if (outputStream == null) {
            result.error("NOT_CONNECTED", "연결되지 않음", null)
            return
        }
        try {
            outputStream!!.write(bytes)
            outputStream!!.flush()
            result.success(true)
        } catch (e: Exception) {
            result.error("SEND_FAILED", e.message, null)
        }
    }

    // ── 수신 루프 ─────────────────────────────────────────────────
    private fun startReadLoop() {
        readThread = Thread {
            val buf = ByteArray(1024)
            try {
                while (socket?.isConnected == true) {
                    val n = inputStream?.read(buf) ?: break
                    if (n > 0) {
                        val data = buf.copyOf(n).toList().map { it.toInt() and 0xFF }
                        sendEvent(mapOf("type" to "data", "bytes" to data))
                    }
                }
            } catch (_: Exception) {}
            sendEvent(mapOf("type" to "disconnected"))
            closeConnection()
        }.also { it.isDaemon = true; it.start() }
    }

    // ── 연결 해제 ─────────────────────────────────────────────────
    private fun closeConnection() {
        readThread?.interrupt()
        readThread = null
        try { inputStream?.close()  } catch (_: Exception) {}
        try { outputStream?.close() } catch (_: Exception) {}
        try { socket?.close()       } catch (_: Exception) {}
        inputStream  = null
        outputStream = null
        socket       = null
    }

    // ── 이벤트 전달 (메인 스레드로 post) ──────────────────────────
    private fun sendEvent(data: Map<String, Any>) {
        android.os.Handler(android.os.Looper.getMainLooper()).post {
            eventSink?.success(data)
        }
    }

    // ── 블루투스 설정 열기 ────────────────────────────────────────
    private fun handleOpenBtSettings(result: MethodChannel.Result) {
        try {
            val intent = Intent(Settings.ACTION_BLUETOOTH_SETTINGS).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
            result.success(true)
        } catch (e: Exception) {
            result.error("SETTINGS_FAILED", e.message, null)
        }
    }

    // ── 권한 확인 ─────────────────────────────────────────────────
    private fun hasPermission(permission: String): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S &&
            permission == Manifest.permission.BLUETOOTH_CONNECT) return true
        return ContextCompat.checkSelfPermission(context, permission) ==
            PackageManager.PERMISSION_GRANTED
    }
}
