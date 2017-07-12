package com.busivid.cordova.videouploader;

import org.apache.cordova.LOG;
import org.apache.cordova.filetransfer.FileTransfer;
import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.io.File;

class UploadOperation implements Runnable {
	private static final int DEFAULT_UPLOAD_CHUNK_SIZE = 100 * 1024 * 1024; // 100 MB
	private static final String TAG = VideoUploader.TAG;

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
		final File source = new File(_source);
		final long sourceLength = source.length();

		final int chunkSize = _options.optInt("upload_chunk_size", DEFAULT_UPLOAD_CHUNK_SIZE);
		final int chunks = (int) (sourceLength / chunkSize) + 1;

		for (int i = 0; i < chunks; i++) {
			final String callbackId = _uploadOperationCallback.getProgressId() + ".part" + (i + 1);
			final long offset = chunkSize * i;

			JSONArray args = new JSONArray();
			args.put(_source);
			args.put(_target);
			args.put("file");								// fileKey
			args.put(source.getName());						// fileName
			args.put("video/mp4");							// mimeType
			args.put(_options.optJSONObject("params"));		// params
			args.put(false);								// trustEveryone
			args.put(false);								// chunkedMode
			args.put(_options.optJSONObject("headers"));	// headers
			args.put(callbackId);							// objectId
			args.put("POST");								// httpMethod
			args.put(1800);									// timeout
			args.put(offset);								// byte offset from start of file
			args.put(chunkSize);							// bytes to upload

			final Object lock = new Object();
			try {
				FileTransferCallbackContext fileTransferCallbackContext = new FileTransferCallbackContext(
					callbackId,
					new IEventListener() {
						// Completed
						@Override
						public void invoke() {
							lock.notify();
						}
					}, new IStringEventListener() {
						// Error
						@Override
						public void invoke(String value) {
							lock.notify();
						}
					}, new ILongEventListener() {
						// Progress
						@Override
						public void invoke(long value) {
							long totalBytesUploaded = offset + value;
							double percentage = (double) totalBytesUploaded / sourceLength * 100;
							_uploadOperationCallback.onUploadProgress(percentage);
						}
					}
				);

				_fileTransfer.execute("upload", args, fileTransferCallbackContext);
				lock.wait();

				String lastErrorMessage = fileTransferCallbackContext.getLastErrorMessage();
				if (lastErrorMessage != null)
					throw new Exception(lastErrorMessage);
			} catch (Throwable e) {
				LOG.d(TAG, "upload exception ", e);

				_uploadOperationCallback.onUploadError(e.toString());
				break;
			}
		}

		_uploadOperationCallback.onUploadComplete();
	}
}
