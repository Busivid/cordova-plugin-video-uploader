cordova-plugin-video-uploader
=============================

Cordova Video Uploader Plugin for Apache Cordova

Performs the following steps
1) Transcodes one or more videos
2) Uploads each video using a chunked upload method
3) Hits a url after each file is uploaded

## Installation

    cordova plugin add https://github.com/Busivid/cordova-plugin-video-uploader.git

## Usage

    function onVideoUploadError(error) {
      console.log(error.completedUploads); // Array of id
      console.log(error.message);
    }

    function onVideoUploadProgress(type, id, percentage) {
      // percentage is (int) 1-100
      // id (see options.id)
      // type is either 'TRANSCODE_COMPLETE', 'TRANSCODE_ERROR', 'TRANSCODING', 'UPLOAD_COMPLETE' or 'UPLOADING'

      console.log(id + ' ' + type + ' ' + percentage + '%');
    }

    function onVideoUploadSuccess() {
      console.log('All operations completed');
    }

    var upload1 = {
      'callbackUrl': 'Url to hit after each file is uploaded',
      'chunkSize': 'Size of each individual chunk',
      'fileName': 'Relative Remote path/to/filename.mp4',
      'filePath': 'Absolute Local file://URL',
      'id': 'Some unique string, used to facilitate multiple concurrent operations',
      'maxSeconds': '(int) Maximum video length in seconds',
      'params': 'Array of HTTP Request variables sent to both the callbackUrl and uploadUrl',
      'timeout': '(int) Timeout value for the upload request',
      'uploadUrl': 'Url to POST the transcoded file to'
    };

    var options = [
      upload1,
      upload2,
    ];

    cordova.plugins.VideoUploader.compressAndUpload(options, success, progress, error)

