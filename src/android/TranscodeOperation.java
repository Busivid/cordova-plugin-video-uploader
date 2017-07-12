package com.busivid.cordova.videouploader;

import android.media.MediaMetadataRetriever;
import net.ypresto.androidtranscoder.MediaTranscoder;
import org.apache.cordova.CordovaInterface;
import org.apache.cordova.LOG;
import org.json.JSONException;
import org.json.JSONObject;
import java.io.File;
import java.io.FileInputStream;
import java.io.IOException;

class TranscodeOperation implements Runnable {
	private final String TAG = VideoUploader.TAG;

	private final TranscodeOperationCallback _callback;
	public final CordovaInterface _cordova;
	private final String _dstPath;
	private final int _fps;
	private final int _height;
	private final File _src;
	private final String _srcPath;
	private final int _videoBitrate;
	private final long _videoDuration;
	private final int _width;

	public TranscodeOperation(JSONObject options, CordovaInterface cordova, Utils utils, TranscodeOperationCallback callback) throws IOException, JSONException {
		_callback = callback;
		_cordova = cordova;

		LOG.d(TAG, "options: " + options.toString());

		_dstPath = options.getString("dstPath");
		_fps = options.optInt("fps", 25);
		_height = options.optInt("height", 720);
		_src = utils.resolveLocalFileSystemURI(options.getString("filePath"));
		_srcPath = _src.getAbsolutePath();
		_videoBitrate = options.optInt("videoBitrate", 5 * 1000 * 1000);
		_videoDuration = options.optLong("maxSeconds", 900) * 1000 * 1000;
		_width = options.optInt("width", 1280);

		if (!_src.exists()) {
			LOG.d(TAG, "input file does not exist");
			_callback.onTranscodeError("input video does not exist.");
			return;
		}
		LOG.d(TAG, "filePath: " + _srcPath);
	}

	@Override
	public void run() {
		try {
			FileInputStream fin = new FileInputStream(_src);

			MediaTranscoder.Listener listener = new MediaTranscoder.Listener() {
				@Override
				public void onTranscodeProgress(double progress) {
					LOG.d(TAG, "transcode running " + progress);

					_callback.onTranscodeProgress(progress * 100);
				}

				@Override
				public void onTranscodeCompleted() {
					LOG.d(TAG, "transcode completed");

					File outFile = new File(_dstPath);

					if (!outFile.exists()) {
						LOG.d(TAG, "outputFile doesn't exist!");
						_callback.onTranscodeError("an error occurred during transcoding");
						return;
					}

					_callback.onTranscodeComplete();
				}

				@Override
				public void onTranscodeCanceled() {
			LOG.d(TAG, "transcode canceled");
			_callback.onTranscodeError("transcode canceled");
				}

				@Override
				public void onTranscodeFailed(Exception exception) {
					LOG.d(TAG, "transcode exception", exception);

					_callback.onTranscodeError(exception.toString());
				}
			};

			MediaMetadataRetriever mmr = new MediaMetadataRetriever();
			mmr.setDataSource(_srcPath);

			// String orientation;
			// String mmrOrientation = mmr.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION);
			// LOG.d(TAG, "mmrOrientation: " + mmrOrientation); // 0, 90, 180, or 270

			// float videoWidth = Float.parseFloat(mmr.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH));
			// float videoHeight = Float.parseFloat(mmr.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT));

			MediaTranscoder.getInstance().transcodeVideo(fin.getFD(), _dstPath, new CustomAndroidFormatStrategy(_videoBitrate, _fps, _width, _height), listener, _videoDuration);
		}
		catch (Throwable e) {
			LOG.d(TAG, "transcode exception ", e);
			_callback.onTranscodeError(e.toString());
		}
	}
}