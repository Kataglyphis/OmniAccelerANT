package org.freedesktop.gstreamer.androidmedia;

import android.graphics.SurfaceTexture;

public final class GstAmcOnFrameAvailableListener implements SurfaceTexture.OnFrameAvailableListener {

    private long context;

    public void setContext(long context) {
        this.context = context;
    }

    @SuppressWarnings("PMD.MethodNamingConventions")
    private native void native_onFrameAvailable(long context, SurfaceTexture surfaceTexture);

    @Override
    public void onFrameAvailable(SurfaceTexture surfaceTexture) {
        native_onFrameAvailable(context, surfaceTexture);
    }
}
