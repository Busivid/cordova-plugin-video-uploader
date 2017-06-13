cordova-plugin-video-uploader
=============================

Cordova Video Uploader Plugin for Apache Cordova

Performs the following steps
1) Transcodes one or more videos
2) Uploads each video using a chunked upload method
3) Hits a url after each file is uploaded

## Installation

    cordova plugin add http://git.busivid.com/root/cordova-plugin-video-uploader.git

## Usage

    function onVideoUploadError(error) {
      console.log(error.completedTransfers); // Array of progressId
      console.log(error.message);
    }

    function onVideoUploadProgress(type, progressId, percentage) {
      // percentage is (int) 1-100
      // progressId (see options.progressId)
      // type is either 'TRANSCODING', 'UPLOADING', or 'UPLOADCOMPLETE'

      console.log(progressId + ' ' + type + ' ' + percentage + '%');
    }

    function onVideoUploadSuccess() {
      console.log('All operations completed');
    }

    var upload1 = {
      'callbackUrl': 'Url to hit after each file is uploaded',
      'fileName': 'Relative Remote path/to/filename.mp4',
      'filePath': 'Absolute Local file://URL',
      'maxSeconds': '(int) Maximum video length in seconds',
      'params': 'HTTP Request variables sent to both the callbackUrl and uploadUrl',
      'progressId': 'Some unique string, used to facilitate multiple concurrent operations',
      'uploadUrl': 'Url to POST the transcoded file to'
    };

    var options = [
      upload1
    ];

    cordova.plugins.VideoUploader.compressAndUpload(options, success, progress, error)

