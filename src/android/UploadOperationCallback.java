package com.busivid.cordova.videouploader;

import org.apache.cordova.CallbackContext;
import org.apache.cordova.LOG;
import org.apache.cordova.PluginResult;
import org.json.JSONException;
import org.json.JSONObject;

class UploadOperationCallback {
	private final String TAG = VideoUploader.TAG;

	private final CallbackContext _callbackContext;
	private Boolean _isError;
	private final String _progressId;
	private final UploadCompleteBlock _uploadCompleteBlock;
	private final UploadErrorBlock _uploadErrorBlock;

	public UploadOperationCallback(CallbackContext callbackContext, String progressId, UploadCompleteBlock uploadCompleteBlock, UploadErrorBlock uploadErrorBlock) {
		_callbackContext = callbackContext;
		_isError = false;
		_progressId = progressId;
		_uploadCompleteBlock = uploadCompleteBlock;
		_uploadErrorBlock = uploadErrorBlock;
	}

	public String getProgressId() {
		return _progressId;
	}

	public void onUploadComplete(long elapsedMillis) {
		if (_isError)
			return;

		LOG.d(TAG, "onUploadComplete");

		JSONObject jsonObj = new JSONObject();
		try {
			jsonObj.put("id", _progressId);
			jsonObj.put("progress", 100);
			jsonObj.put("type", VideoUploader.PROGRESS_UPLOADED);
		} catch (JSONException e) {
			e.printStackTrace();
		}

		PluginResult progressResult = new PluginResult(PluginResult.Status.OK, jsonObj);
		progressResult.setKeepCallback(true);

		_callbackContext.sendPluginResult(progressResult);
		_uploadCompleteBlock.ElapsedMillis = elapsedMillis;
		_uploadCompleteBlock.run();
	}

	public void onUploadError(String message) {
		LOG.d(TAG, "onUploadError: " + message);

		_isError = true;
		_uploadErrorBlock.Message = message;
		_uploadErrorBlock.run();
	}

	public void onUploadProgress(double percentage) {
		if (_isError)
			return;

		LOG.d(TAG, "onUploadProgress: " + percentage);

		JSONObject jsonObj = new JSONObject();
		try {
			jsonObj.put("id", _progressId);
			jsonObj.put("progress", percentage);
			jsonObj.put("type", VideoUploader.PROGRESS_UPLOADING);
		} catch (JSONException e) {
			e.printStackTrace();
		}

		PluginResult progressResult = new PluginResult(PluginResult.Status.OK, jsonObj);
		progressResult.setKeepCallback(true);

		_callbackContext.sendPluginResult(progressResult);
	}
}
