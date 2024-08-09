# Cordova NativePlayer Plugin

## Description
The NativePlayer plugin provides a native video player implementation for Cordova applications. It uses ExoPlayer on Android and AVPlayer on iOS, offering a high-performance and feature-rich video playback experience.

## Installation

```bash
cordova plugin add https://github.com/marcellov7/cordova-plugin-nativeplayer.git
```

## Usage Example

Here's a basic example of how to use the NativePlayer plugin:

```javascript
document.addEventListener('deviceready', onDeviceReady, false);

function onDeviceReady() {
    var videoUrl = 'https://example.com/video.mp4';
    var playerContainer = 'player-container';

    // Create the player
    NativePlayer.createPlayer(videoUrl, playerContainer, onSuccess, onError);

    // Register event listener
    NativePlayer.registerEventListener(function(event) {
        switch(event.type) {
            case 'play':
                console.log('Video started playing');
                break;
            case 'pause':
                console.log('Video paused');
                break;
            case 'timeUpdate':
                console.log('Current time:', event.currentTime);
                break;
            // Handle other events...
        }
    });

    // Player controls
    document.getElementById('playBtn').addEventListener('click', function() {
        NativePlayer.play(onSuccess, onError);
    });

    document.getElementById('pauseBtn').addEventListener('click', function() {
        NativePlayer.pause(onSuccess, onError);
    });

    // More control implementations...
}

function onSuccess() {
    console.log('Operation successful');
}

function onError(error) {
    console.error('Error:', error);
}
```

## API Reference

### Methods

1. `createPlayer(url, divId, success, error)`
2. `play(success, error)`
3. `pause(success, error)`
4. `stop(success, error)`
5. `seekTo(position, success, error)`
6. `setVolume(volume, success, error)`
7. `getPosition(success, error)`
8. `getDuration(success, error)`
9. `destroy(success, error)`
10. `registerEventListener(callback)`
11. `setRate(rate, success, error)`
12. `toggleFullscreen(success, error)`
13. `togglePictureInPicture(success, error)`
14. `setPreferredAudioLanguage(language, success, error)`
15. `setPreferredTextLanguage(language, success, error)`
16. `enableSubtitles(enable, success, error)`
17. `setVideoQuality(quality, success, error)`
18. `setBackgroundPlayback(enabled, success, error)`

### Events

1. `play`: Fired when playback starts
2. `pause`: Fired when playback is paused
3. `stop`: Fired when playback is stopped
4. `ended`: Fired when playback reaches the end
5. `timeUpdate`: Fired periodically with current playback time
6. `durationChange`: Fired when the video duration is available or changes
7. `progress`: Fired to indicate buffering progress
8. `seeking`: Fired when a seek operation starts
9. `seeked`: Fired when a seek operation completes
10. `waiting`: Fired when the player is waiting for data
11. `canPlay`: Fired when the player can start playback
12. `canPlayThrough`: Fired when the player estimates it can play through the entire media without stopping
13. `loadStart`: Fired when the player starts loading data
14. `loadedMetadata`: Fired when metadata has been loaded
15. `loadedData`: Fired when data for the current frame is loaded
16. `volumeChange`: Fired when the volume changes
17. `rateChange`: Fired when the playback rate changes
18. `resize`: Fired when the player size changes
19. `error`: Fired when an error occurs
20. `stalled`: Fired when the player is stalling
21. `fullscreenChange`: Fired when entering or exiting fullscreen mode
22. `pictureInPictureChange`: Fired when entering or exiting picture-in-picture mode
23. `qualityChange`: Fired when the video quality changes
24. `audioTrackChange`: Fired when the audio track changes
25. `textTrackChange`: Fired when the text track (subtitles) changes

## Platform Support

- Android 5.0+ (API 21+)
- iOS 11.0+

## License

This project is licensed under the MIT License.