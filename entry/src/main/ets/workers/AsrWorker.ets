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
interface StopMsg { type: 'stop'; }
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
      appLogger.info(`[${TAG}] start listening`);
      break;
    case 'feed':
      handleFeed(data as FeedMsg);
      break;
    case 'stop':
      handleStop();
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

    const silero = new SileroVadConfig(
      `${msg.destAsrDir}/silero_vad.onnx`,
      0.5,    // threshold (语音概率阈值)
      0.25,   // minSpeechDuration: 0.25 秒 (250ms)
      0.5,    // minSilenceDuration: 0.5 秒 (500ms)
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
    feedCount++;
    if (feedCount % 30 === 0) {
      appLogger.info(`[${TAG}] feed #${feedCount} maxAbs=${maxAbs.toFixed(4)} isDetected=${v.isDetected()} isEmpty=${v.isEmpty()}`);
    }
    drainVadSegments();
  } catch (e) {
    appLogger.error(`[${TAG}] worker feed failed`, e);
  }
}

function drainVadSegments(): void {
  const v = vad;
  if (!v) {
    return;
  }
  // 无论 isDetected() 状态如何，只要队列非空就排空
  // 语音段结束时 isDetected()=false 但队列中有已完成的段
  while (!v.isEmpty()) {
    const segment = v.front();
    v.pop();
    processSegment(segment.samples);
  }
}

function processSegment(samples: Float32Array): void {
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
    if (isListening) {
      appLogger.info(`[${TAG}] worker endpoint text="${text}"`);
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

function handleStop(): void {
  isListening = false;
  const v = vad;
  if (v) {
    try {
      v.flush();
      // flush 强制输出残留段，但可能不触发 isDetected()，此处直接排空队列
      while (!v.isEmpty()) {
        const segment = v.front();
        v.pop();
        processSegment(segment.samples);
      }
    } catch (e) {
      appLogger.error(`[${TAG}] worker stop flush failed`, e);
    }
  }
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