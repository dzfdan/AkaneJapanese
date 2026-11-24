import { audio } from '@kit.AudioKit';
import appLogger from '../utils/Logger';

const TAG = 'AudioRecorder';

const SAMPLE_RATE = 16000;
// 数据看门狗超时：启动后 3 秒内未收到任何 PCM 数据，视为麦克风未正常工作
const NO_DATA_TIMEOUT_MS = 3000;

/**
 * 音频采集器：16kHz / mono / 16-bit PCM
 *
 * 使用 @kit.AudioKit 的 audio.createAudioCapturer 创建 AudioCapturer，
 * 订阅 'readData' 事件读取 PCM 数据，onData 回调输出 Int16Array 样本。
 *
 * 关键设计：
 * 1. 使用 SOURCE_TYPE_VOICE_RECOGNITION 而非 SOURCE_TYPE_MIC。
 *    语音识别源类型会启用系统级回声消除(AEC)、降噪(NS)、自动增益(AGC)，
 *    在车机/平板多麦设备上避免播放回声进入录音，显著提升 ASR 识别率。
 * 2. 订阅 'stateChange' 监控采集器实际运行状态（running/paused/stopped），
 *    便于排查"启动了但没声音"的问题。
 * 3. 数据看门狗：启动后若 3 秒内未收到任何 PCM 帧，打印警告，
 *    帮助定位麦克风被占用/权限未生效/设备路由失败等问题。
 */
export class AudioRecorder {
  private capturer: audio.AudioCapturer | null = null;
  public onData: ((samples: Int16Array) => void) | null = null;
  /** 录音中发生错误时回调（如麦克风被占用、设备断开、无数据输入） */
  public onError: ((message: string) => void) | null = null;
  private isCapturing: boolean = false;
  private readDataCallback: ((buffer: ArrayBuffer) => void) | null = null;
  private stateChangeCallback: ((state: audio.AudioState) => void) | null = null;

  // 数据看门狗
  private noDataTimerId: number = -1;
  private receivedAnyData: boolean = false;
  // 周期性输出音量日志，便于排查麦克风是否真的有声音
  private amplitudeLogAccumulator: number = 0;
  private readonly amplitudeLogInterval: number = 50;

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
          // 语音识别专用源：启用 AEC/NS/AGC，避免播放回声与环境噪声进入录音
          source: audio.SourceType.SOURCE_TYPE_VOICE_RECOGNITION,
          capturerFlags: 0,
        },
      };
      this.capturer = await audio.createAudioCapturer(options);

      // 订阅 readData 事件（API 11+，替代已废弃的 read() 轮询）
      this.readDataCallback = (buffer: ArrayBuffer): void => {
        if (buffer.byteLength <= 0) {
          return;
        }
        // 首帧到达时取消看门狗
        if (!this.receivedAnyData) {
          this.receivedAnyData = true;
          this.cancelNoDataWatchdog();
          appLogger.info(`[${TAG}] first audio frame received, size=${buffer.byteLength}`);
        }
        // 16-bit PCM: bytes -> Int16Array
        const frameCount = Math.floor(buffer.byteLength / 2);
        const samples = new Int16Array(frameCount);
        const view = new DataView(buffer);
        let maxAbs = 0;
        for (let i = 0; i < frameCount; i++) {
          const v = view.getInt16(i * 2, true);
          samples[i] = v;
          const abs = v < 0 ? -v : v;
          if (abs > maxAbs) {
            maxAbs = abs;
          }
        }
        // 周期性输出峰值，便于排查"麦克风无输入"
        this.amplitudeLogAccumulator++;
        if (this.amplitudeLogAccumulator >= this.amplitudeLogInterval) {
          this.amplitudeLogAccumulator = 0;
          appLogger.debug(`[${TAG}] amplitude maxAbs=${maxAbs} (silence if ~0)`);
        }
        if (this.onData) {
          this.onData(samples);
        }
      };
      this.capturer.on('readData', this.readDataCallback);

      // 监控采集器状态变化
      this.stateChangeCallback = (state: audio.AudioState): void => {
        appLogger.info(`[${TAG}] capturer state change -> ${state}`);
        if (state === audio.AudioState.STATE_RUNNING) {
          // 真正进入录音状态后启动看门狗
          this.startNoDataWatchdog();
        } else if (state === audio.AudioState.STATE_STOPPED || state === audio.AudioState.STATE_RELEASED) {
          this.cancelNoDataWatchdog();
        }
      };
      try {
        this.capturer.on('stateChange', this.stateChangeCallback);
      } catch (e) {
        appLogger.warn(`[${TAG}] subscribe stateChange failed (non-fatal)`, e);
      }


      await this.capturer.start();
      this.isCapturing = true;
      appLogger.info(`[${TAG}] started at ${SAMPLE_RATE}Hz mono 16-bit, source=VOICE_RECOGNITION`);
    } catch (e) {
      appLogger.error(`[${TAG}] start failed`, e);
      this.isCapturing = false;
      this.cleanup();
      throw e as Error;
    }
  }

  async stop(): Promise<void> {
    this.isCapturing = false;
    this.cancelNoDataWatchdog();
    const c = this.capturer;
    if (c) {
      try {
        if (this.readDataCallback) {
          c.off('readData', this.readDataCallback);
        }
      } catch (e) {
        appLogger.error(`[${TAG}] off readData failed`, e);
      }
      try {
        if (this.stateChangeCallback) {
          c.off('stateChange', this.stateChangeCallback);
        }
      } catch (e) {
        appLogger.error(`[${TAG}] off stateChange failed`, e);
      }

      try {
        await c.stop();
        await c.release();
      } catch (e) {
        appLogger.error(`[${TAG}] stop/release failed`, e);
      }
      this.capturer = null;
    }
    this.cleanup();
    appLogger.info(`[${TAG}] stopped`);
  }

  /**
   * 启动数据看门狗：若超时未收到任何 PCM 帧，打印警告并回调 onError
   */
  private startNoDataWatchdog(): void {
    this.cancelNoDataWatchdog();
    this.receivedAnyData = false;
    this.noDataTimerId = setTimeout(() => {
      if (!this.receivedAnyData && this.isCapturing) {
        const msg = '麦克风无数据输入（可能被占用或权限未生效）';
        appLogger.error(`[${TAG}] ${msg}`);
        if (this.onError) {
          this.onError(msg);
        }
      }
    }, NO_DATA_TIMEOUT_MS);
  }

  private cancelNoDataWatchdog(): void {
    if (this.noDataTimerId >= 0) {
      clearTimeout(this.noDataTimerId);
      this.noDataTimerId = -1;
    }
  }

  private cleanup(): void {
    if (this.capturer) {
      try {
        this.capturer.release();
      } catch (e) {
        appLogger.error(`[${TAG}] cleanup release failed`, e);
      }
      this.capturer = null;
    }
    this.readDataCallback = null;
    this.stateChangeCallback = null;
    this.receivedAnyData = false;
    this.amplitudeLogAccumulator = 0;
  }
}
