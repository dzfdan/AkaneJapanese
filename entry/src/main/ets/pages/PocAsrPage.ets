/**
 * PoC ASR 验证页（临时，Task 8 完成后删除）
 *
 * 操作流程：
 * 1. 点 "1. Init" → 加载 sherpa-onnx 离线模型 + VAD
 * 2. 点 "2. Recognize Fixed WAV" → 读 rawfile WAV，喂 PCM，看识别文本
 *
 * 注意：此页面仅用于 PoC 验证，不参与正式产品流程。
 */
import { common } from '@kit.AbilityKit';
import { SherpaAsrEngine } from '../service/SherpaAsrEngine';
import appLogger from '../utils/Logger';

const TAG = 'PocAsrPage';

@Entry
@Component
struct PocAsrPage {
  @State status: string = 'idle';
  @State result: string = '';
  @State elapsedMs: number = 0;
  private context: common.Context = getContext(this) as common.Context;

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
      Button('2. Recognize Fixed WAV').width('80%').height(48).onClick(() => this.buttonRecognizeFixedWav());
    }
    .width('100%').height('100%').justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center);
  }
}

