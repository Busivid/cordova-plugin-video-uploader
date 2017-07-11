package com.busivid.cordova.videouploader;

import org.apache.cordova.CallbackContext;
import org.apache.cordova.LOG;
import org.apache.cordova.PluginResult;
import org.json.JSONException;
import org.json.JSONObject;

interface IUploadOperationCallback {
	String getProgressId();
	void onUploadComplete();
	void onUploadError(String message);
	void onUploadProgress(double percentage);
}

class UploadOperationCallback implements IUploadOperationCallback {
	private final String TAG = VideoUploader.TAG;

	private final CallbackContext _callbackContext;
	private final String _progressId;
	private final Runnable _uploadCompleteBlock;

	public UploadOperationCallback(CallbackContext callbackContext, String progressId, Runnable uploadCompleteBlock) {
		_callbackContext = callbackContext;
		_progressId = progressId;
		_uploadCompleteBlock = uploadCompleteBlock;
	}

	public String getProgressId() {
		return _progressId;
	}

	public void onUploadError(String message) {
		LOG.d(TAG, "onUploadError: " + message);

		_callbackContext.error(message);
	}

	public void onUploadComplete() {
		LOG.d(TAG, "onUploadComplete");

		_uploadCompleteBlock.run();

		JSONObject jsonObj = new JSONObject();
		try {
			jsonObj.put("progress", 100);
			jsonObj.put("progressId", _progressId);
			jsonObj.put("type", "UPLOAD_COMPLETE");
		} catch (JSONException e) {
			e.printStackTrace();
		}

		PluginResult progressResult = new PluginResult(PluginResult.Status.OK, jsonObj);
		progressResult.setKeepCallback(true);

		_callbackContext.sendPluginResult(progressResult);
		_callbackContext.success();
	}

	public void onUploadProgress(double percentage) {
		LOG.d(TAG, "onUploadProgress: " + percentage);

		JSONObject jsonObj = new JSONObject();
		try {
			jsonObj.put("progress", percentage);
			jsonObj.put("progressId", _progressId);
			jsonObj.put("type", "UPLOADING");
		} catch (JSONException e) {
			e.printStackTrace();
		}

		PluginResult progressResult = new PluginResult(PluginResult.Status.OK, jsonObj);
		progressResult.setKeepCallback(true);

		_callbackContext.sendPluginResult(progressResult);
	}
}
