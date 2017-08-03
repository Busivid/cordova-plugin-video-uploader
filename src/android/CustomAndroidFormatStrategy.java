package com.busivid.cordova.videouploader;

import android.media.MediaCodecInfo;
import android.media.MediaFormat;

import net.ypresto.androidtranscoder.format.MediaFormatStrategy;

public class CustomAndroidFormatStrategy implements MediaFormatStrategy {

	private static final int DEFAULT_BITRATE = 8000000;
	private static final int DEFAULT_FRAMERATE = 30;
	private static final int DEFAULT_HEIGHT = 0;
	private static final int DEFAULT_WIDTH = 0;
	private static final String TAG = "CustomFormatStrategy";
	private final int height;
	private final int mBitRate;
	private final int mFrameRate;
	private final int width;

	public CustomAndroidFormatStrategy() {
		this.mBitRate = DEFAULT_BITRATE;
		this.mFrameRate = DEFAULT_FRAMERATE;
		this.width = DEFAULT_WIDTH;
		this.height = DEFAULT_HEIGHT;
	}

	public CustomAndroidFormatStrategy(final int bitRate, final int frameRate, final int width, final int height) {
		this.mBitRate = bitRate;
		this.mFrameRate = frameRate;
		this.width = width;
		this.height = height;
	}

	public MediaFormat createAudioOutputFormat(MediaFormat inputFormat) {
		return null;
	}

	public MediaFormat createVideoOutputFormat(MediaFormat inputFormat) {
		final int inWidth = inputFormat.getInteger(MediaFormat.KEY_WIDTH);
		final int inHeight = inputFormat.getInteger(MediaFormat.KEY_HEIGHT);

		final int outLonger = this.width >= this.height
			? this.width
			: this.height;

		final int inLonger;
		final int inShorter;
		if (inWidth >= inHeight) {
			inLonger = inWidth;
			inShorter = inHeight;
		} else {
			inLonger = inHeight;
			inShorter = inWidth;
		}

		final int outWidth;
		final int outHeight;
		if (inLonger > outLonger) {
			final double aspectRatio = (double)inLonger / (double)inShorter;

			if (inWidth >= inHeight) {
				outWidth = outLonger;
				outHeight = Double.valueOf(outWidth / aspectRatio).intValue();
			} else {
				outHeight = outLonger;
				outWidth = Double.valueOf(outHeight / aspectRatio).intValue();
			}
		} else {
			outWidth = inWidth;
			outHeight = inHeight;
		}

		MediaFormat format = MediaFormat.createVideoFormat("video/avc", outWidth, outHeight);
		format.setInteger(MediaFormat.KEY_BIT_RATE, mBitRate);
		format.setInteger(MediaFormat.KEY_FRAME_RATE, mFrameRate);
		format.setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 3);
		format.setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface);
		format.setLong(MediaFormat.KEY_DURATION, 5 * 1000 * 1000); // Microseconds μs

		return format;
	}
}
