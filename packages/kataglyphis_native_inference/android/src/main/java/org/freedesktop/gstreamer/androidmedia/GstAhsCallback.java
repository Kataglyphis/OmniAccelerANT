package org.freedesktop.gstreamer.androidmedia;

import android.hardware.Sensor;
import android.hardware.SensorEvent;
import android.hardware.SensorEventListener;

public final class GstAhsCallback implements SensorEventListener {

    private final long context;
    private final long userData;

    @SuppressWarnings("unused")
    private final long extra;

    public GstAhsCallback(long context, long userData, long extra) {
        this.context = context;
        this.userData = userData;
        this.extra = extra;
    }

    @SuppressWarnings("PMD.MethodNamingConventions")
    private native void gst_ah_sensor_on_sensor_changed(SensorEvent event, long context, long userData);

    @SuppressWarnings("PMD.MethodNamingConventions")
    private native void gst_ah_sensor_on_accuracy_changed(Sensor sensor, int accuracy, long context, long userData);

    @Override
    public void onSensorChanged(SensorEvent event) {
        gst_ah_sensor_on_sensor_changed(event, context, userData);
    }

    @Override
    public void onAccuracyChanged(Sensor sensor, int accuracy) {
        gst_ah_sensor_on_accuracy_changed(sensor, accuracy, context, userData);
    }
}
