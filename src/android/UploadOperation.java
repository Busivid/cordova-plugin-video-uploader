package com.busivid.cordova.videouploader;

import org.apache.cordova.LOG;
import org.apache.cordova.filetransfer.FileTransfer;
import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.io.File;

class UploadOperation implements Runnable {
	private final String TAG = VideoUploader.TAG;

	private final FileTransfer _fileTransfer;
	private final JSONObject _options;
	private final String _source;
	private final String _target;
	private final UploadOperationCallback _uploadOperationCallback;

	public UploadOperation(FileTransfer fileTransfer, String source, JSONObject options, UploadOperationCallback uploadOperationCallback) throws JSONException {
		_fileTransfer = fileTransfer;
		_options = options;
		_source = source;
		_target = options.getString("uploadUrl");
		_uploadOperationCallback = uploadOperationCallback;
	}

	@Override
	public void run() {
		File source = new File(_source);

		JSONArray args = new JSONArray();
		args.put(_source);
		args.put(_target);
		args.put("file");									// fileKey
		args.put(source.getName());							// fileName
		args.put("video/mp4");								// mimeType
		args.put(_options.optJSONObject("params"));			// params
		args.put(false);									// trustEveryone
		args.put(false);									// chunkedMode
		args.put(_options.optJSONObject("headers"));		// headers
		args.put(_uploadOperationCallback.getProgressId());	// objectId
		args.put("POST");									// httpMethod
		args.put(1800);										// timeout

		try {
			_fileTransfer.execute("upload", args, new FileTransferCallbackContext(_uploadOperationCallback));
		} catch (Throwable e) {
			LOG.d(TAG, "upload exception ", e);

			_uploadOperationCallback.onUploadError(e.toString());
		}
	}
}
