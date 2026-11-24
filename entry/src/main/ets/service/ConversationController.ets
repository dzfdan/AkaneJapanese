import { Scene } from '../model/Scene';
import { Sentence } from '../model/Sentence';
import { PlayerController } from './PlayerController';
import { SherpaAsrEngine } from './SherpaAsrEngine';
import { AudioRecorder } from './AudioRecorder';
import { MatchResult, matchWithReading, getSentenceReading } from './SimilarityMatcher';
import { CallbackList } from '../utils/CallbackList';
import appLogger from '../utils/Logger';

const TAG = 'ConversationController';

export type ConversationState = 'IDLE' | 'APP_SPEAKING' | 'WAITING_USER' | 'USER_SPEAKING' | 'RECOGNIZING' | 'FEEDBACK';

export interface ConversationUiState {
  state: ConversationState;
  currentScene: Scene | null;
  currentDialogueIndex: number;
  /** App 刚说的句子索引（偶数：0, 2, 4...） */
  currentSentenceIndex: number;
  /** App 刚说的句子 */
  currentSentence: Sentence | null;
  /** 用户应该说的句子（currentSentenceIndex + 1，奇数索引） */
  targetSentence: Sentence | null;
  lastMatch: MatchResult | null;
  retryCount: number;
  errorMessage: string | null;
}

type StateChangeCb = (s: ConversationUiState) => void;

export class ConversationController {
  private static instance: ConversationController | null = null;
  private state: ConversationState = 'IDLE';
  private currentScene: Scene | null = null;
  private currentDialogueIndex: number = 0;
  // App 刚说的句子索引（偶数：0, 2, 4...），用户说下一句（奇数索引）
  private currentSentenceIndex: number = 0;
  private lastMatch: MatchResult | null = null;
  private retryCount: number = 0;
  private errorMessage: string | null = null;

  private listeners: CallbackList<StateChangeCb> = new CallbackList<StateChangeCb>();
  private player: PlayerController;
  private asr: SherpaAsrEngine;
  private recorder: AudioRecorder;

  private sentenceEndBound: (s: Sentence) => void;

  private constructor() {
    this.player = PlayerController.getInstance();
    this.asr = SherpaAsrEngine.getInstance();
    this.recorder = new AudioRecorder();
    this.sentenceEndBound = (s: Sentence) => this.onAppSentenceEnd(s);
  }

  static getInstance(): ConversationController {
    if (!ConversationController.instance) {
      ConversationController.instance = new ConversationController();
    }
    return ConversationController.instance;
  }

  addOnStateChange(cb: StateChangeCb): void {
    this.listeners.add(cb);
  }

  removeOnStateChange(cb: StateChangeCb): void {
    this.listeners.remove(cb);
  }

  getUiState(): ConversationUiState {
    const sentence = this.getCurrentSentence();
    const target = this.getTargetSentence();
    return {
      state: this.state,
      currentScene: this.currentScene,
      currentDialogueIndex: this.currentDialogueIndex,
      currentSentenceIndex: this.currentSentenceIndex,
      currentSentence: sentence,
      targetSentence: target,
      lastMatch: this.lastMatch,
      retryCount: this.retryCount,
      errorMessage: this.errorMessage,
    };
  }

  /**
   * 开始对话模式
   * 对话规则：App 说偶数索引句子（0, 2, 4...），用户说奇数索引句子（1, 3, 5...）
   * App 播放完句子 N 后，等待用户说句子 N+1，并匹配句子 N+1（而非 N）。
   * 反馈后 App 继续说句子 N+2，交替进行，直到所有句子完成。
   * @param scene 场景对象
   * @param dialogueIdx 起始对话索引
   * @param sentenceIdx 起始句子索引（若为奇数会自动回退到上一个偶数，作为 App 的起始句）
   */
  async startConversation(scene: Scene, dialogueIdx: number, sentenceIdx: number): Promise<void> {
    this.currentScene = scene;
    this.currentDialogueIndex = dialogueIdx;
    // 起始索引必须是偶数（App 的轮次）。若传入奇数，回退到上一个偶数。
    let startIdx = sentenceIdx;
    if (startIdx % 2 !== 0) {
      startIdx = Math.max(0, startIdx - 1);
    }
    this.currentSentenceIndex = startIdx;
    this.retryCount = 0;
    this.lastMatch = null;
    this.errorMessage = null;
    this.player.addOnSentenceEnd(this.sentenceEndBound);
    try {
      await this.beginAppSpeaking();
    } catch (e) {
      // 播放失败时移除监听器，避免残留回调误触发
      this.player.removeOnSentenceEnd(this.sentenceEndBound);
      throw e as Error;
    }
  }

