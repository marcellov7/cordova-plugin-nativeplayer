package com.example.plugin;

import org.apache.cordova.CordovaPlugin;
import org.apache.cordova.CallbackContext;
import org.apache.cordova.PluginResult;
import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import android.app.PictureInPictureParams;
import android.content.Context;
import android.content.Intent;
import android.content.res.Configuration;
import android.net.ConnectivityManager;
import android.net.Network;
import android.net.NetworkCapabilities;
import android.net.NetworkRequest;
import android.os.Build;
import android.os.Handler;
import android.os.PowerManager;
import android.util.Rational;
import android.view.View;
import android.view.ViewGroup;
import android.widget.FrameLayout;

import androidx.annotation.Nullable;

import com.google.android.exoplayer2.*;
import com.google.android.exoplayer2.C;
import com.google.android.exoplayer2.source.TrackGroupArray;
import com.google.android.exoplayer2.trackselection.TrackSelectionArray;
import com.google.android.exoplayer2.trackselection.TrackSelectionOverride;
import com.google.android.exoplayer2.ui.PlayerView;
import com.google.android.exoplayer2.video.VideoSize;
import com.google.android.exoplayer2.analytics.AnalyticsListener;
import com.google.android.exoplayer2.source.MediaSource.MediaPeriodId;
import com.google.android.exoplayer2.source.LoadEventInfo;
import com.google.android.exoplayer2.Format;

public class NativePlayer extends CordovaPlugin {

    private ExoPlayer player;
    private PlayerView playerView;
    private CallbackContext callbackContext;
    private Handler handler;
    private ConnectivityManager.NetworkCallback networkCallback;
    private boolean isFullscreen = false;
    private String divId;
    private PowerManager.WakeLock wakeLock;

    @Override
    public boolean execute(String action, JSONArray args, CallbackContext callbackContext) throws JSONException {
        this.callbackContext = callbackContext;
        if (action.equals("createPlayer")) {
            String url = args.getString(0);
            this.divId = args.getString(1);
            this.createPlayer(url, this.divId);
            return true;
        } else if (action.equals("play")) {
            this.play();
            return true;
        } else if (action.equals("pause")) {
            this.pause();
            return true;
        } else if (action.equals("stop")) {
            this.stop();
            return true;
        } else if (action.equals("seekTo")) {
            long position = args.getLong(0);
            this.seekTo(position);
            return true;
        } else if (action.equals("setVolume")) {
            float volume = (float) args.getDouble(0);
            this.setVolume(volume);
            return true;
        } else if (action.equals("setRate")) {
            float rate = (float) args.getDouble(0);
            this.setRate(rate);
            return true;
        } else if (action.equals("toggleFullscreen")) {
            this.toggleFullscreen();
            return true;
        } else if (action.equals("togglePictureInPicture")) {
            this.togglePictureInPicture();
            return true;
        } else if (action.equals("setPreferredAudioLanguage")) {
            String language = args.getString(0);
            this.setPreferredAudioLanguage(language);
            return true;
        } else if (action.equals("setPreferredTextLanguage")) {
            String language = args.getString(0);
            this.setPreferredTextLanguage(language);
            return true;
        } else if (action.equals("enableSubtitles")) {
            boolean enable = args.getBoolean(0);
            this.enableSubtitles(enable);
            return true;
        } else if (action.equals("setVideoQuality")) {
            String quality = args.getString(0);
            this.setVideoQuality(quality);
            return true;
        } else if (action.equals("setBackgroundPlayback")) {
            boolean enabled = args.getBoolean(0);
            this.setBackgroundPlayback(enabled);
            return true;
        }
        return false;
    }

