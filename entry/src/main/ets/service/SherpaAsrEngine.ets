/**
 * sherpa-onnx ASR 引擎封装（Worker 代理版本）
 *
 * 所有 native 操作（OfflineRecognizer/Vad 构造、acceptWaveform、decode、getResult）
 * 都在 AsrWorker 子线程执行，主线程不阻塞，避免 AppFreeze (THREAD_BLOCK_6S)。
 *
 * 根因：OfflineRecognizer/Vad 构造是同步 native 调用，加载 ONNX 模型阻塞 6s+，
 * 在主线程触发会触发鸿蒙 watchdog THREAD_BLOCK_3S -> THREAD_BLOCK_6S -> 系统杀进程。
 * 延迟初始化方案无效（点击按钮时仍阻塞主线程），唯一可靠方案是 Worker 子线程。
 *
 * 对外接口不变：init / startListening / feedPcmChunk / stopListening / recognizeFromPcm / isReady
 */
import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { ErrorEvent, MessageEvents, worker } from '@kit.ArkTS';
import appLogger from '../utils/Logger';

const TAG = 'SherpaAsrEngine';

// ======== 主线程 -> Worker 请求消息 ========
interface InitReqMsg {
  type: 'init';
  modelDir: string;
  destAsrDir: string;
}
interface StartReqMsg { type: 'start'; }
interface FeedReqMsg {
  type: 'feed';
  samples: ArrayBuffer;
}
interface StopReqMsg {
  type: 'stop';
  recognize: boolean; // true: flush 后把残留语音段识别并回传 endpoint；false: 丢弃
}
interface RecognizeReqMsg {
  type: 'recognize';
  samples: ArrayBuffer;
}
interface MsgWithType { type: string; }

// ======== Worker -> 主线程 回复消息 ========
interface InitDoneMsg { type: 'init_done'; }
interface InitFailedMsg { type: 'init_failed'; error: string; }
interface EndpointMsg { type: 'endpoint'; text: string; }
interface StopDoneMsg { type: 'stop_done'; }
interface RecognizeDoneMsg { type: 'recognize_done'; text: string; }

export class SherpaAsrEngine {
  private static instance: SherpaAsrEngine | null = null;
  private wk: worker.ThreadWorker | null = null;
  private modelDir: string = '';
  public isReady: boolean = false;

  // ======== VAD 流水线状态 ========
  private isListening: boolean = false;
  private onEndpointCb: ((text: string) => void) | null = null;

  // ======== Promise 等待回调 ========
  private pendingInitResolve: (() => void) | null = null;
  private pendingInitReject: ((e: Error) => void) | null = null;
  private pendingStopResolves: Array<() => void> = [];
  // 监听会话代际号：startListening 递增；stopListening 仅在代际未变时清理状态，
  // 避免迟到的旧 stop 完成回调把新会话的 isListening/onEndpointCb 冲掉
  // （该竞态曾导致录音启动后 feedPcmChunk 全部静默丢弃，识别结果恒为空）
  private listenGeneration: number = 0;
  private pendingRecognizeResolve: ((text: string) => void) | null = null;
  // init 进行中的 Promise（防止并发 init 重复创建 Worker）
  private pendingInitPromise: Promise<void> | null = null;

  private constructor() {}

  static getInstance(): SherpaAsrEngine {
    if (!SherpaAsrEngine.instance) {
      SherpaAsrEngine.instance = new SherpaAsrEngine();
    }
    return SherpaAsrEngine.instance;
  }

  /**
   * 初始化：首次复制模型到 getFilesDir()/asr/，创建 Worker 在子线程加载 native 模型
   * 并发调用时复用同一个 Promise，避免重复创建 Worker
   */
  async init(context: common.Context): Promise<void> {
    if (this.isReady) {
      appLogger.info(`[${TAG}] already initialized, skip`);
      return;
    }
    if (this.pendingInitPromise) {
      appLogger.info(`[${TAG}] init in progress, wait same promise`);
      return this.pendingInitPromise;
    }
    const p: Promise<void> = this.initInternal(context);
    this.pendingInitPromise = p;
    try {
      await p;
    } finally {
      this.pendingInitPromise = null;
    }
  }

