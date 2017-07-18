package com.busivid.cordova.videouploader;

import org.apache.cordova.LOG;
import org.apache.cordova.filetransfer.FileTransfer;
import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.io.File;
import java.util.concurrent.CountDownLatch;

class UploadOperation implements Runnable {
	private static final int DEFAULT_UPLOAD_CHUNK_SIZE = -1;
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
		final int chunks = chunkSize < 1
				? 1
				: (int) (sourceLength / chunkSize) + 1;

		for (int i = 0; i < chunks; i++) {
			final String callbackId = chunks > 1
					? _uploadOperationCallback.getProgressId() + ".part" + (i + 1)
					: _uploadOperationCallback.getProgressId();
			final long offset = chunkSize * i;

			final CountDownLatch latch = new CountDownLatch(1);
			try {
				JSONArray params = _options.optJSONArray("params");

				JSONArray args = new JSONArray();
				args.put(_source);
				args.put(_target);
				args.put("file");				// fileKey
				args.put(source.getName());			// fileName
				args.put("video/mp4");				// mimeType
				args.put(params.opt(0));			// params
				args.put(false);				// trustEveryone
				args.put(false);				// chunkedMode
				args.put(_options.optJSONObject("headers"));	// headers
				args.put(callbackId);				// objectId
				args.put("POST");				// httpMethod
				args.put(1800);					// timeout
				args.put(offset);				// offset of first byte to upload
				args.put(chunkSize);				// number of bytes to upload

				FileTransferCallbackContext fileTransferCallbackContext = new FileTransferCallbackContext(
					callbackId,
					new IEventListener() {
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
							double percentage = (double) totalBytesUploaded / sourceLength * 100;
							_uploadOperationCallback.onUploadProgress(percentage);
						}
					}
				);

				_fileTransfer.execute("upload", args, fileTransferCallbackContext);
				latch.await();

				String lastErrorMessage = fileTransferCallbackContext.getLastErrorMessage();
				if (lastErrorMessage != null)
					throw new Exception(lastErrorMessage);
			} catch (Throwable e) {
				LOG.d(TAG, "upload exception ", e);

				_uploadOperationCallback.onUploadError(e.toString());
				return;
			}
		}

		_uploadOperationCallback.onUploadComplete();
	}
}