    private void createPlayer(String url, String divId) {
        cordova.getActivity().runOnUiThread(() -> {
            player = new SimpleExoPlayer.Builder(cordova.getActivity()).build();
            playerView = new PlayerView(cordova.getActivity());
            playerView.setPlayer(player);

            FrameLayout.LayoutParams params = new FrameLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.MATCH_PARENT
            );
            ((ViewGroup) webView.getView().getParent()).addView(playerView, params);

            MediaItem mediaItem = MediaItem.fromUri(url);
            player.setMediaItem(mediaItem);
            player.prepare();

            setupPlayerListeners();
            setupNetworkCallback();
            updatePlayerPosition(divId);
        });
    }

    private void setupPlayerListeners() {
        player.addListener(new Player.Listener() {
            @Override
            public void onPlaybackStateChanged(int playbackState) {
                switch (playbackState) {
                    case Player.STATE_IDLE:
                        sendEvent("stop", null);
                        break;
                    case Player.STATE_BUFFERING:
                        sendEvent("waiting", null);
                        break;
                    case Player.STATE_READY:
                        sendEvent("ready", null);
                        sendEvent("canPlay", null);
                        if (player.getPlayWhenReady()) {
                            sendEvent("play", null);
                        } else {
                            sendEvent("pause", null);
                        }
                        break;
                    case Player.STATE_ENDED:
                        sendEvent("ended", null);
                        break;
                }
            }

            @Override
            public void onPlayerError(PlaybackException error) {
                try {
                    JSONObject errorObj = new JSONObject();
                    errorObj.put("error", error.getMessage());
                    sendEvent("error", errorObj);
                } catch (JSONException e) {
                    e.printStackTrace();
                }
            }

            @Override
            public void onPositionDiscontinuity(Player.PositionInfo oldPosition, Player.PositionInfo newPosition, int reason) {
                if (reason == Player.DISCONTINUITY_REASON_SEEK) {
                    sendEvent("seeking", null);
                    sendEvent("seeked", null);
                }
            }

            @Override
            public void onPlayWhenReadyChanged(boolean playWhenReady, int reason) {
                sendEvent(playWhenReady ? "play" : "pause", null);
            }

            @Override
            public void onPlaybackParametersChanged(PlaybackParameters playbackParameters) {
                try {
                    JSONObject rateObj = new JSONObject();
                    rateObj.put("rate", playbackParameters.speed);
                    sendEvent("rateChange", rateObj);
                } catch (JSONException e) {
                    e.printStackTrace();
                }
            }

            @Override
            public void onTracksChanged(Tracks tracks) {
                handleTrackChange(tracks);
            }

            @Override
            public void onVideoSizeChanged(VideoSize videoSize) {
                try {
                    JSONObject resolutionObj = new JSONObject();
                    resolutionObj.put("width", videoSize.width);
                    resolutionObj.put("height", videoSize.height);
                    sendEvent("resolutionChange", resolutionObj);
                } catch (JSONException e) {
                    e.printStackTrace();
                }
            }

            @Override
            public void onVolumeChanged(float volume) {
                try {
                    JSONObject volumeObj = new JSONObject();
                    volumeObj.put("volume", volume);
                    volumeObj.put("muted", volume == 0);
                    sendEvent("volumeChange", volumeObj);
                } catch (JSONException e) {
                    e.printStackTrace();
                }
            }

            @Override
            public void onIsLoadingChanged(boolean isLoading) {
                sendEvent(isLoading ? "loadStart" : "loadedData", null);
            }

            public void onMediaItemTransition(@Nullable MediaItem mediaItem, int reason) {
                sendEvent("loadedMetadata", null);
            }
        });

        // Setup timeUpdate event
        handler = new Handler();
        final Runnable updateProgressRunnable = new Runnable() {
            @Override
            public void run() {
                updateProgress();
                handler.postDelayed(this, 1000);
            }
        };
        handler.post(updateProgressRunnable);

        // Setup progress event
        player.addAnalyticsListener(new AnalyticsListener() {
            public void onLoadCompleted(EventTime eventTime, LoadEventInfo loadEventInfo, MediaPeriodId mediaPeriodId) {
                updateBufferProgress();
            }
        });
    }

    private void updateProgress() {
        try {
            JSONObject progressObj = new JSONObject();
            progressObj.put("currentTime", player.getCurrentPosition() / 1000.0);
            progressObj.put("duration", player.getDuration() / 1000.0);
            sendEvent("timeUpdate", progressObj);
        } catch (JSONException e) {
            e.printStackTrace();
        }
    }

    private void updateBufferProgress() {
        try {
            JSONObject bufferObj = new JSONObject();
            bufferObj.put("bufferedPercentage", player.getBufferedPercentage());
            sendEvent("progress", bufferObj);
        } catch (JSONException e) {
            e.printStackTrace();
        }
    }

    private void handleTrackChange(Tracks tracks) {
        for (Tracks.Group trackGroup : tracks.getGroups()) {
            if (trackGroup.getType() == C.TRACK_TYPE_VIDEO) {
                try {
                    JSONObject trackObj = new JSONObject();
                    trackObj.put("track", Format.toLogString(trackGroup.getMediaTrackGroup().getFormat(0)));
                    sendEvent("qualityTrackChange", trackObj);
                } catch (JSONException e) {
                    e.printStackTrace();
                }
            } else if (trackGroup.getType() == C.TRACK_TYPE_AUDIO) {
                try {
                    JSONObject trackObj = new JSONObject();
                    trackObj.put("track", Format.toLogString(trackGroup.getMediaTrackGroup().getFormat(0)));
                    sendEvent("audioTrackChange", trackObj);
                } catch (JSONException e) {
                    e.printStackTrace();
                }
            } else if (trackGroup.getType() == C.TRACK_TYPE_TEXT) {
                try {
                    JSONObject trackObj = new JSONObject();
                    trackObj.put("track", Format.toLogString(trackGroup.getMediaTrackGroup().getFormat(0)));
                    sendEvent("textTrackChange", trackObj);
                } catch (JSONException e) {
                    e.printStackTrace();
                }
            }
        }
    }

    private void setupNetworkCallback() {
        ConnectivityManager connectivityManager = (ConnectivityManager) cordova.getActivity().getSystemService(Context.CONNECTIVITY_SERVICE);
        networkCallback = new ConnectivityManager.NetworkCallback() {
            @Override
            public void onAvailable(Network network) {
                sendEvent("online", null);
            }

            @Override
            public void onLost(Network network) {
                sendEvent("offline", null);
            }
        };
        NetworkRequest networkRequest = new NetworkRequest.Builder()
                .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
                .build();
        connectivityManager.registerNetworkCallback(networkRequest, networkCallback);
    }

    private void updatePlayerPosition(String divId) {
        cordova.getActivity().runOnUiThread(() -> {
            webView.getEngine().evaluateJavascript(
                    "function getElementRect(id) { " +
                            "  var el = document.getElementById(id); " +
                            "  var rect = el.getBoundingClientRect(); " +
                            "  return JSON.stringify({left: rect.left, top: rect.top, width: rect.width, height: rect.height}); " +
                            "} " +
                            "getElementRect('" + divId + "');",
                    value -> {
                        try {
                            JSONObject rect = new JSONObject(value);
                            playerView.setX(rect.getInt("left"));
                            playerView.setY(rect.getInt("top"));
                            playerView.setLayoutParams(new FrameLayout.LayoutParams(
                                    rect.getInt("width"),
                                    rect.getInt("height")
                            ));
                            sendEvent("resize", null);
                        } catch (JSONException e) {
                            e.printStackTrace();
                        }
                    }
            );
        });
    }

    private void sendEvent(String eventName, JSONObject eventData) {
        if (eventData == null) {
            eventData = new JSONObject();
        }
        try {
            eventData.put("type", eventName);
            PluginResult result = new PluginResult(PluginResult.Status.OK, eventData);
            result.setKeepCallback(true);
            callbackContext.sendPluginResult(result);
        } catch (JSONException e) {
            e.printStackTrace();
        }
    }

    private void play() {
        if (player != null) {
            player.setPlayWhenReady(true);
        }
    }

    private void pause() {
        if (player != null) {
            player.setPlayWhenReady(false);
        }
    }

    private void stop() {
        if (player != null) {
            player.stop();
            player.seekTo(0);
        }
    }

    private void seekTo(long position) {
        if (player != null) {
            player.seekTo(position);
        }
    }

    private void setVolume(float volume) {
        if (player != null) {
            player.setVolume(volume);
        }
    }

    private void setRate(float rate) {
        if (player != null) {
            PlaybackParameters params = new PlaybackParameters(rate);
            player.setPlaybackParameters(params);
        }
    }

    private void toggleFullscreen() {
        cordova.getActivity().runOnUiThread(() -> {
            isFullscreen = !isFullscreen;
            if (isFullscreen) {
                // Implement fullscreen logic here
                // This might involve changing the layout params, hiding system UI, etc.
            } else {
                // Implement exit fullscreen logic here
            }
            try {
                JSONObject fullscreenObj = new JSONObject();
                fullscreenObj.put("isFullscreen", isFullscreen);
                sendEvent("fullscreenChange", fullscreenObj);
            } catch (JSONException e) {
                e.printStackTrace();
            }
        });
    }

    private void togglePictureInPicture() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            cordova.getActivity().runOnUiThread(() -> {
                if (cordova.getActivity().isInPictureInPictureMode()) {
                    cordova.getActivity().moveTaskToBack(false);
                } else {
                    PictureInPictureParams.Builder params = new PictureInPictureParams.Builder();
                    cordova.getActivity().enterPictureInPictureMode(params.build());
                }
            });
        }
    }

    public void onPictureInPictureModeChanged(boolean isInPictureInPictureMode, Configuration newConfig) {
        try {
            JSONObject pipObj = new JSONObject();
            pipObj.put("isPictureInPicture", isInPictureInPictureMode);
            sendEvent("pictureInPictureChange", pipObj);
        } catch (JSONException e) {
            e.printStackTrace();
        }
    }

    @Override
    public void onDestroy() {
        if (player != null) {
            player.release();
        }
        if (handler != null) {
            handler.removeCallbacksAndMessages(null);
        }
        if (networkCallback != null) {
            ConnectivityManager connectivityManager = (ConnectivityManager) cordova.getActivity().getSystemService(Context.CONNECTIVITY_SERVICE);
            connectivityManager.unregisterNetworkCallback(networkCallback);
        }
        if (wakeLock != null && wakeLock.isHeld()) {
            wakeLock.release();
        }
        super.onDestroy();
    }

    public void onConfigurationChanged(Configuration newConfig) {
        super.onConfigurationChanged(newConfig);
        if (newConfig.orientation == Configuration.ORIENTATION_LANDSCAPE ||
            newConfig.orientation == Configuration.ORIENTATION_PORTRAIT) {
            updatePlayerPosition(this.divId);
        }
    }

    private void updateMediaInfo() {
        if (player != null && player.getCurrentMediaItem() != null) {
            try {
                JSONObject mediaInfo = new JSONObject();
                MediaItem mediaItem = player.getCurrentMediaItem();
                mediaInfo.put("title", mediaItem.mediaMetadata.title);
                mediaInfo.put("artist", mediaItem.mediaMetadata.artist);
                mediaInfo.put("album", mediaItem.mediaMetadata.albumTitle);
                mediaInfo.put("duration", player.getDuration() / 1000.0);
                sendEvent("mediaInfo", mediaInfo);
            } catch (JSONException e) {
                e.printStackTrace();
            }
        }
    }

    private void handleStalled() {
        if (player != null && player.getPlaybackState() == Player.STATE_BUFFERING &&
            player.getPlayWhenReady() && player.getBufferedPosition() == player.getCurrentPosition()) {
            sendEvent("stalled", null);
        }
    }

    private void setupStallDetection() {
        final Handler stallHandler = new Handler();
        final Runnable stallRunnable = new Runnable() {
            @Override
            public void run() {
                handleStalled();
                stallHandler.postDelayed(this, 1000);
            }
        };
        stallHandler.post(stallRunnable);
    }

    private void handleWarning(String message) {
        try {
            JSONObject warningObj = new JSONObject();
            warningObj.put("message", message);
            sendEvent("warning", warningObj);
        } catch (JSONException e) {
            e.printStackTrace();
        }
    }

    @Override
    public void onResume(boolean multitasking) {
        super.onResume(multitasking);
        if (player != null) {
            player.setPlayWhenReady(true);
        }
    }

    @Override
    public void onPause(boolean multitasking) {
        super.onPause(multitasking);
        if (player != null) {
            player.setPlayWhenReady(false);
        }
    }

    private void setPreferredAudioLanguage(String language) {
        // Implement custom logic to select preferred audio language
        // This might involve iterating through available audio tracks and selecting the appropriate one
    }

    private void setPreferredTextLanguage(String language) {
        // Implement custom logic to select preferred text language
        // This might involve iterating through available text tracks and selecting the appropriate one
    }

    private void enableSubtitles(boolean enable) {
        if (player != null) {
            Tracks tracks = player.getCurrentTracks();
            for (Tracks.Group trackGroup : tracks.getGroups()) {
                if (trackGroup.getType() == C.TRACK_TYPE_TEXT) {
                    player.setTrackSelectionParameters(
                        player.getTrackSelectionParameters()
                            .buildUpon()
                            .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, !enable)
                            .build()
                    );
                    break;
                }
            }
        }
    }

    private void setVideoQuality(String quality) {
        if (player != null) {
            Tracks tracks = player.getCurrentTracks();
            for (Tracks.Group trackGroup : tracks.getGroups()) {
                if (trackGroup.getType() == C.TRACK_TYPE_VIDEO) {
                    for (int i = 0; i < trackGroup.length; i++) {
                        Format format = trackGroup.getTrackFormat(i);
                        if (quality.equals(format.height + "p")) {
                            player.setTrackSelectionParameters(
                                player.getTrackSelectionParameters()
                                    .buildUpon()
                                    .setOverrideForType(
                                        new TrackSelectionOverride(
                                            trackGroup.getMediaTrackGroup(),
                                            i
                                        )
                                    )
                                    .build()
                            );
                            break;
                        }
                    }
                    break;
                }
            }
        }
    }

    public void setBackgroundPlayback(boolean enabled) {
        if (player != null) {
            player.setHandleAudioBecomingNoisy(!enabled);

            PowerManager powerManager = (PowerManager) cordova.getActivity().getSystemService(Context.POWER_SERVICE);
            if (wakeLock == null) {
                wakeLock = powerManager.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "NativePlayer:WakeLock");
            }

            if (enabled) {
                if (!wakeLock.isHeld()) {
                    wakeLock.acquire();
                }
            } else {
                if (wakeLock.isHeld()) {
                    wakeLock.release();
                }
            }
        }
    }

    @Override
    public void onActivityResult(int requestCode, int resultCode, Intent intent) {
        super.onActivityResult(requestCode, resultCode, intent);
        // Handle any activity results here if needed
    }
}