package com.busivid.cordova.videouploader;

import org.apache.cordova.CallbackContext;
import org.apache.cordova.LOG;
import org.apache.cordova.PluginResult;
import org.json.JSONException;
import org.json.JSONObject;

class TranscodeOperationCallback {
	private final String TAG = VideoUploader.TAG;

	private final CallbackContext _callbackContext;
	private Boolean _isError;
	private final String _progressId;
	private final Runnable _transcodeCompleteBlock;
	private final Runnable _transcodeErrorBlock;

	public TranscodeOperationCallback(CallbackContext callbackContext, String progressId, Runnable transcodeCompleteBlock, Runnable transcodeErrorBlock) {
		_callbackContext = callbackContext;
		_isError = false;
		_progressId = progressId;
		_transcodeCompleteBlock = transcodeCompleteBlock;
		_transcodeErrorBlock = transcodeErrorBlock;
	}

	public void onTranscodeComplete() {
		if (_isError)
			return;

		LOG.d(TAG, "onTranscodeComplete");

		JSONObject jsonObj = new JSONObject();
		try {
			jsonObj.put("progress", 100);
			jsonObj.put("progressId", _progressId);
			jsonObj.put("type", VideoUploader.PROGRESS_TRANSCODED);
		} catch (JSONException e) {
			e.printStackTrace();
		}

		PluginResult progressResult = new PluginResult(PluginResult.Status.OK, jsonObj);
		progressResult.setKeepCallback(true);

		_callbackContext.sendPluginResult(progressResult);

		_transcodeCompleteBlock.run();
	}

	public void onTranscodeError(String message) {
		LOG.d(TAG, "onTranscodeError: " + message);

		_isError = true;
		_callbackContext.error(message);
		_transcodeErrorBlock.run();
	}

	public void onTranscodeProgress(double percentage) {
		if (_isError)
			return;

		LOG.d(TAG, "onTranscodeProgress: " + percentage);

		JSONObject jsonObj = new JSONObject();
		try {
			jsonObj.put("progress", percentage);
			jsonObj.put("progressId", _progressId);
			jsonObj.put("type", VideoUploader.PROGRESS_TRANSCODING);
		} catch (JSONException e) {
			e.printStackTrace();
		}

		PluginResult progressResult = new PluginResult(PluginResult.Status.OK, jsonObj);
		progressResult.setKeepCallback(true);

		_callbackContext.sendPluginResult(progressResult);
	}
}