  private async initInternal(context: common.Context): Promise<void> {
    const t0 = Date.now();
    try {
      const filesDir = context.filesDir;
      const destAsrDir = `${filesDir}/asr`;
      const zipformerDir = `${destAsrDir}/sherpa-onnx-zipformer-ja-reazonspeech-2024-08-01`;

      // 首次复制（验证关键模型文件 tokens.txt 存在才算就绪，避免不完整目录被跳过）
      const tokensPath = `${zipformerDir}/tokens.txt`;
      if (!this.dirExists(tokensPath)) {
        appLogger.info(`[${TAG}] first-time copy rawfile/asr -> ${destAsrDir}`);
        await this.copyRawfileToFiles(context, destAsrDir);
      } else {
        appLogger.info(`[${TAG}] model files exist, skip copy`);
      }
      this.modelDir = zipformerDir;

      // 创建 Worker（子线程加载 native 模型，主线程不阻塞）
      appLogger.info(`[${TAG}] creating Worker...`);
      this.wk = new worker.ThreadWorker('entry/ets/workers/AsrWorker.ets');
      this.wk.onmessage = (e: MessageEvents): void => this.onWorkerMessage(e);
      this.wk.onerror = (e: ErrorEvent): void => {
        appLogger.error(`[${TAG}] Worker error`, e);
      };

      // 发送 init，等待子线程加载完成
      await new Promise<void>((resolve, reject): void => {
        this.pendingInitResolve = resolve;
        this.pendingInitReject = reject;
        const wk = this.wk;
        if (wk) {
          const initMsg: InitReqMsg = { type: 'init', modelDir: zipformerDir, destAsrDir: destAsrDir };
          wk.postMessage(initMsg);
        } else {
          reject(new Error('worker not created'));
        }
      });

      this.isReady = true;
      appLogger.info(`[${TAG}] init done in ${Date.now() - t0}ms, isReady=${this.isReady}`);
    } catch (e) {
      appLogger.error(`[${TAG}] init failed`, e);
      this.isReady = false;
      throw e as Error;
    }
  }

  private onWorkerMessage(e: MessageEvents): void {
    const data = e.data as MsgWithType;
    const type: string = data.type;
    switch (type) {
      case 'init_done': {
        const r = this.pendingInitResolve;
        this.pendingInitResolve = null;
        this.pendingInitReject = null;
        if (r) {
          r();
        }
        break;
      }
      case 'init_failed': {
        const rej = this.pendingInitReject;
        this.pendingInitResolve = null;
        this.pendingInitReject = null;
        if (rej) {
          rej(new Error((data as InitFailedMsg).error));
        }
        break;
      }
      case 'endpoint': {
        if (this.isListening && this.onEndpointCb) {
          const text: string = (data as EndpointMsg).text;
          appLogger.info(`[${TAG}] endpoint text="${text}"`);
          this.onEndpointCb(text);
        }
        break;
      }
      case 'stop_done': {
        const rs = this.pendingStopResolves;
        this.pendingStopResolves = [];
        for (const r of rs) {
          r();
        }
        break;
      }
      case 'recognize_done': {
        const r = this.pendingRecognizeResolve;
        this.pendingRecognizeResolve = null;
        if (r) {
          r((data as RecognizeDoneMsg).text);
        }
        break;
      }
      default:
        break;
    }
  }

  /**
   * PoC：直接对 PCM 样本识别（非流式）
   * @param samples 16kHz mono 16-bit PCM 样本数组
   * @param sampleRate 采样率（PoC 简化：调用方负责保证 16kHz；非 16kHz 模型可能误识别）
   * @returns 识别文本
   */
  async recognizeFromPcm(samples: Int16Array, sampleRate: number): Promise<string> {
    const wk = this.wk;
    if (!wk || !this.isReady) {
      throw new Error('SherpaAsrEngine not initialized');
    }
    // 复制 buffer 避免转移所有权影响调用方
    const buf: ArrayBuffer = samples.buffer.slice(samples.byteOffset, samples.byteOffset + samples.byteLength);
    return new Promise<string>((resolve): void => {
      this.pendingRecognizeResolve = resolve;
      const msg: RecognizeReqMsg = { type: 'recognize', samples: buf };
      wk.postMessage(msg);
    });
  }

