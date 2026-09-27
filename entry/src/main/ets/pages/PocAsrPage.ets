/**
 * PoC ASR 验证页（临时，Task 8 完成后删除）
 *
 * 操作流程：
 * 1. 点 "1. Init" → 加载 sherpa-onnx 离线模型 + VAD
 * 2. 点 "2. Recognize Fixed WAV" → 读 rawfile WAV，喂 PCM，看识别文本
 *
 * 注意：此页面仅用于 PoC 验证，不参与正式产品流程。
 */
import { common, abilityAccessCtrl } from '@kit.AbilityKit';
import { SherpaAsrEngine } from '../service/SherpaAsrEngine';
import { AudioRecorder } from '../service/AudioRecorder';
import appLogger from '../utils/Logger';

const TAG = 'PocAsrPage';

@Entry
@Component
struct PocAsrPage {
  @State status: string = 'idle';
  @State result: string = '';
  @State elapsedMs: number = 0;
  @State listening: boolean = false;
  private context: common.Context = getContext(this) as common.Context;
  private recorder: AudioRecorder | null = null;

  async buttonInit() {
    this.status = 'init...';
    this.result = '';
    this.elapsedMs = 0;
    try {
      await SherpaAsrEngine.getInstance().init(this.context);
      this.status = 'ready: ' + SherpaAsrEngine.getInstance().isReady;
    } catch (e) {
      appLogger.error(`[${TAG}] init failed`, e);
      this.status = 'init failed: ' + (e as Error).message;
    }
  }

  async buttonToggleListening() {
    if (this.listening) {
      // 停止监听
      this.listening = false;
      this.status = 'stopping...';
      try {
        if (this.recorder) {
          await this.recorder.stop();
          this.recorder = null;
        }
        await SherpaAsrEngine.getInstance().stopListening();
        this.status = 'stopped';
      } catch (e) {
        appLogger.error(`[${TAG}] stop listening failed`, e);
        this.status = 'stop failed: ' + (e as Error).message;
      }
      return;
    }
    // 开始监听：请求麦克风权限
    this.status = 'requesting mic permission...';
    try {
      const atManager = abilityAccessCtrl.createAtManager();
      const permResult = await atManager.requestPermissionsFromUser(this.context, ['ohos.permission.MICROPHONE']);
      const granted = permResult.authResults && permResult.authResults[0] === 0;
      if (!granted) {
        this.status = 'mic permission denied';
        return;
      }
      // 启动 VAD 监听
      await SherpaAsrEngine.getInstance().startListening((text: string) => {
        this.result = text;
      });
      // 创建 AudioRecorder 并 wire 到 engine
      this.recorder = new AudioRecorder();
      this.recorder.onData = (samples: Int16Array) => {
        SherpaAsrEngine.getInstance().feedPcmChunk(samples);
      };
      await this.recorder.start();
      this.listening = true;
      this.status = 'listening...';
    } catch (e) {
      appLogger.error(`[${TAG}] start listening failed`, e);
      this.status = 'listen failed: ' + (e as Error).message;
      this.listening = false;
      if (this.recorder) {
        this.recorder.stop().catch(() => {});
        this.recorder = null;
      }
    }
  }

  async buttonRecognizeFixedWav() {
    this.status = 'recognizing...';
    this.result = '';
    this.elapsedMs = 0;
    try {
      const rm = this.context.resourceManager;
      // rawfile 中存在的实际 WAV 文件
      const buf = await rm.getRawFileContent('audio/scene-001-normal.wav');
      // 跳过 44 字节 WAV 头，取后续 16-bit PCM
      const samples: Int16Array = new Int16Array(buf.buffer.slice(44));
      // 从 WAV 头读采样率（offset 24, 4 字节 little-endian）
      const view = new DataView(buf.buffer);
      let sampleRate = 22050;
      try {
        sampleRate = view.getUint32(24, true);
      } catch (e) {
        appLogger.warn(`[${TAG}] read sampleRate from WAV header failed, fallback to ${sampleRate}`);
      }
      appLogger.info(`[${TAG}] wav samples=${samples.length}, sampleRate=${sampleRate}`);
      const t0 = Date.now();
      const text = await SherpaAsrEngine.getInstance().recognizeFromPcm(samples, sampleRate);
      this.elapsedMs = Date.now() - t0;
      this.result = text || '(empty)';
      this.status = 'done';
    } catch (e) {
      appLogger.error(`[${TAG}] recognize failed`, e);
      this.status = 'recognize failed: ' + (e as Error).message;
    }
  }

  build() {
    Column() {
      Text('PoC ASR').fontSize(24).margin({ bottom: 24 });
      Text(`status: ${this.status}`).fontSize(14).margin({ bottom: 12 });
      Text(`elapsed: ${this.elapsedMs}ms`).fontSize(14).margin({ bottom: 12 });
      Text(`result: ${this.result}`).fontSize(14).margin({ bottom: 24 }).width('90%');
      Button('1. Init').width('80%').height(48).margin({ bottom: 12 }).onClick(() => this.buttonInit());
      Button('2. Recognize Fixed WAV').width('80%').height(48).margin({ bottom: 12 }).onClick(() => this.buttonRecognizeFixedWav());
      Button(this.listening ? '3. Stop Listening' : '3. Start Listening').width('80%').height(48).onClick(() => this.buttonToggleListening());
    }
    .width('100%').height('100%').justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center);
  }
}

