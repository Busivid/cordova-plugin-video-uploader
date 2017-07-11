package com.busivid.cordova.videouploader;

import org.apache.cordova.CallbackContext;
import org.apache.cordova.LOG;
import org.apache.cordova.PluginResult;
import org.json.JSONException;
import org.json.JSONObject;

class TranscodeOperationCallback {
	private final String TAG = VideoUploader.TAG;

	private final CallbackContext _callbackContext;
	private final String _progressId;
	private final Runnable _transcodeCompleteBlock;

	public TranscodeOperationCallback(CallbackContext callbackContext, String progressId, Runnable transcodeCompleteBlock) {
		_callbackContext = callbackContext;
		_progressId = progressId;
		_transcodeCompleteBlock = transcodeCompleteBlock;
	}

	public void onTranscodeError(String message) {
		LOG.d(TAG, "onTranscodeError: " + message);

		_callbackContext.error(message);
	}

	public void onTranscodeProgress(double percentage) {
		LOG.d(TAG, "onTranscodeProgress: " + percentage);

		JSONObject jsonObj = new JSONObject();
		try {
			jsonObj.put("progress", percentage);
			jsonObj.put("progressId", _progressId);
			jsonObj.put("type", "TRANSCODING");

		} catch (JSONException e) {
			e.printStackTrace();
		}

		PluginResult progressResult = new PluginResult(PluginResult.Status.OK, jsonObj);
		progressResult.setKeepCallback(true);

		_callbackContext.sendPluginResult(progressResult);
	}

	public void onTranscodeComplete() {
		LOG.d(TAG, "onTranscodeComplete");

		_transcodeCompleteBlock.run();

		JSONObject jsonObj = new JSONObject();
		try {
			jsonObj.put("progress", 100);
			jsonObj.put("progressId", _progressId);
			jsonObj.put("type", "TRANSCODE_COMPLETE");

		} catch (JSONException e) {
			e.printStackTrace();
		}

		PluginResult progressResult = new PluginResult(PluginResult.Status.OK, jsonObj);
		progressResult.setKeepCallback(true);

		_callbackContext.sendPluginResult(progressResult);
	}
}
