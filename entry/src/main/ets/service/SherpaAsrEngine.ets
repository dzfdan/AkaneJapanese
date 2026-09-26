/**
 * sherpa-onnx ASR 引擎封装（PoC 版本）
 *
 * PoC 通过条件：
 * 1. init() 不抛异常，isReady = true
 * 2. recognizeFromPcm() 返回非空字符串，且包含可识别的日文字符
 * 3. 单次识别耗时 < 5s
 *
 * 实际 HAR 1.13.3 API（与 plan/corrigenda 假设的差异，PoC 阶段已修正）：
 * - 使用 `new OfflineRecognizer(config)` 而非 `sherpaOnnx.createOfflineRecognizer(config)`
 * - 配置结构：featConfig / modelConfig{transducer{encoder,decoder,joiner}, tokens, numThreads, provider}
 * - VAD 用 `new Vad(new VadConfig(new SileroVadConfig(...), new TenVadConfig('', 0, 0, 0, 0), sampleRate, debug, numThreads, provider))`
 * - `stream.acceptWaveform({samples, sampleRate})` 接受对象形式（Samples 接口），不是两个独立参数
 * - `recognizer.getResult(stream).text` 而非 `stream.result.text` 或 `stream.getResult().text`
 * - 离线模式无 reset()，重建 stream 即可（this.stream = recognizer.createStream()）
 *
 * ArkTS 严格类型：禁止 any/unknown，所有字段必须用 HAR 实际导出的类类型
 */
import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import {
  OfflineRecognizer,
  OfflineRecognizerConfig,
  OfflineTransducerModelConfig,
  OfflineModelConfig,
  FeatureConfig,
  OfflineStream,
  Vad,
  VadConfig,
  SileroVadConfig,
  TenVadConfig,
} from 'sherpa_onnx';
import appLogger from '../utils/Logger';

const TAG = 'SherpaAsrEngine';

export class SherpaAsrEngine {
  private static instance: SherpaAsrEngine | null = null;
  private recognizer: OfflineRecognizer | null = null;
  private vad: Vad | null = null;
  private stream: OfflineStream | null = null;
  private modelDir: string = '';
  public isReady: boolean = false;

  private constructor() {}

  static getInstance(): SherpaAsrEngine {
    if (!SherpaAsrEngine.instance) {
      SherpaAsrEngine.instance = new SherpaAsrEngine();
    }
    return SherpaAsrEngine.instance;
  }

  /**
   * 初始化：首次复制模型到 getFilesDir()/asr/，加载 recognizer + vad
   */
  async init(context: common.Context): Promise<void> {
    const t0 = Date.now();
    try {
      const filesDir = context.filesDir;
      const destAsrDir = `${filesDir}/asr`;
      const zipformerDir = `${destAsrDir}/sherpa-onnx-zipformer-ja-reazonspeech-2024-08-01`;

      // 首次复制（已存在则跳过）
      if (!this.dirExists(destAsrDir)) {
        appLogger.info(`[${TAG}] first-time copy rawfile/asr -> ${destAsrDir}`);
        await this.copyRawfileToFiles(context, destAsrDir);
      } else {
        appLogger.info(`[${TAG}] model dir exists, skip copy`);
      }
      this.modelDir = zipformerDir;

      // 构建 OfflineRecognizer 配置（Zipformer ja 离线 transducer）
      const transducer = new OfflineTransducerModelConfig();
      transducer.encoder = `${zipformerDir}/encoder-epoch-99-avg-1.int8.onnx`;
      transducer.decoder = `${zipformerDir}/decoder-epoch-99-avg-1.int8.onnx`;
      transducer.joiner = `${zipformerDir}/joiner-epoch-99-avg-1.int8.onnx`;

      const modelConfig = new OfflineModelConfig();
      modelConfig.transducer = transducer;
      modelConfig.tokens = `${zipformerDir}/tokens.txt`;
      modelConfig.numThreads = 1;
      modelConfig.provider = 'cpu';

      const featConfig = new FeatureConfig();
      featConfig.sampleRate = 16000;
      featConfig.featureDim = 80;

      const recognizerConfig = new OfflineRecognizerConfig();
      recognizerConfig.featConfig = featConfig;
      recognizerConfig.modelConfig = modelConfig;

      // 创建 recognizer（Zipformer ja 离线 transducer）
      this.recognizer = new OfflineRecognizer(recognizerConfig);

      // 创建 VAD（silero）；tenVad 占位（model 留空，native 库会跳过 ten 路径）
      const silero = new SileroVadConfig(
        `${destAsrDir}/silero_vad.onnx`,
        0.5,    // threshold
        100,    // minSpeechDuration ms
        1500,   // minSilenceDuration ms
        512,    // windowSize
      );
      const tenVad = new TenVadConfig('', 0, 0, 0, 0);
      const vadConfig = new VadConfig(silero, tenVad, 16000, false, 1, 'cpu');
      this.vad = new Vad(vadConfig);

      this.stream = this.recognizer.createStream();
      this.isReady = true;
      appLogger.info(`[${TAG}] init done in ${Date.now() - t0}ms, isReady=${this.isReady}`);
    } catch (e) {
      appLogger.error(`[${TAG}] init failed`, e);
      this.isReady = false;
      throw e as Error;
    }
  }

