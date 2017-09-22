var exec = require('cordova/exec');

exports.abort = function(success) {
	var error = function(){};
	exec(success, error, 'VideoUploader', 'abort', []);
};

exports.cleanUp = function (success, error) {
	exec(success, error, 'VideoUploader', 'cleanUp', []);
};

exports.compressAndUpload = function (options, successCallback, progressCallback, errorCallback) {
	var error = function (results) {
		if (typeof results === 'undefined')
			results = {};

		if (typeof results.completedUploads === 'undefined' || !Array.isArray(results.completedUploads))
			results.completedUploads = new Array();

		if (typeof errorCallback === 'function')
			errorCallback(results);
	};

	var success = function (results) {
		if (results !== null && typeof results.progress !== 'undefined') {
			if (typeof progressCallback === 'function') {
				progressCallback(results.type, results.progressId, results.progress);
			}
		} else {
			if (typeof successCallback === 'function') {
				successCallback(results);
			}
		}
	};

	exec(success, error, 'VideoUploader', 'compressAndUpload', [options]);
};

exports.PROGRESS_TRANSCODED = 'PROGRESS_TRANSCODED';
exports.PROGRESS_TRANSCODING = 'PROGRESS_TRANSCODING';
exports.PROGRESS_TRANSCODING_ERROR = 'PROGRESS_TRANSCODING_ERROR';
exports.PROGRESS_UPLOADED = 'PROGRESS_UPLOADED';
exports.PROGRESS_UPLOADING = 'PROGRESS_UPLOADING';
exports.WARNING_DISK_LOW = 'WARNING_DISK_LOW';
