package com.busivid.cordova.videouploader;

import org.apache.cordova.LOG;
import org.apache.cordova.filetransfer.FileTransfer;
import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.io.File;
import java.net.HttpURLConnection;
import java.net.URL;
import java.util.concurrent.CountDownLatch;
import java.util.Date;

class UploadOperation implements Runnable {
	private static final int DEFAULT_UPLOAD_CHUNK_SIZE = 100 * 1024 * 1024;
	private static final String TAG = VideoUploader.TAG;

	private final FileTransfer _fileTransfer;
	private final JSONObject _options;
	private String _source;
	private final String _target;
	private final UploadOperationCallback _uploadOperationCallback;
	private Date _uploadStartTime;

	public UploadOperation(FileTransfer fileTransfer, String source, JSONObject options, UploadOperationCallback uploadOperationCallback) throws JSONException {
		_fileTransfer = fileTransfer;
		_options = options;
		_source = source;
		_target = options.getString("uploadUrl");
		_uploadOperationCallback = uploadOperationCallback;
	}

	public void setSource(String value) {
		_source = value;
	}

	@Override
	public void run() {
		final File source = new File(_source);
		final long sourceLength = source.length();

		final int chunkSize = _options.optInt("chunkSize", DEFAULT_UPLOAD_CHUNK_SIZE);
		final int chunks = chunkSize <= 0
			? 1
			: (int)(sourceLength / chunkSize) + 1;

		_uploadStartTime = new Date();

		for (int i = 0; i < chunks; i++) {
			final String callbackId = chunks > 1
				? _uploadOperationCallback.getProgressId() + ".part" + (i + 1)
				: _uploadOperationCallback.getProgressId();
			final long offset = chunkSize * i;

			final CountDownLatch latch = new CountDownLatch(1);
			try {
				JSONArray params = _options.optJSONArray("params");
				JSONObject options = params.optJSONObject(i);

				// Determine if this chunk has already been uploaded
				URL url = new URL(_target + "/" + options.get("key"));
				HttpURLConnection connection = (HttpURLConnection)url.openConnection();
				connection.setRequestMethod("HEAD");
				connection.setUseCaches(false);
				int responseCode = connection.getResponseCode();
				if (responseCode == 200) {
					_uploadStartTime = null;
					continue;
				}

				JSONArray args = new JSONArray();
				args.put(_source);
				args.put(_target);
				args.put("file");                                // fileKey
				args.put(source.getName());                        // fileName
				args.put("video/mp4");                            // mimeType
				args.put(options);                                // params
				args.put(false);                                // trustEveryone
				args.put(false);                                // chunkedMode
				args.put(_options.optJSONObject("headers"));    // headers
				args.put(callbackId);                            // objectId
				args.put("POST");                                // httpMethod
				args.put(1800);                                    // timeout
				args.put(offset);                                // offset of first byte to upload
				args.put(chunkSize);                            // number of bytes to upload

				FileTransferCallbackContext fileTransferCallbackContext = new FileTransferCallbackContext(callbackId, new IEventListener() {
					// Completed
					@Override
					public void invoke() {
						latch.countDown();
					}
				}, new IStringEventListener() {
					// Error
					@Override
					public void invoke(String value) {
						latch.countDown();
					}
				}, new ILongEventListener() {
					// Progress
					@Override
					public void invoke(long value) {
						long totalBytesUploaded = offset + value;
						double percentage = (double)totalBytesUploaded / sourceLength * 100;
						_uploadOperationCallback.onUploadProgress(percentage);
					}
				});

				_fileTransfer.execute("upload", args, fileTransferCallbackContext);
				latch.await();

				String lastErrorMessage = fileTransferCallbackContext.getLastErrorMessage();
				if (lastErrorMessage != null)
					throw new Exception(lastErrorMessage);
			} catch (Throwable e) {
				LOG.d(TAG, "upload exception ", e);

				_uploadOperationCallback.onUploadError(e.getMessage());
				return;
			}
		}

		long elapsed = _uploadStartTime == null
			? -1
			: System.currentTimeMillis() - _uploadStartTime.getTime();

		_uploadOperationCallback.onUploadComplete(elapsed);
	}
}
