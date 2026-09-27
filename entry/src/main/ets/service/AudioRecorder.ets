import { audio } from '@kit.AudioKit';
import appLogger from '../utils/Logger';

const TAG = 'AudioRecorder';

const SAMPLE_RATE = 16000;

/**
 * 音频采集器：16kHz / mono / 16-bit PCM
 *
 * 使用 @kit.AudioKit 的 audio.createAudioCapturer 创建 AudioCapturer，
 * 订阅 'readData' 事件读取 PCM 数据，onData 回调输出 Int16Array 样本。
 */
export class AudioRecorder {
  private capturer: audio.AudioCapturer | null = null;
  public onData: ((samples: Int16Array) => void) | null = null;
  private isCapturing: boolean = false;
  private readDataCallback: ((buffer: ArrayBuffer) => void) | null = null;

  async start(): Promise<void> {
    if (this.isCapturing) {
      appLogger.warn(`[${TAG}] already capturing`);
      return;
    }
    try {
      const options: audio.AudioCapturerOptions = {
        streamInfo: {
          samplingRate: audio.AudioSamplingRate.SAMPLE_RATE_16000,
          channels: audio.AudioChannel.CHANNEL_1,
          sampleFormat: audio.AudioSampleFormat.SAMPLE_FORMAT_S16LE,
          encodingType: audio.AudioEncodingType.ENCODING_TYPE_RAW,
        },
        capturerInfo: {
          source: audio.SourceType.SOURCE_TYPE_MIC,
          capturerFlags: 0,
        },
      };
      this.capturer = await audio.createAudioCapturer(options);
      // 订阅 readData 事件（API 11+，替代已废弃的 read() 轮询）
      this.readDataCallback = (buffer: ArrayBuffer): void => {
        if (buffer.byteLength <= 0) {
          return;
        }
        // 16-bit PCM: bytes -> Int16Array
        const frameCount = Math.floor(buffer.byteLength / 2);
        const samples = new Int16Array(frameCount);
        const view = new DataView(buffer);
        for (let i = 0; i < frameCount; i++) {
          samples[i] = view.getInt16(i * 2, true);
        }
        if (this.onData) {
          this.onData(samples);
        }
      };
      this.capturer.on('readData', this.readDataCallback);
      await this.capturer.start();
      this.isCapturing = true;
      appLogger.info(`[${TAG}] started at ${SAMPLE_RATE}Hz mono 16-bit`);
    } catch (e) {
      appLogger.error(`[${TAG}] start failed`, e);
      this.isCapturing = false;
      if (this.capturer) {
        try {
          this.capturer.release();
        } catch (e2) {
          appLogger.error(`[${TAG}] release after start failure failed`, e2);
        }
        this.capturer = null;
      }
      this.readDataCallback = null;
      throw e as Error;
    }
  }

  async stop(): Promise<void> {
    this.isCapturing = false;
    if (this.capturer) {
      try {
        if (this.readDataCallback) {
          this.capturer.off('readData', this.readDataCallback);
        }
      } catch (e) {
        appLogger.error(`[${TAG}] off readData failed`, e);
      }
      try {
        await this.capturer.stop();
        await this.capturer.release();
      } catch (e) {
        appLogger.error(`[${TAG}] stop/release failed`, e);
      }
      this.capturer = null;
    }
    this.readDataCallback = null;
    appLogger.info(`[${TAG}] stopped`);
  }
}
