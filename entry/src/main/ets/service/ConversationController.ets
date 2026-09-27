import { Scene } from '../model/Scene';
import { Sentence } from '../model/Sentence';
import { PlayerController } from './PlayerController';
import { SherpaAsrEngine } from './SherpaAsrEngine';
import { AudioRecorder } from './AudioRecorder';
import { MatchResult, match } from './SimilarityMatcher';
import { CallbackList } from '../utils/CallbackList';
import appLogger from '../utils/Logger';

const TAG = 'ConversationController';

export type ConversationState = 'IDLE' | 'APP_SPEAKING' | 'WAITING_USER' | 'USER_SPEAKING' | 'RECOGNIZING' | 'FEEDBACK';

export interface ConversationUiState {
  state: ConversationState;
  currentScene: Scene | null;
  currentDialogueIndex: number;
  currentSentenceIndex: number;
  currentSentence: Sentence | null;
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
    return {
      state: this.state,
      currentScene: this.currentScene,
      currentDialogueIndex: this.currentDialogueIndex,
      currentSentenceIndex: this.currentSentenceIndex,
      currentSentence: sentence,
      lastMatch: this.lastMatch,
      retryCount: this.retryCount,
      errorMessage: this.errorMessage,
    };
  }

  async startConversation(scene: Scene, dialogueIdx: number, sentenceIdx: number): Promise<void> {
    this.currentScene = scene;
    this.currentDialogueIndex = dialogueIdx;
    this.currentSentenceIndex = sentenceIdx;
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
      this.setState('IDLE');
    }
  }

  private onAppSentenceEnd(_sentence: Sentence): void {
    this.beginWaitingUser().catch((e: Object) => {
      appLogger.error(`[${TAG}] beginWaitingUser failed`, e);
    });
  }

  private async beginWaitingUser(): Promise<void> {
    this.setState('WAITING_USER');
    try {
      await this.asr.startListening((text: string) => this.onAsrEndpoint(text));
      this.recorder.onData = (samples: Int16Array) => {
        if (this.state === 'WAITING_USER' || this.state === 'USER_SPEAKING') {
          this.setState('USER_SPEAKING');
          this.asr.feedPcmChunk(samples);
        }
      };
      await this.recorder.start();
    } catch (e) {
      appLogger.error(`[${TAG}] beginWaitingUser failed`, e);
      this.errorMessage = '录音启动失败';
      this.setState('IDLE');
    }
  }

  private onAsrEndpoint(text: string): void {
    this.setState('RECOGNIZING');
    this.recorder.stop().catch((e: Object) => {
      appLogger.error(`[${TAG}] recorder.stop failed`, e);
    });
    this.asr.stopListening().catch((e: Object) => {
      appLogger.error(`[${TAG}] asr.stopListening failed`, e);
    });

    const sentence = this.getCurrentSentence();
    if (!sentence) {
      this.errorMessage = '没有当前句子';
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
      const result = match(text, sentence.japanese);
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
    this.retryCount += 1;
    this.lastMatch = null;
    this.errorMessage = null;
    this.beginWaitingUser().catch((e: Object) => {
      appLogger.error(`[${TAG}] retry failed`, e);
    });
  }

  nextSentence(): void {
    if (this.state !== 'FEEDBACK') {
      return;
    }
    if (!this.currentScene) {
      return;
    }
    const dialogue = this.currentScene.dialogues[this.currentDialogueIndex];
    if (!dialogue) {
      return;
    }
    if (this.currentSentenceIndex < dialogue.sentences.length - 1) {
      this.currentSentenceIndex += 1;
    } else {
      if (this.currentDialogueIndex < this.currentScene.dialogues.length - 1) {
        this.currentDialogueIndex += 1;
        this.currentSentenceIndex = 0;
      } else {
        this.stopConversation();
        return;
      }
    }
    this.lastMatch = null;
    this.retryCount = 0;
    this.errorMessage = null;
    this.beginAppSpeaking().catch((e: Object) => {
      appLogger.error(`[${TAG}] nextSentence failed`, e);
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

