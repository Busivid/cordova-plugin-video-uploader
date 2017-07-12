package com.busivid.cordova.videouploader;

import org.apache.cordova.CallbackContext;
import org.apache.cordova.PluginResult;
import org.json.JSONException;
import org.json.JSONObject;

import java.util.concurrent.Callable;
import java.util.concurrent.RunnableFuture;

class FileTransferCallbackContext extends CallbackContext {
	private static final String TAG = VideoUploader.TAG;

	private final IEventListener _completeEvent;
	private final IStringEventListener _errorEvent;
	private final ILongEventListener _progressEvent;
	private String _lastErrorMessage;

	public String getLastErrorMessage() {
		return _lastErrorMessage;
	}

	FileTransferCallbackContext(String callbackId, IEventListener completeEvent, IStringEventListener errorEvent, ILongEventListener progressEvent) {
		super(callbackId, null);

		_completeEvent = completeEvent;
		_errorEvent = errorEvent;
		_progressEvent = progressEvent;
	}

	@Override
	public void sendPluginResult(PluginResult pluginResult) {
		int status = pluginResult.getStatus();

		// Catch FileTransferProgress events -> mutate into VideoUploader Progress Event
		if (status != PluginResult.Status.OK.ordinal()) {
			_lastErrorMessage = pluginResult.getMessage();
			_errorEvent.invoke(_lastErrorMessage);
			return;
		}

		try {
			JSONObject fileTransferResult = new JSONObject(pluginResult.getMessage());

			// cordova-plugin-file-transfer JS uses the presence of 'lengthComputable' to differentiate between onprogress() and successcallback()
			if (!fileTransferResult.has("lengthComputable")) {
				_completeEvent.invoke();
				return;
			}

			long loaded = fileTransferResult.getLong("loaded");
			_progressEvent.invoke(loaded);
		} catch (JSONException jsonException) {
			_lastErrorMessage = pluginResult.getMessage();
			_errorEvent.invoke(_lastErrorMessage);
		}
	}
}
