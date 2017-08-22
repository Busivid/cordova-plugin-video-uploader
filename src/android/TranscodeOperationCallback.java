package com.busivid.cordova.videouploader;

import org.apache.cordova.CallbackContext;
import org.apache.cordova.LOG;
import org.apache.cordova.PluginResult;
import org.json.JSONException;
import org.json.JSONObject;

class TranscodeOperationCallback {
	private final String TAG = VideoUploader.TAG;

	private final CallbackContext _callbackContext;
	private Boolean _isDiskLow;
	private Boolean _isError;
	private final String _progressId;
	private final Runnable _transcodeCompleteBlock;
	private final Runnable _transcodeErrorBlock;

	public TranscodeOperationCallback(CallbackContext callbackContext, String progressId, Runnable transcodeCompleteBlock, Runnable transcodeErrorBlock) {
		_callbackContext = callbackContext;
		_isDiskLow = false;
		_isError = false;
		_progressId = progressId;
		_transcodeCompleteBlock = transcodeCompleteBlock;
		_transcodeErrorBlock = transcodeErrorBlock;
	}

	public void onTranscodeComplete() {
		if (_isError)
			return;

		LOG.d(TAG, "onTranscodeComplete");

		sendProgress(VideoUploader.PROGRESS_TRANSCODED, 100);
		_transcodeCompleteBlock.run();
	}

	public void onTranscodeDiskLow() {
		if (_isDiskLow)
			return;

		LOG.d(TAG, "onTranscodeDiskLow");

		_isDiskLow = true;
		sendProgress(VideoUploader.WARNING_DISK_LOW, -1);
	}

	public void onTranscodeError(String message) {
		LOG.d(TAG, "onTranscodeError: " + message);

		_isError = true;
		sendProgress(VideoUploader.PROGRESS_TRANSCODING_ERROR, 100);
		sendProgress(VideoUploader.PROGRESS_TRANSCODED, 100);
		_transcodeErrorBlock.run();
	}

	public void onTranscodeProgress(double percentage) {
		if (_isError)
			return;

		LOG.d(TAG, "onTranscodeProgress: " + percentage);

		sendProgress(VideoUploader.PROGRESS_TRANSCODING, percentage);
	}

	private void sendProgress(String type, double percentage) {
		JSONObject jsonObj = new JSONObject();
		try {
			jsonObj.put("progress", percentage);
			jsonObj.put("progressId", _progressId);
			jsonObj.put("type", type);
		} catch (JSONException e) {
			e.printStackTrace();
		}

		PluginResult progressResult = new PluginResult(PluginResult.Status.OK, jsonObj);
		progressResult.setKeepCallback(true);

		_callbackContext.sendPluginResult(progressResult);
	}
}