  private async beginAppSpeaking(): Promise<void> {
    if (!this.currentScene) {
      return;
    }
    this.setState('APP_SPEAKING');
    try {
      await this.player.playSentenceAndNotify(this.currentScene, this.currentDialogueIndex, this.currentSentenceIndex);
    } catch (e) {
      appLogger.error(`[${TAG}] beginAppSpeaking failed`, e);
      this.errorMessage = '播放失败';
      this.player.removeOnSentenceEnd(this.sentenceEndBound);
      this.setState('IDLE');
      throw e as Error;
    }
  }

  private onAppSentenceEnd(_sentence: Sentence): void {
    // App 说完后，检查是否存在用户的目标句子（下一句，奇数索引）
    const target = this.getTargetSentence();
    if (!target) {
      // App 已说最后一句，没有用户轮次，对话结束
      appLogger.info(`[${TAG}] onAppSentenceEnd: no target sentence, conversation done`);
      this.stopConversation();
      return;
    }
    this.beginWaitingUser().catch((e: Object) => {
      appLogger.error(`[${TAG}] beginWaitingUser failed`, e);
    });
  }

  private async beginWaitingUser(): Promise<void> {
    this.setState('WAITING_USER');
    try {
      await this.asr.startListening((text: string) => this.onAsrEndpoint(text));
      this.recorder.onData = (samples: Int16Array) => {
        if (this.state === 'WAITING_USER') {
          this.setState('USER_SPEAKING');
        }
        if (this.state === 'USER_SPEAKING') {
          this.asr.feedPcmChunk(samples);
        }
      };
      this.recorder.onError = (msg: string) => {
        appLogger.error('[' + TAG + '] recorder error: ' + msg);
        this.errorMessage = msg;
        this.setState('IDLE');
        this.recorder.stop().catch(() => {});
        this.asr.stopListening().catch(() => {});
      };
      await this.recorder.start();
    } catch (e) {
      const errMsg = e instanceof Error ? e.message : String(e);
      appLogger.error(`[${TAG}] beginWaitingUser failed: ` + errMsg, e);
      this.errorMessage = '录音启动失败：' + errMsg;
      this.setState('IDLE');
      try {
        this.asr.stopListening();
      } catch (_) {}
    }
  }

  private async onAsrEndpoint(text: string): Promise<void> {
    this.setState('RECOGNIZING');
    // await 停止录音和 ASR，避免重试时 start/stop 竞态
    try {
      await this.recorder.stop();
    } catch (e) {
      appLogger.error(`[${TAG}] recorder.stop failed`, e);
    }
    try {
      await this.asr.stopListening();
    } catch (e) {
      appLogger.error(`[${TAG}] asr.stopListening failed`, e);
    }

    // 匹配用户的目标句子（奇数索引：App 说完后的下一句 N+1，而不是 App 说的 N）
    const target = this.getTargetSentence();
    if (!target) {
      this.errorMessage = '没有目标句子';
      this.setState('IDLE');
      return;
    }

    try {
      if (!text || text.trim().length === 0) {
        this.lastMatch = { similarity: 0, isCorrect: false, userHighlighted: [], originalHighlighted: [] };
        this.errorMessage = '没听清，请重试';
        this.setState('FEEDBACK');
        return;
      }
      const result = matchWithReading(text, target.japanese, getSentenceReading(target));
      this.lastMatch = result;
      this.setState('FEEDBACK');
    } catch (e) {
      appLogger.error(`[${TAG}] match failed`, e);
      this.errorMessage = '识别异常，请重试';
      // 重启录音流水线（仅 setState 会导致麦克风已停但 UI 显示等待，用户卡死）
      this.beginWaitingUser().catch((err: Object) => {
        appLogger.error(`[${TAG}] retry after match failure failed`, err);
        this.setState('IDLE');
      });
    }
  }

  retry(): void {
    if (this.state !== 'FEEDBACK') {
      return;
    }
    // 重试同一句目标句子（用户说错的奇数索引句子），不重新播放 App 句子
    this.retryCount += 1;
    this.lastMatch = null;
    this.errorMessage = null;
    this.beginWaitingUser().catch((e: Object) => {
      appLogger.error(`[${TAG}] retry failed`, e);
    });
  }

