package org.freedesktop.gstreamer.androidmedia;

import android.hardware.Camera;

public final class GstAhcCallback
        implements Camera.PreviewCallback, Camera.ErrorCallback, Camera.AutoFocusCallback {

    private final long context;
    private final long userData;

    public GstAhcCallback(long context, long userData) {
        this.context = context;
        this.userData = userData;
    }

    @SuppressWarnings("PMD.MethodNamingConventions")
    private native void gst_ah_camera_on_preview_frame(byte[] data, Camera camera, long context, long userData);

    @SuppressWarnings("PMD.MethodNamingConventions")
    private native void gst_ah_camera_on_error(int error, Camera camera, long context, long userData);

    @SuppressWarnings("PMD.MethodNamingConventions")
    private native void gst_ah_camera_on_auto_focus(boolean success, Camera camera, long context, long userData);

    @Override
    public void onPreviewFrame(byte[] data, Camera camera) {
        gst_ah_camera_on_preview_frame(data, camera, context, userData);
    }

    @Override
    public void onError(int error, Camera camera) {
        gst_ah_camera_on_error(error, camera, context, userData);
    }

    @Override
    public void onAutoFocus(boolean success, Camera camera) {
        gst_ah_camera_on_auto_focus(success, camera, context, userData);
    }
}