  /**
   * 启动 VAD 监听。
   * @param onEndpoint 检测到完整语音段端点时回调，参数为识别文本
   */
  async startListening(onEndpoint: (text: string) => void): Promise<void> {
    const wk = this.wk;
    if (!wk || !this.isReady) {
      throw new Error('SherpaAsrEngine not initialized');
    }
    this.listenGeneration++;
    this.onEndpointCb = onEndpoint;
    this.isListening = true;
    appLogger.info(`[${TAG}] startListening gen=${this.listenGeneration}`);
    const msg: StartReqMsg = { type: 'start' };
    wk.postMessage(msg);
  }

  /**
   * 停止 VAD 监听。
   * @param recognizePending true: flush 残留语音段并识别，结果经 onEndpoint 回调
   *                         （Worker 先回传 endpoint 再回传 stop_done）；
   *                         false: 丢弃残留语音段
   */
  async stopListening(recognizePending: boolean = false): Promise<void> {
    const wk = this.wk;
    if (!wk) {
      this.isListening = false;
      this.onEndpointCb = null;
      appLogger.info(`[${TAG}] stopListening (no worker)`);
      return;
    }
    // 记录调用时的会话代际；若 await 期间有新的 startListening，代际会变，
    // 尾部清理必须跳过，避免迟到的旧 stop 把新会话的监听状态冲掉
    const gen = this.listenGeneration;
    // recognize 模式下保留监听状态，让 flush 产生的 endpoint 能透传给回调
    if (!recognizePending) {
      this.isListening = false;
    }
    await new Promise<void>((resolve): void => {
      this.pendingStopResolves.push(resolve);
      const msg: StopReqMsg = { type: 'stop', recognize: recognizePending };
      wk.postMessage(msg);
    });
    if (this.listenGeneration === gen) {
      this.isListening = false;
      this.onEndpointCb = null;
    }
    appLogger.info(`[${TAG}] stopListening recognize=${recognizePending} gen=${gen} curGen=${this.listenGeneration}`);
  }

  /**
   * 喂 PCM 块给 Worker（同步方法，由 AudioRecorder.onData 回调触发）。
   * Worker 中 VAD 检测到端点后取出语音段，解码并回调识别文本。
   * @param samples 16-bit PCM 样本（Int16Array），采样率必须为 16000
   */
  feedPcmChunk(samples: Int16Array): void {
    const wk = this.wk;
    if (!wk || !this.isListening) {
      return;
    }
    try {
      // 复制 buffer 避免转移所有权影响 AudioRecorder 后续使用
      const buf: ArrayBuffer = samples.buffer.slice(samples.byteOffset, samples.byteOffset + samples.byteLength);
      const msg: FeedReqMsg = { type: 'feed', samples: buf };
      wk.postMessage(msg);
    } catch (e) {
      appLogger.error(`[${TAG}] feedPcmChunk failed`, e);
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
    try {
      await fileIo.mkdir(destDir, true);
    } catch (e) {
      // 目录已存在时忽略
    }
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
      const parentDir = dest.substring(0, dest.lastIndexOf('/'));
      try {
        await fileIo.mkdir(parentDir, true);
      } catch (e) {
        // 目录已存在时忽略
      }
      // 先删除已存在的文件（避免 CREATE 模式报 "File Exists"）
      try {
        await fileIo.unlink(dest);
      } catch (e) {
        // 文件不存在时忽略
      }
      const file = await fileIo.open(dest, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY);
      await fileIo.write(file.fd, content.buffer);
      await fileIo.close(file);
    }
  }
}