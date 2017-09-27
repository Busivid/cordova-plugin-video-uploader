/*
	Licensed to the Apache Software Foundation (ASF) under one
	or more contributor license agreements.  See the NOTICE file
	distributed with this work for additional information
	regarding copyright ownership.  The ASF licenses this file
	to you under the Apache License, Version 2.0 (the
	"License"); you may not use this file except in compliance
	with the License.  You may obtain a copy of the License at

	http://www.apache.org/licenses/LICENSE-2.0

	Unless required by applicable law or agreed to in writing,
	software distributed under the License is distributed on an
	"AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
	KIND, either express or implied.  See the License for the
	specific language governing permissions and limitations
	under the License.
 */

package com.busivid.cordova.videouploader;

import org.apache.cordova.CallbackContext;
import org.apache.cordova.CordovaPlugin;
import org.apache.cordova.LOG;
import org.apache.cordova.filetransfer.FileTransfer;
import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.io.File;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.MalformedURLException;
import java.net.URI;
import java.net.URISyntaxException;
import java.net.URL;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.atomic.AtomicInteger;

import javax.net.ssl.HttpsURLConnection;

public class VideoUploader extends CordovaPlugin {
	static final String PROGRESS_UPLOADED = "PROGRESS_UPLOADED";
	static final String PROGRESS_UPLOADING = "PROGRESS_UPLOADING";
	static final String PROGRESS_TRANSCODED = "PROGRESS_TRANSCODED";
	static final String PROGRESS_TRANSCODING = "PROGRESS_TRANSCODING";
	static final String PROGRESS_TRANSCODING_ERROR = "PROGRESS_TRANSCODING_ERROR";
	public static final String TAG = "VideoUploader";
	static final String WARNING_DISK_LOW = "WARNING_DISK_LOW";

	private final List<String> _completedUploads;
	private final List<File> _tmpFiles;
	private ExecutorService _transcodeOperations;
	private ExecutorService _uploadOperations;
	private final Utils _utils;

	public VideoUploader() {
		_completedUploads = Collections.synchronizedList(new ArrayList<String>());
		_tmpFiles = new ArrayList<File>();
		_utils = new Utils(cordova);
	}

	private void abort() {
		abortAndShutDown(null, null);
	}

	private void abortAndShutDown(String message, CallbackContext callbackContext) {
		// Ignore if already aborted.
		if (_transcodeOperations.isShutdown() && _uploadOperations.isShutdown())
			return;

		_transcodeOperations.shutdownNow();
		_uploadOperations.shutdownNow();

		// If callbackContext, then return.
		if (callbackContext != null) {
			JSONObject jsonObj = new JSONObject();
			try {
				jsonObj.put("completedTransfers", new JSONArray(_completedUploads));
				jsonObj.put("message", message);
			} catch (JSONException e) {
				e.printStackTrace();
			}
			callbackContext.error(jsonObj);
		}
	}

	private void cleanUp() {
		String tmpPath = getTempDirectoryPath();

		File tmpDir = new File(tmpPath);
		for (File file : tmpDir.listFiles())
			if (!file.isDirectory())
				if (!file.delete())
					LOG.d(TAG, "unable to delete: " + file.getAbsolutePath());
	}

