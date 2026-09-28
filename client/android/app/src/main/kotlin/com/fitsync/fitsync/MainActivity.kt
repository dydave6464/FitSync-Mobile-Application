package com.fitsync.fitsync

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/// The phone's own step counter (TYPE_STEP_COUNTER), not Health Connect: a
/// running total since the last restart. The app keeps its own readings to
/// work out each day (lib/features/activity/domain/step_readings.dart).
class MainActivity : FlutterActivity() {
  private fun reading(steps: Float): Map<String, Long> {
    val now = System.currentTimeMillis()
    return mapOf(
      "steps" to steps.toLong(),
      "bootMs" to now - SystemClock.elapsedRealtime(),
      "atMs" to now,
    )
  }

  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    val sensors = getSystemService(Context.SENSOR_SERVICE) as SensorManager
    val counter: Sensor? = sensors.getDefaultSensor(Sensor.TYPE_STEP_COUNTER)
    val messenger = flutterEngine.dartExecutor.binaryMessenger
    val main = Handler(Looper.getMainLooper())

    MethodChannel(messenger, "fitsync/steps").setMethodCallHandler { call, result ->
      when (call.method) {
        "isAvailable" -> result.success(counter != null)
        "readStepCounter" -> {
          if (counter == null) {
            result.error("unavailable", "No TYPE_STEP_COUNTER sensor", null)
            return@setMethodCallHandler
          }
          var done = false
          lateinit var listener: SensorEventListener
          // Some phones send nothing until the next step, and none without
          // the permission; answer rather than hang.
          val timeout = Runnable {
            if (!done) {
              done = true
              sensors.unregisterListener(listener)
              result.error("timeout", "No step counter reading", null)
            }
          }
          listener = object : SensorEventListener {
            override fun onSensorChanged(event: SensorEvent) {
              if (done) return
              done = true
              main.removeCallbacks(timeout)
              sensors.unregisterListener(this)
              result.success(reading(event.values[0]))
            }
            override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
          }
          sensors.registerListener(listener, counter, SensorManager.SENSOR_DELAY_NORMAL)
          main.postDelayed(timeout, 5000)
        }
        else -> result.notImplemented()
      }
    }

    EventChannel(messenger, "fitsync/steps/live").setStreamHandler(object : EventChannel.StreamHandler {
      private var listener: SensorEventListener? = null

      override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
        if (counter == null) {
          sink.error("unavailable", "No TYPE_STEP_COUNTER sensor", null)
          return
        }
        listener = object : SensorEventListener {
          override fun onSensorChanged(event: SensorEvent) { sink.success(reading(event.values[0])) }
          override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
        }
        sensors.registerListener(listener, counter, SensorManager.SENSOR_DELAY_NORMAL)
      }

      override fun onCancel(arguments: Any?) {
        listener?.let { sensors.unregisterListener(it) }
        listener = null
      }
    })
  }
}
