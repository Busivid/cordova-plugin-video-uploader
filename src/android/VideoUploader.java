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
import java.net.URL;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

import javax.net.ssl.HttpsURLConnection;

public class VideoUploader extends CordovaPlugin
{
	public static final String TAG = "VideoUploader";

	private final ExecutorService _transcodeOperations;
	private final ExecutorService _uploadOperations;
	private final Utils _utils;

	public VideoUploader() {
		_transcodeOperations = Executors.newFixedThreadPool(1);
		_uploadOperations = Executors.newFixedThreadPool(1);
		_utils = new Utils(cordova);
	}

	@Override
	public boolean execute(String action, JSONArray args, CallbackContext callbackContext) throws JSONException {
		LOG.d(TAG, "action: " + action);

		if (action.equals("abort")) {
			_transcodeOperations.shutdownNow();
			_uploadOperations.shutdownNow();
			callbackContext.success();
			return true;
		}

		if (action.equals("cleanUp")) {
			cleanup(callbackContext);
			return true;
		}

		if (action.equals("compressAndUpload")) {
			compressAndUpload(args, callbackContext);
			return true;
		}

		throw new JSONException("action: " + action + " is not implemented.");
	}

	private void cleanup(final CallbackContext callbackContext) {
		String tmpPath = getTempDirectoryPath();

		File tmpDir = new File(tmpPath);
		for (File file: tmpDir.listFiles())
			if (!file.isDirectory())
				if (!file.delete())
					LOG.d(TAG, "unable to delete: " + file.getAbsolutePath());

		callbackContext.success();
	}

	private void compressAndUpload(JSONArray args, final CallbackContext callbackContext) {
		try {
			JSONArray fileOptions = args.getJSONArray(0);

			for (int i=0; i < fileOptions.length(); i++) {
				// Parse options
				final JSONObject options = fileOptions.getJSONObject(i);
				final String progressId = options.getString("progressId");

				// Determine tmp file for transcoding
				final String tmpPath = getTempDirectoryPath();
				final String subject = tmpPath + "/" + new SimpleDateFormat("yyyyMMdd_HHmmss", Locale.ENGLISH).format(new Date()) + ".mp4";
				options.put("dstPath", subject);

				final FileTransfer fileTransfer = new FileTransfer();
				fileTransfer.privateInitialize(this.getServiceName(), this.cordova, this.webView, this.preferences);

				final URL uploadCompleteUrl = new URL(options.getString("callbackUrl"));

				// Prepare the upload operation
				final UploadOperation uploadOperation = new UploadOperation(
						fileTransfer,
						subject,
						options,
						new UploadOperationCallback(
								callbackContext,
								progressId,
								new Runnable() {
									@Override
									public void run() {
										reportUploadComplete(callbackContext, uploadCompleteUrl);
									}
								}
						)
				);

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
										_uploadOperations.execute(uploadOperation);
									}
								}
						)
				);

				// Enqueue transcode operation
				_transcodeOperations.execute(transcodeOperation);
			}
		} catch (Throwable e) {
			LOG.d(TAG, "exception ", e);
			callbackContext.error(e.toString());
		}
	}

	private void reportUploadComplete(CallbackContext callbackContext, URL uploadCompleteUrl) {
		int attempts = 3;
		while (attempts > 0) {
			HttpURLConnection connection = null;
			int responseCode = -1;
			try {
				LOG.d(TAG, "HTTP GET: ", uploadCompleteUrl.toString());
				connection = (HttpURLConnection) uploadCompleteUrl.openConnection();
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

	@SuppressWarnings("ResultOfMethodCallIgnored")
	private String getTempDirectoryPath() {
		// Use internal storage
		File cache = cordova.getActivity().getCacheDir();

		// Create the cache directory if it doesn't exist
		cache.mkdirs();

		return cache.getAbsolutePath();
	}
}