	private void compressAndUpload(JSONArray args, final CallbackContext callbackContext) {
		_completedUploads.clear();
		try {
			JSONArray fileOptions = args.getJSONArray(0);

			final AtomicInteger remaining = new AtomicInteger(fileOptions.length());

			for (int i = 0; i < fileOptions.length(); i++) {
				// Parse options
				final JSONObject options = fileOptions.getJSONObject(i);
				final Boolean deleteAfter = options.optBoolean("deleteAfter", false);
				final String progressId = options.getString("progressId"); // mediaId

				final File original = _utils.resolveLocalFileSystemURI(options.getString("filePath"));

				// Determine tmp file for transcoding
				final String tmpPath = getTempDirectoryPath();
				final String subject = tmpPath + "/" + progressId + "_compressed.mp4";
				options.put("dstPath", subject);

				final File subjectFile = new File(subject);
				_tmpFiles.add(subjectFile);

				final FileTransfer fileTransfer = new FileTransfer();
				fileTransfer.privateInitialize(this.getServiceName(), this.cordova, this.webView, this.preferences);

				final URL uploadCompleteUrl = new URL(options.getString("callbackUrl"));

				final UploadOperationCallback uploadOperationCallback = new UploadOperationCallback(
					callbackContext,
					progressId,
					new UploadCompleteBlock() {
						@Override
						public void run() {
							URL url = uploadCompleteUrl;
							if (ElapsedMillis >= 0) {
								try {
									final URI oldUri = url.toURI();
									final String param = "clientUploadSeconds=" + (int)(ElapsedMillis / 1000);

									String query = oldUri.getQuery();
									if (query == null)
										query = param;
									else
										query += "&" + param;

									url = new URI(oldUri.getScheme(), oldUri.getAuthority(), oldUri.getPath(), query, oldUri.getFragment()).toURL();
								} catch (MalformedURLException exception) {
									// Do Nothing
								} catch (URISyntaxException exception) {
									// Do Nothing
								}
							}

							reportUploadComplete(callbackContext, url);

							if (deleteAfter)
								original.delete();

							// Free Disk Space (After Upload)
							//noinspection ResultOfMethodCallIgnored
							subjectFile.delete();
							_tmpFiles.remove(subjectFile);

							_completedUploads.add(progressId);
							if (remaining.decrementAndGet() == 0)
								callbackContext.success();
						}
					},
					new UploadErrorBlock() {
						@Override
						public void run() {
							abortAndShutDown(Message, callbackContext);
						}
					}
				);

				// Prepare the upload operation
				final UploadOperation uploadOperation = new UploadOperation(fileTransfer, subject, options, uploadOperationCallback);

				// Prepare the transcode operation
				final TranscodeOperation transcodeOperation = new TranscodeOperation(
					options,
					cordova,
					_utils,
					new TranscodeOperationCallback(
						callbackContext,
						progressId,
						new Runnable() {
							@Override
							public void run() {
								if (subjectFile.exists() && !original.exists()) {
									LOG.d(TAG, "Using cached transcoded file");
								} else if (subjectFile.length() > original.length()) {
									// Free Disk Space (Original File Preferred)
									//noinspection ResultOfMethodCallIgnored
									subjectFile.delete();
									_tmpFiles.remove(subjectFile);

									LOG.d(TAG, "Encoded file is larger than the original, uploading the original file instead.");
									uploadOperation.setSource(original.getAbsolutePath());
								} else if (deleteAfter)
									original.delete();

								if (_uploadOperations.isShutdown())
									return;

								_uploadOperations.execute(uploadOperation);
							}
						},
						new Runnable() {
							@Override
							public void run() {
								// Free Disk Space (On Error)
								//noinspection ResultOfMethodCallIgnored
								subjectFile.delete();
								_tmpFiles.remove(subjectFile);

								if (_uploadOperations.isShutdown())
									return;

								LOG.d(TAG, "Transcoding Failed: Uploading the original file instead.");
								uploadOperation.setSource(original.getAbsolutePath());

								_uploadOperations.execute(uploadOperation);
							}
						}
					),
					this
				);

				// Enqueue transcode operation
				_transcodeOperations.execute(transcodeOperation);
			}
		} catch (Throwable e) {
			LOG.d(TAG, "exception ", e);
			callbackContext.error(e.getMessage());
		}
	}

	@Override
	public boolean execute(String action, JSONArray args, CallbackContext callbackContext) throws JSONException {
		LOG.d(TAG, "action: " + action);

		if (_transcodeOperations == null || _transcodeOperations.isShutdown())
			_transcodeOperations = Executors.newFixedThreadPool(1);

		if (_uploadOperations == null || _uploadOperations.isShutdown())
			_uploadOperations = Executors.newFixedThreadPool(1);

		if (action.equals("abort")) {
			abort();
			callbackContext.success();
			return true;
		}

		if (action.equals("cleanUp")) {
			cleanUp();
			callbackContext.success();
			return true;
		}

		if (action.equals("compressAndUpload")) {
			compressAndUpload(args, callbackContext);
			return true;
		}

		throw new JSONException("action: " + action + " is not implemented.");
	}

	@SuppressWarnings("ResultOfMethodCallIgnored")
	private String getTempDirectoryPath() {
		// Use internal storage
		File cache = cordova.getActivity().getCacheDir();

		// Create the cache directory if it doesn't exist
		cache.mkdirs();

		return cache.getAbsolutePath();
	}

	long getTotalTmpFileBytes() {
		long result = 0;
		for (File file : _tmpFiles) {
			result += file.length();
		}

		return result;
	}

	private void reportUploadComplete(CallbackContext callbackContext, URL uploadCompleteUrl) {
		int attempts = 3;
		while (attempts > 0) {
			HttpURLConnection connection = null;
			int responseCode = -1;
			try {
				LOG.d(TAG, "HTTP GET: ", uploadCompleteUrl.toString());
				connection = (HttpURLConnection)uploadCompleteUrl.openConnection();
				connection.setConnectTimeout(10000);
				connection.setReadTimeout(10000);

				responseCode = connection.getResponseCode();
				LOG.d(TAG, "Response Code: ", responseCode);

				final InputStream in = connection.getInputStream();

				int ptr;
				final StringBuffer buffer = new StringBuffer();

				while ((ptr = in.read()) != -1)
					buffer.append((char)ptr);

				LOG.d(TAG, "Response Body: ", buffer);

				if (responseCode == HttpsURLConnection.HTTP_OK) {
					return;
				}

				throw new Exception("Error HTTP Response Code: " + responseCode);
			} catch (Exception exception) {
				LOG.d(TAG, "Exception: ", exception.getMessage());

				// Retry indefinitely for HTTP - Service Unavailable
				if (responseCode != 503)
					attempts--;

				try {
					Thread.sleep(10000);
				} catch (InterruptedException e) {
					e.printStackTrace();
				}
			} finally {
				if (connection != null)
					connection.disconnect();
			}
		}

		callbackContext.error("HTTP Request Failed: " + uploadCompleteUrl);
	}
}
