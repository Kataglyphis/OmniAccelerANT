/**
 * GStreamer Android initialization helper.
 * 
 * This file is based on the official GStreamer Android helper class.
 * It initializes GStreamer and sets up the application context and class loader
 * which are required by plugins like androidmedia to access Android Java APIs.
 * 
 * Original source: https://gitlab.freedesktop.org/gstreamer/gstreamer/-/tree/master/data/android/GStreamer.java
 */
package org.freedesktop.gstreamer;

import android.content.Context;

public class GStreamer {
    private static native void nativeInit(Context context) throws Exception;

    /**
     * Initialize GStreamer with the given Android context.
     * This must be called before using any GStreamer functionality that requires
     * access to Android APIs (like the androidmedia plugin for camera access).
     *
     * @param context The Android application context
     * @throws Exception if GStreamer initialization fails
     */
    public static void init(Context context) throws Exception {
        nativeInit(context);
    }
}
