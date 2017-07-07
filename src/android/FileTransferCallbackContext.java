package com.busivid.cordova.videouploader;

import org.apache.cordova.CallbackContext;
import org.apache.cordova.PluginResult;
import org.json.JSONException;
import org.json.JSONObject;

class FileTransferCallbackContext extends CallbackContext {
	private final String TAG = VideoUploader.TAG;

	private final IUploadOperationCallback _uploadOperationCallback;

	FileTransferCallbackContext(IUploadOperationCallback uploadOperationCallback) {
		super(uploadOperationCallback.getProgressId(), null);

		_uploadOperationCallback = uploadOperationCallback;
	}

	@Override
	public void sendPluginResult(PluginResult pluginResult) {
		int status = pluginResult.getStatus();

		// Catch FileTransferProgress events -> mutate into VideoUploader Progress Event
		if (status != PluginResult.Status.OK.ordinal()) {
			_uploadOperationCallback.onUploadError(pluginResult.getMessage());
			return;
		}

		try {
			JSONObject fileTransferResult = new JSONObject(pluginResult.getMessage());

			// cordova-plugin-file-transfer JS uses the presence of 'lengthComputable' to differentiate between onprogress() and successcallback()
			if (!fileTransferResult.has("lengthComputable")) {
				_uploadOperationCallback.onUploadComplete();
				return;
			}

			long loaded = fileTransferResult.getLong("loaded");
			long total = fileTransferResult.getLong("total");

			double percentage = total == 0
					? 0
					: loaded / (double)total * 100;

			_uploadOperationCallback.onUploadProgress(percentage);
		} catch (JSONException jsonException) {
			_uploadOperationCallback.onUploadError(jsonException.toString());
		}
	}
}
