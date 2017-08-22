var exec = require('cordova/exec');

exports.abort = function(success) {
	var error = function(){};
	exec(success, error, 'VideoUploader', 'abort', []);
};

exports.cleanUp = function (success, error) {
	exec(success, error, 'VideoUploader', 'cleanUp', []);
};

exports.compressAndUpload = function (options, success, progress, error) {
	var win = function (results) {
		if (results !== null && typeof results.progress !== 'undefined') {
			if (typeof progress === 'function') {
				progress(results.type, results.progressId, results.progress);
			}
		} else {
			success(results);
		}
	};

	exec(win, error, 'VideoUploader', 'compressAndUpload', [options]);
};

exports.ERROR_DISK_FULL = 'ERROR_DISK_FULL';
exports.PROGRESS_TRANSCODED = 'PROGRESS_TRANSCODED';
exports.PROGRESS_TRANSCODING = 'PROGRESS_TRANSCODING';
exports.PROGRESS_UPLOADED = 'PROGRESS_UPLOADED';
exports.PROGRESS_UPLOADING = 'PROGRESS_UPLOADING';
exports.WARNING_DISK_LOW = 'WARNING_DISK_LOW';
