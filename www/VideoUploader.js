var exec = require('cordova/exec');

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

exports.cleanUp = function (success, error) {
	exec(success, error, 'VideoUploader', 'cleanUp', []);
};

exports.abort = function(success) {
	var error = function(){};
	exec(success, error, 'VideoUploader', 'abort', []);
};
