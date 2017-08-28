package com.busivid.cordova.videouploader;

import android.media.MediaMetadataRetriever;
import android.os.Environment;
import android.os.StatFs;

import net.ypresto.androidtranscoder.MediaTranscoder;

import org.apache.cordova.CordovaInterface;
import org.apache.cordova.LOG;
import org.json.JSONException;
import org.json.JSONObject;

import java.io.File;
import java.io.FileInputStream;
import java.io.IOException;
import java.util.concurrent.CountDownLatch;

class TranscodeOperation implements Runnable {
	private final String TAG = VideoUploader.TAG;

	private final TranscodeOperationCallback _callback;
	private final VideoUploader _context;
	public final CordovaInterface _cordova;
	private final File _dst;
	private final String _dstPath;
	private final int _fps;
	private final int _height;
	private boolean _isComplete;
	private final File _src;
	private final String _srcPath;
	private final int _videoBitrate;
	private final long _videoDuration;
	private final int _width;

	public TranscodeOperation(JSONObject options, CordovaInterface cordova, Utils utils, TranscodeOperationCallback callback, VideoUploader context) throws IOException, JSONException {
		_callback = callback;
		_context = context;
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

		_dst = new File(_dstPath);

		if (!_src.exists()) {
			LOG.d(TAG, "input file does not exist");
			_callback.onTranscodeError("input video does not exist.");
			return;
		}
		LOG.d(TAG, "filePath: " + _srcPath);
	}

	@Override
	public void run() {
		final CountDownLatch latch = new CountDownLatch(1);

		final MediaTranscoder.Listener listener = new MediaTranscoder.Listener() {
			@Override
			public void onTranscodeCanceled() {
				LOG.d(TAG, "transcode canceled");

				_callback.onTranscodeError("transcode canceled");
				latch.countDown();
			}

			@Override
			public void onTranscodeCompleted() {
				LOG.d(TAG, "transcode completed");

				_isComplete = true;
				if (!_dst.exists()) {
					LOG.d(TAG, "outputFile doesn't exist!");
					_callback.onTranscodeError("an error occurred during transcoding");
					return;
				}

				_callback.onTranscodeComplete();
				latch.countDown();
			}

			@Override
			public void onTranscodeFailed(Exception exception) {
				LOG.d(TAG, "transcode exception", exception);

				_callback.onTranscodeError(exception.toString());
				latch.countDown();
			}

			@Override
			public void onTranscodeProgress(double progress) {
				LOG.d(TAG, "transcode running " + progress);

				_callback.onTranscodeProgress(progress * 100);
			}
		};

		try {
			MediaMetadataRetriever mmr = new MediaMetadataRetriever();
			mmr.setDataSource(_srcPath);

			// String rotation = mmr.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION);
			// float videoWidth = Float.parseFloat(mmr.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH));
			// float videoHeight = Float.parseFloat(mmr.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT));

			// LOG.d(TAG, "rotation: " + rotation); // 0, 90, 180, or 270

			if (_dst.exists()) {
				listener.onTranscodeCompleted();
				return;
			}

			float durationMillis = Float.parseFloat(mmr.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION));
			if (durationMillis > 0) {
				long bytesRequired = (long)Math.ceil(durationMillis / 1000 * 1.3f * 1024 * 1024); // 1.3 MB per second

				StatFs statFs = new StatFs(Environment.getDataDirectory().getAbsolutePath());
				while (true) {
					long bytesAvailable = statFs.getAvailableBytes();

					// We're OK
					if (bytesRequired < bytesAvailable)
						break;

					// We should be OK if we wait a while
					long totalTmpFileBytes = _context.getTotalTmpFileBytes();
					if (bytesRequired < bytesAvailable + totalTmpFileBytes) {
						LOG.d(TAG, "transcode waiting on disk space. required: " + bytesRequired + " available: " + bytesAvailable + " tmpFiles: " + totalTmpFileBytes);
						_callback.onTranscodeDiskLow();
						Thread.sleep(1000);
						continue;
					}

					// We're totally screwed
					_callback.onTranscodeDiskLow();
					throw new IOException("Insufficient disk space available");
				}
			}

			final FileInputStream inputStream = new FileInputStream(_src);
			_isComplete = false;
			MediaTranscoder.getInstance().transcodeVideo(inputStream.getFD(), _dstPath, new CustomAndroidFormatStrategy(_videoBitrate, _fps, _width, _height), listener, _videoDuration);
			latch.await();
			inputStream.close();
		} catch (InterruptedException e) {
			// Do nothing
		} catch (Throwable e) {
			_callback.onTranscodeError(e.getMessage());
		} finally {
			if (!_isComplete) {
				MediaTranscoder.getInstance().abort();
				_dst.delete();
			}
		}
	}
}
