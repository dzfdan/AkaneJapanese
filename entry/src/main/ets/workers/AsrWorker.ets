/**
 * ASR Worker：在子线程执行 sherpa_onnx native 操作
 *
 * 根因：OfflineRecognizer/Vad 构造是同步 native 调用，加载 ONNX 模型阻塞 6s+，
 * 主线程会触发鸿蒙 watchdog THREAD_BLOCK_3S/6S 被杀进程（AppFreeze）。
 * 本 Worker 把所有 native 操作移到子线程，主线程只负责 UI 和传递 PCM 数据。
 *
 * 消息协议（主线程 -> Worker）：
 *   {type:'init', modelDir, destAsrDir} -> 创建 recognizer/vad/stream
 *   {type:'start'}                      -> 开始监听端点
 *   {type:'feed', samples: ArrayBuffer} -> 喂 Int16 PCM 块（16kHz mono）
 *   {type:'stop'}                       -> 停止并 flush 残留段
 *   {type:'recognize', samples}         -> PoC 整段识别
 *   {type:'release'}                    -> 释放资源
 *
 * 消息协议（Worker -> 主线程）：
 *   {type:'init_done'} | {type:'init_failed', error}
 *   {type:'endpoint', text}             -> 检测到端点并完成识别
 *   {type:'stop_done'}
 *   {type:'recognize_done', text}
 */
import { MessageEvents, ThreadWorkerGlobalScope, worker } from '@kit.ArkTS';
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

const TAG = 'AsrWorker';

// ======== 主线程 -> Worker 消息 ========
interface InitMsg {
  type: 'init';
  modelDir: string;
  destAsrDir: string;
}
interface StartMsg { type: 'start'; }
interface FeedMsg {
  type: 'feed';
  samples: ArrayBuffer; // Int16 PCM 16kHz mono
}
interface StopMsg {
  type: 'stop';
  recognize: boolean; // true: flush 后把残留语音段识别并回传 endpoint；false: 丢弃
}
interface RecognizeMsg {
  type: 'recognize';
  samples: ArrayBuffer; // Int16 PCM 16kHz mono
}
interface ReleaseMsg { type: 'release'; }
interface MsgWithType {
  type: string;
}

// ======== Worker -> 主线程 消息 ========
interface InitDoneMsg { type: 'init_done'; }
interface InitFailedMsg { type: 'init_failed'; error: string; }
interface EndpointMsg { type: 'endpoint'; text: string; }
interface StopDoneMsg { type: 'stop_done'; }
interface RecognizeDoneMsg { type: 'recognize_done'; text: string; }

// ======== Worker 状态 ========
let recognizer: OfflineRecognizer | null = null;
let vad: Vad | null = null;
let stream: OfflineStream | null = null;
let isListening: boolean = false;
let feedCount: number = 0;
// 自上次识别以来累积的全部音频。VAD 只判定"何时说完"（端点时机），
// 识别内容用完整缓冲 —— 避免 VAD 段起点检测延迟裁掉句子开头（只识别出后半段）
let pendingSamples: Float32Array[] = [];

const w: ThreadWorkerGlobalScope = worker.workerPort;

w.onmessage = (e: MessageEvents): void => {
  const data = e.data as MsgWithType;
  const type: string = data.type;
  switch (type) {
    case 'init':
      handleInit(data as InitMsg);
      break;
    case 'start':
      isListening = true;
      feedCount = 0;
      pendingSamples = [];
      appLogger.info(`[${TAG}] start listening`);
      break;
    case 'feed':
      handleFeed(data as FeedMsg);
      break;
    case 'stop':
      handleStop(data as StopMsg);
      break;
    case 'recognize':
      handleRecognize(data as RecognizeMsg);
      break;
    case 'release':
      handleRelease();
      break;
    default:
      break;
  }
};

function handleInit(msg: InitMsg): void {
  const t0 = Date.now();
  try {
    appLogger.info(`[${TAG}] worker init start`);
    const zipformerDir = msg.modelDir;

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

    appLogger.info(`[${TAG}] worker creating OfflineRecognizer...`);
    recognizer = new OfflineRecognizer(recognizerConfig);
    appLogger.info(`[${TAG}] worker OfflineRecognizer created`);

    // 语言学习场景调优：
    // - threshold 0.35：学习者在麦克风前常轻声朗读，0.5 会把轻声语音判为静音丢失开头
    // - minSilenceDuration 1.0s：学习者说长句时词间停顿常 >0.5s，
    //   0.5s 会在句子中间误触发端点（如只说「はい」停顿后整句被截断，识别率极低）
    // - minSpeechDuration 0.3s：过滤咳嗽/碰撞等瞬时噪声
    const silero = new SileroVadConfig(
      `${msg.destAsrDir}/silero_vad.onnx`,
      0.35,   // threshold (语音概率阈值)
      0.3,    // minSpeechDuration: 0.3 秒 (300ms)
      1.0,    // minSilenceDuration: 1.0 秒 —— 容忍学习者句中停顿
      512,    // windowSize: 512 samples (16kHz 下 32ms)
    );
    const tenVad = new TenVadConfig('', 0, 0, 0, 0);
    const vadConfig = new VadConfig(silero, tenVad, 16000, false, 1, 'cpu');
    appLogger.info(`[${TAG}] worker creating Vad...`);
    vad = new Vad(vadConfig);
    appLogger.info(`[${TAG}] worker Vad created`);

    const r = recognizer;
    if (r) {
      stream = r.createStream();
    }
    appLogger.info(`[${TAG}] worker init done in ${Date.now() - t0}ms`);
    const doneMsg: InitDoneMsg = { type: 'init_done' };
    w.postMessage(doneMsg);
  } catch (e) {
    appLogger.error(`[${TAG}] worker init failed`, e);
    recognizer = null;
    vad = null;
    stream = null;
    const err = e as Error;
    const failMsg: InitFailedMsg = { type: 'init_failed', error: err.message };
    w.postMessage(failMsg);
  }
}