  /**
   * PoC：直接对 PCM 样本识别（非流式）
   * @param samples 16kHz mono 16-bit PCM 样本数组
   * @param sampleRate 采样率（PoC 简化：调用方负责保证 16kHz；非 16kHz 模型可能误识别）
   * @returns 识别文本
   */
  async recognizeFromPcm(samples: Int16Array, sampleRate: number): Promise<string> {
    const recognizer: OfflineRecognizer | null = this.recognizer;
    let stream: OfflineStream | null = this.stream;
    if (!recognizer || !stream) {
      throw new Error('SherpaAsrEngine not initialized');
    }
    const t0 = Date.now();
    try {
      // 转换 Int16 -> Float32 [-1, 1]
      const floatSamples = new Float32Array(samples.length);
      for (let i = 0; i < samples.length; i++) {
        floatSamples[i] = samples[i] / 32768.0;
      }
      // OfflineStream.acceptWaveform 接受 Samples 对象 {samples, sampleRate}
      stream.acceptWaveform({ samples: floatSamples, sampleRate: sampleRate });
      recognizer.decode(stream);
      // 实际 API: recognizer.getResult(stream).text（OfflineStream 自身无 result 字段或方法）
      const result = recognizer.getResult(stream);
      const text: string = result.text ? result.text.trim() : '';
      appLogger.info(`[${TAG}] recognizeFromPcm done in ${Date.now() - t0}ms, text="${text}"`);
      // 离线模式无 reset()，重建 stream 以便下次识别
      stream = recognizer.createStream();
      this.stream = stream;
      return text;
    } catch (e) {
      appLogger.error(`[${TAG}] recognizeFromPcm failed`, e);
      throw e as Error;
    }
  }

  private dirExists(path: string): boolean {
    try {
      return fileIo.accessSync(path, fileIo.AccessModeType.EXIST);
    } catch (e) {
      return false;
    }
  }

  private async copyRawfileToFiles(context: common.Context, destDir: string): Promise<void> {
    const rm = context.resourceManager;
    await fileIo.mkdir(destDir, true);
    // 列文件需用 rawfile 描述符方式；此处用已知文件名列表（PoC 简化）
    const files: string[] = [
      'asr/silero_vad.onnx',
      'asr/sherpa-onnx-zipformer-ja-reazonspeech-2024-08-01/encoder-epoch-99-avg-1.int8.onnx',
      'asr/sherpa-onnx-zipformer-ja-reazonspeech-2024-08-01/decoder-epoch-99-avg-1.int8.onnx',
      'asr/sherpa-onnx-zipformer-ja-reazonspeech-2024-08-01/joiner-epoch-99-avg-1.int8.onnx',
      'asr/sherpa-onnx-zipformer-ja-reazonspeech-2024-08-01/tokens.txt',
    ];
    for (const f of files) {
      const content = await rm.getRawFileContent(f);
      const dest = `${context.filesDir}/${f}`;
      const file = await fileIo.open(dest, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY);
      await fileIo.write(file.fd, content.buffer);
      await fileIo.close(file);
    }
  }
}

