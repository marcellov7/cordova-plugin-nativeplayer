var exec = require('cordova/exec');

var NativePlayer = {
    createPlayer: function(url, divId, success, error) {
        exec(success, error, 'NativePlayer', 'createPlayer', [url, divId]);
    },
    play: function(success, error) {
        exec(success, error, 'NativePlayer', 'play', []);
    },
    pause: function(success, error) {
        exec(success, error, 'NativePlayer', 'pause', []);
    },
    stop: function(success, error) {
        exec(success, error, 'NativePlayer', 'stop', []);
    },
    seekTo: function(position, success, error) {
        exec(success, error, 'NativePlayer', 'seekTo', [position]);
    },
    setVolume: function(volume, success, error) {
        exec(success, error, 'NativePlayer', 'setVolume', [volume]);
    },
    getPosition: function(success, error) {
        exec(success, error, 'NativePlayer', 'getPosition', []);
    },
    getDuration: function(success, error) {
        exec(success, error, 'NativePlayer', 'getDuration', []);
    },
    destroy: function(success, error) {
        exec(success, error, 'NativePlayer', 'destroy', []);
    },
    registerEventListener: function(callback) {
        var success = function(event) {
            if (typeof callback === 'function') {
                callback(event);
            }
        };
        var error = function(err) {
            console.error('Error in NativePlayer event listener:', err);
        };
        exec(success, error, 'NativePlayer', 'registerEventListener', []);
    }
};

module.exports = NativePlayer;