  /**
   * 进入下一轮：App 说下一句偶数索引句子（currentSentenceIndex + 2）
   * 若当前对话已无更多句子，则进入下一组对话的第 0 句；
   * 若已无下一组对话，则结束对话。
   *
   * 允许在任意状态下调用——非 FEEDBACK 状态会先清理当前录音/播放资源，
   * 避免用户卡死在 APP_SPEAKING / WAITING_USER 等中间状态。
   */
  nextSentence(): void {
    if (!this.currentScene) {
      appLogger.warn(`[${TAG}] nextSentence: no currentScene`);
      return;
    }
    // 非 FEEDBACK 状态：先清理录音/播放资源，再跳到下一轮
    if (this.state === 'APP_SPEAKING' || this.state === 'WAITING_USER'
      || this.state === 'USER_SPEAKING' || this.state === 'RECOGNIZING') {
      appLogger.info(`[${TAG}] nextSentence: state=${this.state}, cleaning up first`);
      try { this.recorder.stop().catch(() => {}); } catch (_) {}
      try { this.asr.stopListening().catch(() => {}); } catch (_) {}
      try { this.player.pause().catch(() => {}); } catch (_) {}
    }

    const dialogue = this.currentScene.dialogues[this.currentDialogueIndex];
    if (!dialogue) {
      appLogger.warn(`[${TAG}] nextSentence: no dialogue at index ${this.currentDialogueIndex}`);
      return;
    }
    // 下一句 App 应说的索引 = 当前 + 2（跳过用户刚说的奇数句）
    const nextAppIdx = this.currentSentenceIndex + 2;
    if (nextAppIdx < dialogue.sentences.length) {
      this.currentSentenceIndex = nextAppIdx;
    } else {
      // 当前对话已无更多 App 句子，进入下一组对话的第 0 句
      if (this.currentDialogueIndex < this.currentScene.dialogues.length - 1) {
        this.currentDialogueIndex += 1;
        this.currentSentenceIndex = 0;
      } else {
        // 全部对话结束
        appLogger.info(`[${TAG}] nextSentence: all dialogues done`);
        this.stopConversation();
        return;
      }
    }
    this.lastMatch = null;
    this.retryCount = 0;
    this.errorMessage = null;
    this.beginAppSpeaking().catch((e: Object) => {
      appLogger.error(`[${TAG}] nextSentence beginAppSpeaking failed`, e);
    });
  }

  stopConversation(): void {
    this.recorder.stop().catch(() => {
    });
    this.asr.stopListening().catch(() => {
    });
    this.player.pause().catch(() => {
    });
    this.player.removeOnSentenceEnd(this.sentenceEndBound);
    this.state = 'IDLE';
    this.lastMatch = null;
    this.errorMessage = null;
    this.notifyStateChange();
  }

  /**
   * 获取 App 刚说的句子（偶数索引）
   */
  private getCurrentSentence(): Sentence | null {
    if (!this.currentScene) {
      return null;
    }
    const dialogue = this.currentScene.dialogues[this.currentDialogueIndex];
    if (!dialogue) {
      return null;
    }
    if (this.currentSentenceIndex < 0 || this.currentSentenceIndex >= dialogue.sentences.length) {
      return null;
    }
    return dialogue.sentences[this.currentSentenceIndex];
  }

  /**
   * 获取用户应该说的句子（App 句子的下一句，奇数索引）
   * 若不存在（App 已说最后一句），返回 null
   */
  private getTargetSentence(): Sentence | null {
    if (!this.currentScene) {
      return null;
    }
    const dialogue = this.currentScene.dialogues[this.currentDialogueIndex];
    if (!dialogue) {
      return null;
    }
    const targetIdx = this.currentSentenceIndex + 1;
    if (targetIdx < 0 || targetIdx >= dialogue.sentences.length) {
      return null;
    }
    return dialogue.sentences[targetIdx];
  }

  private setState(s: ConversationState): void {
    this.state = s;
    appLogger.info(`[${TAG}] state -> ${s}`);
    this.notifyStateChange();
  }

  private notifyStateChange(): void {
    const ui = this.getUiState();
    this.listeners.notify((cb: StateChangeCb) => cb(ui));
  }
}