function handleFeed(msg: FeedMsg): void {
  const v = vad;
  if (!v || !isListening) {
    return;
  }
  try {
    const int16 = new Int16Array(msg.samples);
    const floatSamples = new Float32Array(int16.length);
    let maxAbs = 0;
    for (let i = 0; i < int16.length; i++) {
      floatSamples[i] = int16[i] / 32768.0;
      const absVal = floatSamples[i] < 0 ? -floatSamples[i] : floatSamples[i];
      if (absVal > maxAbs) {
        maxAbs = absVal;
      }
    }
    v.acceptWaveform(floatSamples);
    pendingSamples.push(floatSamples);
    feedCount++;
    if (feedCount % 30 === 0) {
      appLogger.info(`[${TAG}] feed #${feedCount} maxAbs=${maxAbs.toFixed(4)} isDetected=${v.isDetected()} isEmpty=${v.isEmpty()}`);
    }
    drainVadSegments();
  } catch (e) {
    appLogger.error(`[${TAG}] worker feed failed`, e);
  }
}

function concatPending(): Float32Array {
  let total = 0;
  for (const chunk of pendingSamples) {
    total += chunk.length;
  }
  const out = new Float32Array(total);
  let offset = 0;
  for (const chunk of pendingSamples) {
    out.set(chunk, offset);
    offset += chunk.length;
  }
  return out;
}

function drainVadSegments(): void {
  const v = vad;
  if (!v) {
    return;
  }
  // VAD 段仅作为"一句话结束"的触发信号，段样本弃用；
  // 识别改用 pendingSamples 完整音频（含 VAD 起点之前被裁掉的部分）
  while (!v.isEmpty()) {
    v.pop();
    if (pendingSamples.length > 0) {
      processSegment(concatPending(), false);
      pendingSamples = [];
    }
  }
}

function processSegment(samples: Float32Array, postAlways: boolean): void {
  const r = recognizer;
  const currentStream = stream;
  if (!r || !currentStream) {
    return;
  }
  try {
    currentStream.acceptWaveform({ samples: samples, sampleRate: 16000 });
    r.decode(currentStream);
    const result = r.getResult(currentStream);
    const text: string = result.text ? result.text.trim() : '';
    // 离线模式无 reset()，重建 stream 以便下一段识别
    stream = r.createStream();
    if (isListening || postAlways) {
      appLogger.info(`[${TAG}] worker endpoint text="${text}" postAlways=${postAlways}`);
      const epMsg: EndpointMsg = { type: 'endpoint', text: text };
      w.postMessage(epMsg);
    }
  } catch (e) {
    appLogger.error(`[${TAG}] worker processSegment failed`, e);
    // 出错也重建 stream，避免脏状态
    try {
      stream = r.createStream();
    } catch (e2) {
      appLogger.error(`[${TAG}] worker recreate stream after failure failed`, e2);
    }
  }
}

function handleStop(msg: StopMsg): void {
  isListening = false;
  const v = vad;
  if (v) {
    try {
      v.flush();
      // 清空 VAD 段队列（段样本不再用于识别）
      while (!v.isEmpty()) {
        v.pop();
      }
    } catch (e) {
      appLogger.error(`[${TAG}] worker stop flush failed`, e);
    }
  }
  // 兜底：recognize=true 时无论 VAD 是否检出语音段，都把缓冲的全部音频送识别，
  // 防止 VAD 漏检轻声开头/短句导致内容丢失
  if (msg.recognize && pendingSamples.length > 0) {
    processSegment(concatPending(), true);
  }
  pendingSamples = [];
  appLogger.info(`[${TAG}] worker stop done`);
  const doneMsg: StopDoneMsg = { type: 'stop_done' };
  w.postMessage(doneMsg);
}

function handleRecognize(msg: RecognizeMsg): void {
  const r = recognizer;
  const currentStream = stream;
  if (!r || !currentStream) {
    const doneMsg: RecognizeDoneMsg = { type: 'recognize_done', text: '' };
    w.postMessage(doneMsg);
    return;
  }
  try {
    const t0 = Date.now();
    const int16 = new Int16Array(msg.samples);
    const floatSamples = new Float32Array(int16.length);
    for (let i = 0; i < int16.length; i++) {
      floatSamples[i] = int16[i] / 32768.0;
    }
    currentStream.acceptWaveform({ samples: floatSamples, sampleRate: 16000 });
    r.decode(currentStream);
    const result = r.getResult(currentStream);
    const text: string = result.text ? result.text.trim() : '';
    // 离线模式无 reset()，重建 stream 以便下次识别
    stream = r.createStream();
    appLogger.info(`[${TAG}] worker recognize_done in ${Date.now() - t0}ms, text="${text}"`);
    const doneMsg: RecognizeDoneMsg = { type: 'recognize_done', text: text };
    w.postMessage(doneMsg);
  } catch (e) {
    appLogger.error(`[${TAG}] worker recognize failed`, e);
    try {
      stream = r.createStream();
    } catch (e2) {
      appLogger.error(`[${TAG}] worker recreate stream failed`, e2);
    }
    const doneMsg: RecognizeDoneMsg = { type: 'recognize_done', text: '' };
    w.postMessage(doneMsg);
  }
}

function handleRelease(): void {
  recognizer = null;
  vad = null;
  stream = null;
  isListening = false;
  appLogger.info(`[${TAG}] worker released`);
}