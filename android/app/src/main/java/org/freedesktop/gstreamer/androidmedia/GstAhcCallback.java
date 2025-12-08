package org.freedesktop.gstreamer.androidmedia;

import android.media.Image;
import android.media.ImageReader;
import android.hardware.camera2.CameraDevice;
import android.hardware.camera2.CameraCaptureSession;
import android.hardware.camera2.CaptureRequest;
import android.view.Surface;
import java.nio.ByteBuffer;

public class GstAhcCallback implements ImageReader.OnImageAvailableListener {
    public long mUserData;
    public long mCallback;

    // Native functions (mirror your existing native signatures)
    public static native void gst_ah_camera_on_preview_frame(byte[] data, CameraDevice camera,
                                                             long callback, long user_data);
    public static native void gst_ah_camera_on_error(int error, CameraDevice camera,
                                                     long callback, long user_data);
    public static native void gst_ah_camera_on_auto_focus(boolean success, CameraDevice camera,
                                                          long callback, long user_data);

    public GstAhcCallback(long callback, long user_data) {
        mCallback = callback;
        mUserData = user_data;
    }

    // Called when a new image is available from ImageReader
    @Override
    public void onImageAvailable(ImageReader reader) {
        Image image = null;
        try {
            image = reader.acquireLatestImage();
            if (image == null) return;

            // Convert YUV_420_888 -> NV21-like byte[]
            byte[] nv21 = yuv420ToNv21(image);
            // Pass to native (camera device not available here, pass null or stored CameraDevice)
            gst_ah_camera_on_preview_frame(nv21, /* camera placeholder */ null, mCallback, mUserData);
        } catch (Exception e) {
            // Map exception to an error call if needed
            gst_ah_camera_on_error(-1, /* camera */ null, mCallback, mUserData);
        } finally {
            if (image != null) image.close();
        }
    }

    // Helper: convert YUV_420_888 Image -> NV21 byte[]
    private static byte[] yuv420ToNv21(Image image) {
        Image.Plane[] planes = image.getPlanes();
        ByteBuffer yBuf = planes[0].getBuffer();
        ByteBuffer uBuf = planes[1].getBuffer();
        ByteBuffer vBuf = planes[2].getBuffer();

        int ySize = yBuf.remaining();
        int uSize = uBuf.remaining();
        int vSize = vBuf.remaining();

        byte[] nv21 = new byte[ySize + uSize + vSize];

        // copy Y
        yBuf.get(nv21, 0, ySize);

        // interleave V and U to form NV21 (V then U)
        // This assumes the image is in the common YUV_420_888 layout - may need adjustments per device
        // Simple but not the most robust interleaving:
        byte[] u = new byte[uSize]; uBuf.get(u);
        byte[] v = new byte[vSize]; vBuf.get(v);

        int pos = ySize;
        int chromaStep = 1;
        for (int i = 0; i < vSize; i++) {
            nv21[pos++] = v[i];
            if (pos < nv21.length) nv21[pos++] = u[i];
        }
        return nv21;
    }

    // Call these from your camera open/capture-session management as needed:
    public void onAutoFocusResult(boolean success, CameraDevice cameraDevice) {
        gst_ah_camera_on_auto_focus(success, cameraDevice, mCallback, mUserData);
    }

    public void reportError(int error, CameraDevice cameraDevice) {
        gst_ah_camera_on_error(error, cameraDevice, mCallback, mUserData);
    }
}
