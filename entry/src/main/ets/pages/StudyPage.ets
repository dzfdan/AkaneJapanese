/**
 * 驻车学习详情页
 * 左右分栏布局，包含对话、跟读练习、测验三个 Tab
 */

import { ThemeColors } from '../constants/ThemeConstants';
import { AppConstants } from '../constants/AppConstants';
import { Scene } from '../model/Scene';
import { Dialogue } from '../model/Dialogue';
import { Sentence } from '../model/Sentence';
import { FuriganaText } from '../components/FuriganaText';
import { QuizItem } from '../model/QuizItem';
import { SceneRepository } from '../service/SceneRepository';
import { SettingsStore } from '../service/SettingsStore';
import { ProgressStore } from '../service/ProgressStore';
import { PlayerController, PlayerUiState } from '../service/PlayerController';
import { QuizCard } from '../components/QuizCard';
import { PlayerBar } from '../components/PlayerBar';
import { ConversationTab } from '../components/ConversationTab';
import { SkipBackIcon, SkipNextIcon, PlayIcon, SlowIcon, RecordIcon } from '../components/PlayerIcons';
import { ConversationController } from '../service/ConversationController';
import { AudioRecorder } from '../service/AudioRecorder';
import { SherpaAsrEngine } from '../service/SherpaAsrEngine';
import { MatchResult, match, matchWithReading, getSentenceReading, HighlightSegment } from '../service/SimilarityMatcher';
import { abilityAccessCtrl, common } from '@kit.AbilityKit';
import appLogger from '../utils/Logger';

type TabType = 'dialogue' | 'practice' | 'conversation' | 'quiz';

// 字幕流扁平项：对话标题或句子，用于 List + ForEach 单层渲染
interface FlatSentenceItem {
  isTitle: boolean;
  dialogueIndex: number;
  sentenceIndex: number;
  dialogue: Dialogue;
  sentence: Sentence | null;
}

@Component
export struct StudyPage {
  @Prop isVisible: boolean = true;
  @Prop sceneId: string = '';
  onBack: () => void = () => {};

  @State scene: Scene | null = null;
  @State currentDialogueIndex: number = 0;
  @State currentTab: TabType = 'dialogue';
  @State showRomaji: boolean = true;
  @State showTranslation: boolean = true;
  @State favorites: Set<string> = new Set();
  @State isLoading: boolean = true;
  @State loadError: string = '';

  // 播放相关状态
  @State isPlaying: boolean = false;
  @State @Watch('onPlayerIndexChanged') playerDialogueIndex: number = -1;
  @State @Watch('onPlayerIndexChanged') playerSentenceIndex: number = -1;
  @State currentTimeMs: number = 0;
  @State durationMs: number = 0;

  // 测验相关状态
  @State quizSelectedIndex: number = -1;
  @State quizShowResult: boolean = false;
  @State quizScore: number = 0;
  @State quizSubmitted: boolean = false;

  // 跟读练习相关状态
  @State practiceSentenceIndex: number = 0;
  // 跟读练习 ASR 流程状态
  @State practicePhase: 'idle' | 'loading' | 'recording' | 'recognizing' | 'feedback' = 'idle';
  @State practiceMatchResult: MatchResult | null = null;
  @State practiceErrorMsg: string = '';
  @State practicePermissionGranted: boolean = false;
  @State practiceModelReady: boolean = false;

  // 屏幕宽度断点
  @State screenWidth: number = 600;
  // 横屏（16:9）适配：紧凑间距 + 左右分栏
  @StorageProp('isLandscape') isLandscape: boolean = false;

  // 字幕流滚动控制器，用于自动滚动到当前播放句子
  private sentenceScroller: Scroller = new Scroller();

  // 跟读练习录音器
  private practiceRecorder: AudioRecorder = new AudioRecorder();
  private playerStateCallback: ((state: PlayerUiState) => void) | null = null;
  private playerTimeCallback: ((currentTimeMs: number, durationMs: number) => void) | null = null;
  // 页面销毁标记：组件销毁后 Scroller 与 List 解绑，延迟回调中再调用 currentOffset/scrollToIndex 会抛 JsCrash
  private isDestroyed: boolean = false;

  aboutToAppear(): void {
    this.isDestroyed = false;
    this.loadData();
    // 同步 ASR 模型就绪状态（可能已被对话模式初始化）
    this.practiceModelReady = SherpaAsrEngine.getInstance().isReady;

    this.playerStateCallback = (state: PlayerUiState) => {
      if (state.sceneId === this.sceneId) {
        this.isPlaying = state.isPlaying;
        // 诊断日志：仅索引真正变化时打印
        if (state.dialogueIndex !== this.playerDialogueIndex || state.sentenceIndex !== this.playerSentenceIndex) {
          appLogger.info(`[StudyPage-scroll] player idx -> d=${state.dialogueIndex} s=${state.sentenceIndex} playing=${state.isPlaying}`);
        }
        this.playerDialogueIndex = state.dialogueIndex;
        this.playerSentenceIndex = state.sentenceIndex;
      } else {
        this.isPlaying = false;
        this.playerDialogueIndex = -1;
        this.playerSentenceIndex = -1;
      }
      this.currentTimeMs = state.currentTimeMs;
      this.durationMs = state.durationMs;
    };
    PlayerController.getInstance().addOnStateChange(this.playerStateCallback);

    this.playerTimeCallback = (currentTimeMs: number, durationMs: number) => {
      this.currentTimeMs = currentTimeMs;
      this.durationMs = durationMs;
    };
    PlayerController.getInstance().addOnTimeUpdate(this.playerTimeCallback);

    // 数据加载完成后延迟触发一次滚动（如果音频已在播放）
    this.scrollToCurrentSentence(350);
  }

  aboutToDisappear(): void {
    this.isDestroyed = true;
    this.stopPracticeAsr();
    ConversationController.getInstance().stopConversation();
    if (this.playerStateCallback) {
      PlayerController.getInstance().removeOnStateChange(this.playerStateCallback);
      this.playerStateCallback = null;
    }
    if (this.playerTimeCallback) {
      PlayerController.getInstance().removeOnTimeUpdate(this.playerTimeCallback);
      this.playerTimeCallback = null;
    }
  }

  private async loadData(): Promise<void> {
    this.isLoading = true;
    this.loadError = '';

    try {
      // 从 SceneRepository 获取场景
      const repo = SceneRepository.getInstance();
      const sceneData = repo.getSceneById(this.sceneId);
      if (sceneData) {
        this.scene = sceneData;
      } else {
        // 如果缓存中没有，尝试重新加载
        await repo.loadAll();
        const reloaded = repo.getSceneById(this.sceneId);
        if (reloaded) {
          this.scene = reloaded;
        } else {
          this.loadError = '场景数据加载失败';
          appLogger.error(`StudyPage: scene ${this.sceneId} not found`);
        }
      }

      // 从 SettingsStore 获取偏好
      const settingsStore = SettingsStore.getInstance();
      const settings = settingsStore.getSettings();
      this.showRomaji = settings.showRomaji;
      this.showTranslation = settings.showTranslation;

      // 从 ProgressStore 获取收藏
      const progressStore = ProgressStore.getInstance();
      const progress = progressStore.getProgress();
      this.favorites = new Set(progress.favoriteSentences);

      // 从 PlayerController 同步播放状态（返回本页时音频可能已在播放）
      const uiState = PlayerController.getInstance().getUiState();
      if (uiState.sceneId === this.sceneId) {
        this.isPlaying = uiState.isPlaying;
        this.playerDialogueIndex = uiState.dialogueIndex;
        this.playerSentenceIndex = uiState.sentenceIndex;
        this.currentTimeMs = uiState.currentTimeMs;
        this.durationMs = uiState.durationMs;
      }
    } catch (error) {
      this.loadError = '数据加载失败，请稍后重试';
      appLogger.error('StudyPage: loadData failed', error);
    } finally {
      this.isLoading = false;
    }
  }

  private get currentDialogue(): Dialogue | null {
    if (!this.scene || this.currentDialogueIndex < 0 || this.currentDialogueIndex >= this.scene.dialogues.length) {
      return null;
    }
    const dlg = this.scene.dialogues[this.currentDialogueIndex];
    if (!dlg) {
      appLogger.warn(`StudyPage: currentDialogue is falsy at index ${this.currentDialogueIndex}, dialogues.length=${this.scene.dialogues.length}, type=${typeof dlg}`);
    }
    return dlg || null;
  }

  private get isWideScreen(): boolean {
    return this.screenWidth >= AppConstants.BREAKPOINTS.lg;
  }

  private getSentenceKey(dialogueIdx: number, sentenceIdx: number): string {
    return `${this.sceneId}:${dialogueIdx}:${sentenceIdx}`;
  }

  private handlePlaySentence(dialogueIdx: number, sentenceIdx: number): void {
    const scene = this.scene;
    if (!scene) {
      return;
    }
    const controller = PlayerController.getInstance();
    if (this.playerDialogueIndex === dialogueIdx && this.playerSentenceIndex === sentenceIdx) {
      controller.togglePlay().catch((err: Object) => {
        appLogger.error('StudyPage: toggle play failed', err);
      });
    } else {
      controller.playSentence(scene, dialogueIdx, sentenceIdx).catch((err: Object) => {
        appLogger.error('StudyPage: play sentence failed', err);
      });
    }
  }

  private async handleToggleFavorite(dialogueIdx: number, sentenceIdx: number): Promise<void> {
    const key = this.getSentenceKey(dialogueIdx, sentenceIdx);
    const progressStore = ProgressStore.getInstance();
    const isFav = await progressStore.toggleFavorite(key);

    const newFavorites = new Set(this.favorites);
    if (isFav) {
      newFavorites.add(key);
    } else {
      newFavorites.delete(key);
    }
    this.favorites = newFavorites;
  }

  private handlePlayPause(): void {
    const scene = this.scene;
    if (!scene) {
      return;
    }
    const controller = PlayerController.getInstance();
    const uiState = controller.getUiState();
    if (uiState.sceneId === this.sceneId) {
      controller.togglePlay().catch((err: Object) => {
        appLogger.error('StudyPage: toggle play failed', err);
      });
    } else {
      controller.playSentence(scene, this.currentDialogueIndex, 0).catch((err: Object) => {
        appLogger.error('StudyPage: play sentence failed', err);
      });
    }
  }

  private handlePrevSentence(): void {
    PlayerController.getInstance().prevSentence().catch((err: Object) => {
      appLogger.error('StudyPage: prev sentence failed', err);
    });
  }

  private handleNextSentence(): void {
    PlayerController.getInstance().nextSentence().catch((err: Object) => {
      appLogger.error('StudyPage: next sentence failed', err);
    });
  }

  // 计算当前播放句子在字幕流中的全局索引（含对话标题占位）
  private computeGlobalSentenceIndex(): number {
    if (!this.scene || this.playerDialogueIndex < 0 || this.playerSentenceIndex < 0) {
      return -1;
    }
    let idx = 0;
    for (let d = 0; d < this.playerDialogueIndex && d < this.scene.dialogues.length; d++) {
      idx += 1; // 对话标题
      idx += this.scene.dialogues[d].sentences.length; // 该对话下所有句子
    }
    idx += 1; // 当前对话标题
    idx += this.playerSentenceIndex; // 当前句子
    return idx;
  }

  // 构造扁平化的字幕项列表：把对话标题与每个句子都展开为独立项
  // 这样 List + ForEach 的索引就是简单的 0,1,2,...，scrollToIndex 行为稳定
  private getFlatSentenceItems(): FlatSentenceItem[] {
    const items: FlatSentenceItem[] = [];
    if (!this.scene) {
      return items;
    }
    const dialogues = this.scene.dialogues;
    for (let d = 0; d < dialogues.length; d++) {
      const dialogue = dialogues[d];
      // 标题项
      items.push({
        isTitle: true,
        dialogueIndex: d,
        sentenceIndex: -1,
        dialogue: dialogue,
        sentence: null
      });
      // 句子项
      const sentences = dialogue.sentences;
      for (let s = 0; s < sentences.length; s++) {
        items.push({
          isTitle: false,
          dialogueIndex: d,
          sentenceIndex: s,
          dialogue: dialogue,
          sentence: sentences[s]
        });
      }
    }
    return items;
  }

  // 判断指定句子是否正在播放
  private isSentencePlaying(dIndex: number, sIndex: number): boolean {
    return this.isPlaying && this.playerDialogueIndex === dIndex
      && this.playerSentenceIndex === sIndex;
  }

  // 播放位置变化时自动滚动到当前句子
  // 延迟 150ms 等待 UI 渲染完成后再滚动，避免初始渲染时滚动失效
  private onPlayerIndexChanged(): void {
    setTimeout(() => {
      if (this.isDestroyed) {
        return;
      }
      if (!this.scene || this.scene.dialogues.length === 0) {
        return;
      }
      // 仅在对话 Tab 可见时滚动；切换 Tab 时由 onClick 另行触发
      if (this.currentTab !== 'dialogue') {
        appLogger.info(`[StudyPage-scroll] watch fired but tab=${this.currentTab}, skip`);
        return;
      }
      try {
        const idx = this.computeGlobalSentenceIndex();
        const before = this.sentenceScroller.currentOffset();
        appLogger.info(`[StudyPage-scroll] watch fired idx=${idx} beforeY=${before.yOffset}`);
        if (idx >= 0) {
          this.sentenceScroller.scrollToIndex(idx, true, ScrollAlign.CENTER);
          // 诊断日志：400ms 后检查滚动是否生效
          setTimeout(() => {
            if (this.isDestroyed) {
              return;
            }
            try {
              const after = this.sentenceScroller.currentOffset();
              appLogger.info(`[StudyPage-scroll] after scroll idx=${idx} afterY=${after.yOffset}`);
            } catch (e) {
              appLogger.warn('[StudyPage-scroll] after-scroll offset failed: ' + JSON.stringify(e));
            }
          }, 400);
        }
      } catch (e) {
        // Scroller 未绑定 List（页面切换/销毁竞态）时 currentOffset/scrollToIndex 会抛异常，防止 JsCrash
        appLogger.warn('[StudyPage-scroll] watch scroll failed: ' + JSON.stringify(e));
      }
    }, 150);
  }

  // 主动触发一次滚动到当前播放句子（用于初始化后或 Tab 切换后）
  private scrollToCurrentSentence(delay: number): void {
    setTimeout(() => {
      if (this.isDestroyed) {
        return;
      }
      if (!this.scene || this.scene.dialogues.length === 0) {
        return;
      }
      // 仅在对话 Tab 可见时滚动；非对话 Tab 时 List 未挂载，滚动无意义
      if (this.currentTab !== 'dialogue') {
        appLogger.info(`[StudyPage-scroll] manual scroll skip tab=${this.currentTab}`);
        return;
      }
      if (this.playerDialogueIndex < 0 || this.playerSentenceIndex < 0) {
        appLogger.info('[StudyPage-scroll] manual scroll skip: no playing sentence');
        return;
      }
      try {
        const idx = this.computeGlobalSentenceIndex();
        const before = this.sentenceScroller.currentOffset();
        appLogger.info(`[StudyPage-scroll] manual scroll idx=${idx} beforeY=${before.yOffset}`);
        if (idx >= 0) {
          this.sentenceScroller.scrollToIndex(idx, true, ScrollAlign.CENTER);
          setTimeout(() => {
            if (this.isDestroyed) {
              return;
            }
            try {
              const after = this.sentenceScroller.currentOffset();
              appLogger.info(`[StudyPage-scroll] manual after scroll idx=${idx} afterY=${after.yOffset}`);
            } catch (e) {
              appLogger.warn('[StudyPage-scroll] manual after-scroll offset failed: ' + JSON.stringify(e));
            }
          }, 400);
        }
      } catch (e) {
        appLogger.warn('[StudyPage-scroll] manual scroll failed: ' + JSON.stringify(e));
      }
    }, delay);
  }

  // ---- 跟读练习相关 ----
  // UI 渲染用 getter（ArkUI 响应式上下文正常工作）
  private get practiceSentence(): Sentence | null {
    return this.getPracticeSentence();
  }

  // async 方法中用此方法（getter 在 await 后可能返回缓存的旧值）
  private getPracticeSentence(): Sentence | null {
    const scn = this.scene;
    const dIdx = this.currentDialogueIndex;
    const sIdx = this.practiceSentenceIndex;
    const dlgArr = scn ? scn.dialogues : null;
    const dlg = dlgArr && dIdx >= 0 && dIdx < dlgArr.length ? dlgArr[dIdx] : null;
    const sentArr = dlg ? dlg.sentences : null;
    const sent = sentArr && sIdx >= 0 && sIdx < sentArr.length ? sentArr[sIdx] : null;
    return sent || null;
  }

  private handlePracticePrev(): void {
    if (this.practiceSentenceIndex > 0) {
      this.practiceSentenceIndex -= 1;
    }
  }

  private handlePracticeNext(): void {
    const dialogue = this.currentDialogue;
    if (dialogue && this.practiceSentenceIndex < dialogue.sentences.length - 1) {
      this.practiceSentenceIndex += 1;
    }
  }

  private handlePracticePlay(): void {
    this.playPracticeSentence(false);
  }

  private handlePracticeSlow(): void {
    this.playPracticeSentence(true);
  }

  private playPracticeSentence(slow: boolean): void {
    const scene = this.scene;
    if (!scene) {
      return;
    }
    const controller = PlayerController.getInstance();
    const uiState = controller.getUiState();
    // 先切换慢速模式（若需要），再用 playSentenceAndNotify 播放单句。
    // playSentenceAndNotify 会在句子结束时自动暂停，避免继续播放下一句。
    // 注意：toggleSlowMode 内部会调用 pause() 清除 sentenceNotifyActive，
    // 因此必须在切换完成后再调用 playSentenceAndNotify 重新设置该标记。
    const needToggleSlow = uiState.sceneId === scene.id && slow !== uiState.isSlowMode;
    const playPromise: Promise<void> = needToggleSlow
      ? controller.toggleSlowMode().then((): Promise<void> =>
          controller.playSentenceAndNotify(scene, this.currentDialogueIndex, this.practiceSentenceIndex))
      : controller.playSentenceAndNotify(scene, this.currentDialogueIndex, this.practiceSentenceIndex);
    playPromise.catch((err: Object) => {
      appLogger.error('StudyPage: practice play failed', err);
    });
  }

  // ---- 跟读练习 ASR 相关 ----

  // 请求麦克风权限
  private async ensurePracticePermission(): Promise<boolean> {
    if (this.practicePermissionGranted) {
      return true;
    }
    appLogger.info('StudyPage: practice request mic permission begin');
    let granted: boolean = false;
    let settled: boolean = false;
    try {
      const context = getContext(this) as common.UIAbilityContext;
      // 已被「拒绝且不再询问」的权限：系统可能不弹窗且不回调（Promise 永久挂起），
      // 用 then/catch 标志位 + 10s 轮询超时兜底，避免界面卡在 loading
      const requestPromise = abilityAccessCtrl.createAtManager()
        .requestPermissionsFromUser(context, ['ohos.permission.MICROPHONE']);
      requestPromise.then((res) => {
        settled = true;
        granted = !!(res.authResults && res.authResults[0] === 0);
        appLogger.info(`StudyPage: practice mic permission authResults=${JSON.stringify(res.authResults)} granted=${granted}`);
      }).catch((e: Object) => {
        settled = true;
        appLogger.error('StudyPage: requestPermissionsFromUser failed', e);
      });
      const deadline: number = Date.now() + 10000;
      while (!settled && Date.now() < deadline) {
        await new Promise<void>((resolve): void => {
          setTimeout(() => {
            resolve();
          }, 200);
        });
      }
    } catch (e) {
      appLogger.error('StudyPage: requestPermissionsFromUser outer failed', e);
      settled = true;
    }
    if (!settled) {
      appLogger.warn('StudyPage: practice mic permission request timeout (dialog suppressed?)');
      return false;
    }
    this.practicePermissionGranted = granted;
    if (!granted) {
      appLogger.warn('StudyPage: practice microphone permission denied');
    }
    return this.practicePermissionGranted;
  }

  // 初始化 ASR 模型（延迟到首次录音时）
  private async ensurePracticeModel(): Promise<boolean> {
    if (this.practiceModelReady) {
      return true;
    }
    const asr = SherpaAsrEngine.getInstance();
    if (asr.isReady) {
      this.practiceModelReady = true;
      return true;
    }
    try {
      const context = getContext(this) as common.UIAbilityContext;
      await asr.init(context);
      this.practiceModelReady = true;
    } catch (e) {
      appLogger.error('StudyPage: practice ASR init failed', e);
      this.practiceModelReady = false;
    }
    return this.practiceModelReady;
  }

  // 进入练习 Tab 时后台预加载 ASR 模型（Worker 子线程加载，不阻塞 UI）
  private preloadModelIfNeeded(): void {
    const asr = SherpaAsrEngine.getInstance();
    if (this.practiceModelReady || asr.isReady) {
      this.practiceModelReady = true;
      return;
    }
    const context = getContext(this) as common.UIAbilityContext;
    asr.init(context).then(() => {
      this.practiceModelReady = true;
      appLogger.info('StudyPage: practice preload ASR model done');
    }).catch((e: Object) => {
      appLogger.error('StudyPage: practice preload ASR model failed', e);
    });
  }

  // 开始录音跟读（录音中再次点击 = 完成跟读并识别）
  private async handlePracticeRecord(): Promise<void> {
    if (this.practicePhase === 'recording') {
      return this.handlePracticeFinish();
    }
    // loading/recognizing 期间忽略重复点击
    if (this.practicePhase !== 'idle') {
      appLogger.info(`StudyPage: practice record click ignored, phase=${this.practicePhase}`);
      return;
    }
    // 重置上一次反馈
    this.practiceMatchResult = null;
    this.practiceErrorMsg = '';
    // 先进入 loading 阶段：模型加载（首次约 20 秒）期间给用户明确反馈
    this.practicePhase = 'loading';
    try {
      // 确保权限
      if (!await this.ensurePracticePermission()) {
        appLogger.warn('StudyPage: practice record abort: no mic permission');
        this.practiceErrorMsg = '麦克风权限未授权';
        this.practicePhase = 'idle';
        return;
      }
      appLogger.info('StudyPage: practice record permission ok');
      // 确保 ASR 模型就绪
      if (!await this.ensurePracticeModel()) {
        appLogger.warn('StudyPage: practice record abort: model not ready');
        this.practiceErrorMsg = '语音识别模型加载失败';
        this.practicePhase = 'idle';
        return;
      }
      appLogger.info('StudyPage: practice record model ok');
      const sentence = this.getPracticeSentence();
      if (!sentence) {
        const scn = this.scene;
        const dlgArr = scn ? scn.dialogues : null;
        const dlg = dlgArr && this.currentDialogueIndex >= 0 && this.currentDialogueIndex < dlgArr.length
          ? dlgArr[this.currentDialogueIndex] : undefined;
        const dlgType = typeof dlg;
        const dlgKeys = dlg && typeof dlg === 'object' ? Object.keys(dlg).join(',') : '(n/a)';
        const hasSentences = dlg && typeof dlg === 'object' ? (dlg.sentences !== undefined && dlg.sentences !== null) : false;
        const sentLen = dlg && dlg.sentences ? dlg.sentences.length : -1;
        appLogger.warn(`StudyPage: practice abort detail2: scn=${!!scn} dlgArrLen=${dlgArr ? dlgArr.length : -1} dIdx=${this.currentDialogueIndex} dlgType=${dlgType} dlgKeys=[${dlgKeys}] hasSentences=${hasSentences} sentLen=${sentLen} sIdx=${this.practiceSentenceIndex}`);
        this.practiceErrorMsg = sentLen <= 0 ? '当前对话没有可跟读的句子' : '数据异常，请返回后重新进入';
        this.practicePhase = 'idle';
        return;
      }
      // 等待期间用户已离开练习 Tab，放弃录音
      if (this.currentTab !== 'practice') {
        appLogger.warn(`StudyPage: practice record abort: tab=${this.currentTab}`);
        this.practicePhase = 'idle';
        return;
      }
      appLogger.info('StudyPage: practice record prechecks passed, start listening');
      // 停止对话模式（避免两个流程同时录音）
      ConversationController.getInstance().stopConversation();
      // 停止播放器
      PlayerController.getInstance().pause().catch(() => {});
      this.practicePhase = 'recording';
      const asr = SherpaAsrEngine.getInstance();
      await asr.startListening((text: string) => this.onPracticeAsrEndpoint(text));
      this.practiceRecorder.onData = (samples: Int16Array) => {
        if (this.practicePhase === 'recording') {
          asr.feedPcmChunk(samples);
        }
      };
      this.practiceRecorder.onError = (msg: string) => {
        appLogger.error('StudyPage: practice recorder error: ' + msg);
        this.practiceErrorMsg = msg;
        this.practicePhase = 'idle';
        this.practiceRecorder.stop().catch(() => {});
        SherpaAsrEngine.getInstance().stopListening().catch(() => {});
      };
      await this.practiceRecorder.start();
      appLogger.info('StudyPage: practice record started');
    } catch (e) {
      const errMsg = e instanceof Error ? e.message : String(e);
      appLogger.error('StudyPage: practice record start failed: ' + errMsg, e);
      this.practiceErrorMsg = '录音启动失败：' + errMsg;
      this.practicePhase = 'idle';
      // 确保 ASR 监听状态被重置（startListening 可能已成功但 recorder.start 失败）
      try {
        await SherpaAsrEngine.getInstance().stopListening();
      } catch (_) {}
    }
  }

  // 完成跟读：停止录音并识别已缓冲语音（而不是丢弃）
  private async handlePracticeFinish(): Promise<void> {
    if (this.practicePhase !== 'recording') {
      return;
    }
    this.practicePhase = 'recognizing';
    try {
      await this.practiceRecorder.stop();
    } catch (e) {
      appLogger.error('StudyPage: practice recorder.stop failed', e);
    }
    try {
      // recognize=true: Worker flush 残留语音段并识别，结果经 onPracticeAsrEndpoint 回调
      await SherpaAsrEngine.getInstance().stopListening(true);
    } catch (e) {
      appLogger.error('StudyPage: practice stopListening(recognize) failed', e);
    }
    // stop_done 之前若收到 endpoint，phase 已被 onPracticeAsrEndpoint 推进到 feedback
    if (this.practicePhase === 'recognizing') {
      this.practiceMatchResult = { similarity: 0, isCorrect: false, userHighlighted: [], originalHighlighted: [] };
      this.practiceErrorMsg = '没听清，请重试';
      this.practicePhase = 'feedback';
    }
  }

  // ASR 端点回调：停止录音并匹配
  private async onPracticeAsrEndpoint(text: string): Promise<void> {
    this.practicePhase = 'recognizing';
    try {
      await this.practiceRecorder.stop();
    } catch (e) {
      appLogger.error('StudyPage: practice recorder.stop failed', e);
    }
    try {
      await SherpaAsrEngine.getInstance().stopListening();
    } catch (e) {
      appLogger.error('StudyPage: practice asr.stopListening failed', e);
    }
    const sentence = this.getPracticeSentence();
    if (!sentence) {
      this.practicePhase = 'idle';
      return;
    }
    if (!text || text.trim().length === 0) {
      this.practiceMatchResult = { similarity: 0, isCorrect: false, userHighlighted: [], originalHighlighted: [] };
      this.practiceErrorMsg = '没听清，请重试';
      this.practicePhase = 'feedback';
      return;
    }
    try {
      this.practiceMatchResult = matchWithReading(text, sentence.japanese, getSentenceReading(sentence));
      this.practicePhase = 'feedback';
    } catch (e) {
      appLogger.error('StudyPage: practice match failed', e);
      this.practiceErrorMsg = '识别异常，请重试';
      this.practicePhase = 'idle';
    }
  }

  // 停止跟读练习 ASR（停止录音并丢弃未识别语音）
  // loading 阶段离开 Tab 时仅重置 phase，handlePracticeRecord 的 currentTab 检查会放弃录音
  private stopPracticeAsr(): void {
    if (this.practicePhase === 'recording' || this.practicePhase === 'recognizing') {
      this.practiceRecorder.stop().catch(() => {});
      SherpaAsrEngine.getInstance().stopListening().catch(() => {});
    }
    this.practicePhase = 'idle';
  }

  // 重置跟读练习 ASR 状态
  private resetPracticeAsr(): void {
    this.stopPracticeAsr();
    this.practiceMatchResult = null;
    this.practiceErrorMsg = '';
  }

  // ---- 测验相关 ----
  private get currentQuiz(): QuizItem | null {
    const dialogue = this.currentDialogue;
    if (!dialogue || dialogue.quiz.length === 0) {
      return null;
    }
    return dialogue.quiz[0];
  }

  private handleQuizSelect(index: number): void {
    if (!this.quizShowResult) {
      this.quizSelectedIndex = index;
    }
  }

  private handleQuizSubmit(): void {
    if (this.currentQuiz && this.quizSelectedIndex === this.currentQuiz.correctIndex) {
      this.quizScore = 100;
    } else {
      this.quizScore = 0;
    }
    this.quizShowResult = true;
    this.quizSubmitted = true;
  }

  private handleQuizReset(): void {
    this.quizSelectedIndex = -1;
    this.quizShowResult = false;
    this.quizSubmitted = false;
  }

  build() {
    Column() {
      // 加载状态
      if (this.isLoading) {
        this.LoadingBuilder();
      } else if (this.loadError || !this.scene) {
        this.ErrorBuilder();
      } else {
        // 顶部导航栏
        this.TopBarBuilder();

        // Tab 切换
        this.TabBarBuilder();

        // 主体内容
        Column() {
          this.ContentBuilder();
        }
        .layoutWeight(1);

        // 底部 PlayerBar：仅在「对话」Tab 显示，跟读练习和对话模式有自己的播放控制
        if (this.currentTab === 'dialogue') {
          PlayerBar({
            sceneTitle: this.scene.titleJa,
            sentenceJapanese: this.getCurrentSentenceJapanese(),
            isPlaying: this.isPlaying,
            currentTimeMs: this.currentTimeMs,
            durationMs: this.durationMs,
            onPlayPause: () => this.handlePlayPause(),
            onPrev: () => this.handlePrevSentence(),
            onNext: () => this.handleNextSentence()
          })
          .margin({ top: 8 });
        }
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(ThemeColors.bgApp)
    .padding(this.isLandscape ? 12 : 16)
    .onAreaChange((oldArea: Area, newArea: Area) => {
      this.screenWidth = newArea.width as number;
    });
  }

  // ---- 顶部导航栏 ----
  @Builder
  TopBarBuilder() {
    Row() {
      // 返回按钮
      Text('←')
        .fontSize(20)
        .fontColor(ThemeColors.textPrimary)
        .padding(8)
        .onClick(() => {
          this.onBack();
        });

      // 场景标题
      Column() {
        Text(this.scene ? this.scene.titleJa : '')
          .fontSize(18)
          .fontColor(ThemeColors.textPrimary)
          .fontWeight(700);

        Text(this.scene ? this.scene.titleZh : '')
          .fontSize(12)
          .fontColor(ThemeColors.textSecondary)
          .margin({ top: 2 });
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Center);

      // 占位（平衡返回按钮）
      Text('')
        .width(36);
    }
    .width('100%')
    .height(this.isLandscape ? 44 : 56)
    .alignItems(VerticalAlign.Center);
  }

  // ---- Tab 切换栏 ----
  @Builder
  TabBarBuilder() {
    Row() {
      this.TabItemBuilder('对话', 'dialogue');
      this.TabItemBuilder('跟读练习', 'practice');
      this.TabItemBuilder('人机对话', 'conversation');
    }
    .width('100%')
    .height(this.isLandscape ? 36 : 40)
    .backgroundColor(ThemeColors.bgCard)
    .borderRadius(10)
    .padding(4)
    .margin({ top: this.isLandscape ? 6 : 8, bottom: this.isLandscape ? 8 : 12 });
  }

  @Builder
  TabItemBuilder(label: string, tab: TabType) {
    Text(label)
      .fontSize(13)
      .fontColor(this.currentTab === tab ? '#FFFFFF' : ThemeColors.textSecondary)
      .fontWeight(this.currentTab === tab ? 600 : 400)
      .layoutWeight(1)
      .height('100%')
      .textAlign(TextAlign.Center)
      .backgroundColor(this.currentTab === tab ? ThemeColors.primary : 'transparent')
      .borderRadius(8)
      .onClick(() => {
        if (this.currentTab === 'conversation' && tab !== 'conversation') {
          ConversationController.getInstance().stopConversation();
        }
        // 离开跟读练习 Tab 时停止录音
        if (this.currentTab === 'practice' && tab !== 'practice') {
          this.stopPracticeAsr();
        }
        this.currentTab = tab;
        // 切换到对话 Tab 时，若有播放中的句子，滚动到该句
        if (tab === 'dialogue') {
          this.scrollToCurrentSentence(120);
        }
        // 进入跟读练习 Tab 时后台预加载 ASR 模型（Worker 子线程加载，不阻塞 UI）
        if (tab === 'practice') {
          this.preloadModelIfNeeded();
        }
      });
  }

  // ---- 主体内容 ----
  @Builder
  ContentBuilder() {
    if (this.currentTab === 'dialogue') {
      this.buildDialogueTab();
    } else if (this.currentTab === 'practice') {
      this.buildPracticeTab();
    } else {
      // 对话模式 Tab
      this.buildConversationTab();
    }
  }

  // ---- 对话模式 Tab ----
  @Builder
  buildConversationTab() {
    ConversationTab({
      scene: this.scene,
      currentDialogueIndex: this.currentDialogueIndex,
      practiceSentenceIndex: this.practiceSentenceIndex
    });
  }

  // ---- 对话 Tab ----
  @Builder
  buildDialogueTab() {
    if (this.isWideScreen || this.isLandscape) {
      // 宽屏：左右分栏
      Row() {
        // 左侧：对话列表
        Column() {
          this.DialogueListBuilder();
        }
        .width('35%')
        .margin({ right: 12 });

        // 右侧：句子列表
        Column() {
          this.SentenceListBuilder();
        }
        .layoutWeight(1);
      }
      .width('100%')
      .height('100%');
    } else {
      // 窄屏：上下结构
      Column() {
        // 对话选择器（横滑）
        Column() {
          this.DialogueScrollBuilder();
        }
        .margin({ bottom: 12 });

        // 句子列表
        Column() {
          this.SentenceListBuilder();
        }
        .layoutWeight(1);
      }
      .width('100%')
      .height('100%');
    }
  }

  // ---- 宽屏左侧：对话列表 ----
  @Builder
  DialogueListBuilder() {
    Column() {
      Text('对话列表')
        .fontSize(13)
        .fontColor(ThemeColors.textSecondary)
        .fontWeight(600)
        .width('100%')
        .margin({ bottom: 8 });

      List() {
        ForEach(this.scene!.dialogues, (dialogue: Dialogue, index: number) => {
          ListItem() {
            this.DialogueItemBuilder(dialogue, index);
          }
        }, (dialogue: Dialogue) => dialogue.id);
      }
      .width('100%')
      .layoutWeight(1);
    }
    .width('100%')
    .height('100%');
  }

  @Builder
  DialogueItemBuilder(dialogue: Dialogue, index: number) {
    Column() {
      Text(dialogue.titleJa)
        .fontSize(13)
        .fontColor(this.currentDialogueIndex === index ? ThemeColors.primary : ThemeColors.textPrimary)
        .fontWeight(this.currentDialogueIndex === index ? 600 : 400)
        .width('100%');

      Text(dialogue.titleZh)
        .fontSize(11)
        .fontColor(ThemeColors.textTertiary)
        .width('100%')
        .margin({ top: 2 });
    }
    .width('100%')
    .padding(12)
    .backgroundColor(this.currentDialogueIndex === index ? ThemeColors.bgCardElevated : ThemeColors.bgCard)
    .borderRadius(8)
    .border({
      width: { left: this.currentDialogueIndex === index ? 3 : 0 },
      color: ThemeColors.primary
    })
    .margin({ bottom: 6 })
    .onClick(() => {
      ConversationController.getInstance().stopConversation();
      this.currentDialogueIndex = index;
      this.practiceSentenceIndex = 0;
      this.resetPracticeAsr();
      this.handleQuizReset();
    });
  }

  // ---- 窄屏：对话横滑选择器 ----
  @Builder
  DialogueScrollBuilder() {
    Scroll() {
      Row() {
        ForEach(this.scene!.dialogues, (dialogue: Dialogue, index: number) => {
          Column() {
            Text(dialogue.titleJa)
              .fontSize(12)
              .fontColor(this.currentDialogueIndex === index ? '#FFFFFF' : ThemeColors.textSecondary)
              .fontWeight(this.currentDialogueIndex === index ? 600 : 400);

            Text(dialogue.titleZh)
              .fontSize(10)
              .fontColor(this.currentDialogueIndex === index ? ThemeColors.primaryLight : ThemeColors.textTertiary)
              .margin({ top: 2 });
          }
          .padding({ left: 12, right: 12, top: 8, bottom: 8 })
          .backgroundColor(this.currentDialogueIndex === index ? ThemeColors.primary : ThemeColors.bgCard)
          .borderRadius(8)
          .margin({ right: index < this.scene!.dialogues.length - 1 ? 8 : 0 })
          .onClick(() => {
            ConversationController.getInstance().stopConversation();
            this.currentDialogueIndex = index;
            this.practiceSentenceIndex = 0;
            this.resetPracticeAsr();
            this.handleQuizReset();
          });
        }, (dialogue: Dialogue) => dialogue.id);
      }
    }
    .width('100%')
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off);
  }

  // ---- 句子列表（字幕流式：无卡片，自动滚动到当前播放句）----
  // 改用 List + ListItem + 扁平 ForEach：List 对 scrollToIndex 的索引计算更可靠
  @Builder
  SentenceListBuilder() {
    if (!this.scene || this.scene.dialogues.length === 0) {
      Column() {
        Text('暂无对话内容')
          .fontSize(14)
          .fontColor(ThemeColors.textTertiary);
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center);
    } else {
      List({ scroller: this.sentenceScroller }) {
        // 扁平化 ForEach：对话标题和每个句子都作为独立 ListItem
        ForEach(this.getFlatSentenceItems(), (item: FlatSentenceItem) => {
          ListItem() {
            if (item.isTitle) {
              // 对话分组标题（日文 + 中文）
              Column() {
                Text(item.dialogue.titleJa)
                  .fontSize(18)
                  .fontColor(ThemeColors.primary)
                  .fontWeight(600)
                  .width('100%');
                Text(item.dialogue.titleZh)
                  .fontSize(14)
                  .fontColor(ThemeColors.textTertiary)
                  .width('100%')
                  .margin({ top: 2 });
              }
              .width('100%')
              .padding({ top: item.dialogueIndex === 0 ? 4 : 16, bottom: 8, left: 4, right: 4 });
            } else {
              // 字幕流式句子：无卡片背景，当前句高亮，其他暗色
              Column() {
                // 说话人
                Text(item.sentence!.speakerRoleZh)
                  .fontSize(12)
                  .fontColor(this.isSentencePlaying(item.dialogueIndex, item.sentenceIndex)
                    ? ThemeColors.primary : ThemeColors.textTertiary)
                  .fontWeight(600)
                  .width('100%');

                // 日文原文（含振假名注音）- 当前播放高亮，其他暗色
                FuriganaText({
                  segments: item.sentence!.segments || [],
                  japanese: item.sentence!.japanese,
                  fontSize: 20,
                  fontColor: this.isSentencePlaying(item.dialogueIndex, item.sentenceIndex)
                    ? ThemeColors.textPrimary : ThemeColors.textTertiary,
                  fontWeight: this.isSentencePlaying(item.dialogueIndex, item.sentenceIndex) ? 600 : 400,
                  containerWidth: '100%'
                })
                  .margin({ top: 4 });

                // 罗马音
                if (this.showRomaji) {
                  Text(item.sentence!.romaji)
                    .fontSize(14)
                    .fontColor(this.isSentencePlaying(item.dialogueIndex, item.sentenceIndex)
                      ? ThemeColors.textSecondary : ThemeColors.textTertiary)
                    .width('100%')
                    .margin({ top: 2 });
                }

                // 中文翻译
                if (this.showTranslation) {
                  Text(item.sentence!.translation)
                    .fontSize(16)
                    .fontColor(this.isSentencePlaying(item.dialogueIndex, item.sentenceIndex)
                      ? ThemeColors.textSecondary : ThemeColors.textTertiary)
                    .width('100%')
                    .margin({ top: 2 });
                }
              }
              .width('100%')
              .padding({ left: 4, right: 4, top: 6, bottom: 6 })
              .onClick(() => this.handlePlaySentence(item.dialogueIndex, item.sentenceIndex));
            }
          }
        }, (item: FlatSentenceItem) => `${item.dialogueIndex}:${item.sentenceIndex}`);
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Auto)
      .padding({ left: 4, right: 4 });
    }
  }

  // ---- 跟读练习 Tab ----
  // 显示当前对话的所有句子列表，每个句子可点击选择，
  // 选中句子后可在底部练习区进行原音播放/慢速/录音跟读/上一句/下一句
  @Builder
  buildPracticeTab() {
    // 直接使用 @State 变量做条件判断，避免 getter 在 @Builder 中不触发重渲染
    if (!this.scene || this.scene.dialogues.length === 0
      || this.currentDialogueIndex < 0
      || this.currentDialogueIndex >= this.scene.dialogues.length) {
      Column() {
        Text('暂无练习内容')
          .fontSize(14)
          .fontColor(ThemeColors.textTertiary);
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center);
    } else if (this.isLandscape) {
      // 横屏：左侧句子列表 + 右侧练习详情
      Row() {
        Column() {
          List() {
            ForEach(this.scene.dialogues[this.currentDialogueIndex].sentences,
              (sentence: Sentence, index: number) => {
                ListItem() {
                  this.PracticeSentenceItemBuilder(sentence, index);
                }
              }, (sentence: Sentence) => sentence.id);
          }
          .width('100%')
          .layoutWeight(1)
          .scrollBar(BarState.Auto)
          .padding({ left: 4, right: 4 });
        }
        .layoutWeight(1)
        .height('100%')
        .margin({ right: 12 });

        Column() {
          this.PracticeDetailBuilder();
        }
        .width(380)
        .height('100%')
        .justifyContent(FlexAlign.Center);
      }
      .width('100%')
      .height('100%');
    } else {
      Column() {
        // 上半部：句子列表（可滚动选择）
        List() {
          ForEach(this.scene.dialogues[this.currentDialogueIndex].sentences,
            (sentence: Sentence, index: number) => {
              ListItem() {
                this.PracticeSentenceItemBuilder(sentence, index);
              }
            }, (sentence: Sentence) => sentence.id);
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Auto)
        .padding({ left: 4, right: 4 });

        // 下半部：选中句子的练习详情区
        this.PracticeDetailBuilder();
      }
      .width('100%')
      .height('100%');
    }
  }

  // 跟读练习：句子列表项
  @Builder
  PracticeSentenceItemBuilder(sentence: Sentence, index: number) {
    Column() {
      // 说话人
      Text(sentence.speakerRoleZh)
        .fontSize(11)
        .fontColor(this.practiceSentenceIndex === index ? ThemeColors.primary : ThemeColors.textTertiary)
        .fontWeight(600)
        .width('100%');

      // 日文原文（含振假名注音）- 选中句高亮
      FuriganaText({
        segments: sentence.segments || [],
        japanese: sentence.japanese,
        fontSize: 16,
        fontColor: this.practiceSentenceIndex === index ? ThemeColors.textPrimary : ThemeColors.textTertiary,
        fontWeight: this.practiceSentenceIndex === index ? 600 : 400,
        containerWidth: '100%'
      })
        .margin({ top: 2 });

      // 罗马音
      if (this.showRomaji) {
        Text(sentence.romaji)
          .fontSize(11)
          .fontColor(this.practiceSentenceIndex === index ? ThemeColors.textSecondary : ThemeColors.textTertiary)
          .width('100%')
          .margin({ top: 2 });
      }

      // 中文翻译
      if (this.showTranslation) {
        Text(sentence.translation)
          .fontSize(13)
          .fontColor(this.practiceSentenceIndex === index ? ThemeColors.textSecondary : ThemeColors.textTertiary)
          .width('100%')
          .margin({ top: 2 });
      }
    }
    .width('100%')
    .padding({ left: 8, right: 8, top: 8, bottom: 8 })
    .backgroundColor(this.practiceSentenceIndex === index ? ThemeColors.bgCardElevated : 'transparent')
    .borderRadius(8)
    .margin({ bottom: 4 })
    .onClick(() => {
      // 切换句子时重置 ASR 状态
      this.resetPracticeAsr();
      this.practiceSentenceIndex = index;
    });
  }

  // 跟读练习：选中句子的练习详情区（操作按钮 + 录音/识别/反馈）
  @Builder
  PracticeDetailBuilder() {
    Column() {
      if (this.practicePhase === 'loading') {
        // ---- 模型加载中（首次约 20 秒）----
        Column() {
          LoadingProgress().width(36).height(36).margin({ bottom: 12 });
          Text('正在准备麦克风与语音模型…')
            .fontSize(14)
            .fontColor(ThemeColors.textSecondary);
          Text('首次加载约 20 秒，完成后自动开始录音')
            .fontSize(11)
            .fontColor(ThemeColors.textTertiary)
            .margin({ top: 4 });
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
        .padding({ top: 16, bottom: 16 });
      } else if (this.practicePhase === 'recording') {
        // ---- 录音中 ----
        Row() {
          Text('record')
            .fontSize(28);
          Text('录音中…请大声朗读')
            .fontSize(14)
            .fontColor(ThemeColors.error)
            .fontWeight(600)
            .margin({ left: 8 });
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .margin({ bottom: 8 });

        // 显示当前要朗读的句子
        if (this.practiceSentence) {
          FuriganaText({
            segments: this.practiceSentence.segments || [],
            japanese: this.practiceSentence.japanese,
            fontSize: 20,
            fontColor: ThemeColors.textPrimary,
            fontWeight: 600,
            containerWidth: '100%'
          })
            .margin({ bottom: 8 });
        }

        // 完成跟读按钮（停止录音并识别已缓冲语音）
        Text('✓ 完成跟读')
          .fontSize(14)
          .fontColor('#FFFFFF')
          .fontWeight(600)
          .width('100%')
          .height(44)
          .textAlign(TextAlign.Center)
          .backgroundColor(ThemeColors.primary)
          .borderRadius(10)
          .onClick(() => {
            this.handlePracticeFinish();
          });
      } else if (this.practicePhase === 'recognizing') {
        // ---- 识别中 ----
        Row() {
          LoadingProgress().width(28).height(28).margin({ right: 8 });
          Text('识别中…')
            .fontSize(14)
            .fontColor(ThemeColors.textSecondary);
        }
        .width('100%')
        .justifyContent(FlexAlign.Center);
      } else {
        // ---- idle / feedback：进度 + 反馈 + 操作按钮 ----
        // 进度指示
        Text(`${this.practiceSentenceIndex + 1} / ${this.currentDialogue?.sentences.length || 0}`)
          .fontSize(11)
          .fontColor(ThemeColors.textTertiary)
          .width('100%')
          .margin({ bottom: 8 });

        // 反馈区域（仅 feedback 阶段显示）
        if (this.practicePhase === 'feedback' && this.practiceMatchResult) {
          this.PracticeFeedbackBuilder();
        }

        // 错误提示（醒目；权限问题时附带系统设置路径引导）
        if (this.practiceErrorMsg) {
          Column() {
            Text(`⚠ ${this.practiceErrorMsg}`)
              .fontSize(13)
              .fontColor(ThemeColors.error)
              .fontWeight(700)
              .width('100%')
              .textAlign(TextAlign.Center);
            if (this.practiceErrorMsg.indexOf('权限') >= 0) {
              Text('请在「设置 → 应用和服务 → 应用管理 → 朱音日语 → 权限」中开启麦克风后重试')
                .fontSize(11)
                .fontColor(ThemeColors.textSecondary)
                .width('100%')
                .textAlign(TextAlign.Center)
                .margin({ top: 4 });
            }
          }
          .width('100%')
          .margin({ bottom: 8 });
        }

        // 操作按钮
        Row() {
          this.PracticeButtonBuilder('原音', 'play', () => this.handlePracticePlay());
          this.PracticeButtonBuilder('慢速', 'slow', () => this.handlePracticeSlow());
          this.PracticeButtonBuilder('录音', 'record', () => this.handlePracticeRecord());
          this.PracticeButtonBuilder('上一句', 'skipBack', () => this.handlePracticePrev());
          this.PracticeButtonBuilder('下一句', 'skipNext', () => this.handlePracticeNext());
        }
        .width('100%')
        .justifyContent(FlexAlign.SpaceAround);
      }
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 12, bottom: 12 })
    .backgroundColor(ThemeColors.bgCard)
    .borderRadius(this.isLandscape ? 12 : { topLeft: 12, topRight: 12 });
  }

  // 跟读练习：反馈区域（相似度 + 差异高亮）
  @Builder
  PracticeFeedbackBuilder() {
    Column() {
      // 用户说的内容（差异高亮：错误部分标红）
      Text('◉ 你说:')
        .fontSize(11)
        .fontColor(ThemeColors.textSecondary)
        .width('100%')
        .margin({ bottom: 4 });

      if (this.practiceMatchResult && this.practiceMatchResult.userHighlighted.length > 0) {
        Text() {
          ForEach(this.practiceMatchResult.userHighlighted, (seg: HighlightSegment, i: number) => {
            Span(seg.text)
              .fontSize(18)
              .fontColor(seg.isDiff ? ThemeColors.error : ThemeColors.textPrimary)
              .fontWeight(seg.isDiff ? 700 : 500);
          }, (seg: HighlightSegment, i: number) => `${i}-${seg.text}`);
        }
        .width('100%')
        .margin({ bottom: 8 });
      }

      // 相似度
      if (this.practiceMatchResult) {
        Row() {
          Text(`相似度 ${Math.round(this.practiceMatchResult.similarity * 100)}%`)
            .fontSize(15)
            .fontColor(this.practiceMatchResult.isCorrect ? ThemeColors.success : ThemeColors.error)
            .fontWeight(700);
          Text(this.practiceMatchResult.isCorrect ? '  ✓ 正确！' : '  ⚠ 接近，再试一次')
            .fontSize(13)
            .fontColor(this.practiceMatchResult.isCorrect ? ThemeColors.success : ThemeColors.error);
        }
        .width('100%')
        .margin({ bottom: 8 });
      }

      // 错误时显示"应该说"（目标句子，漏字灰色）
      if (this.practiceMatchResult && !this.practiceMatchResult.isCorrect) {
        Text('💡 应该说:')
          .fontSize(11)
          .fontColor(ThemeColors.textSecondary)
          .width('100%')
          .margin({ bottom: 4 });

        Text() {
          ForEach(this.practiceMatchResult.originalHighlighted, (seg: HighlightSegment, i: number) => {
            Span(seg.text)
              .fontSize(16)
              .fontColor(seg.isDiff ? ThemeColors.textTertiary : ThemeColors.textSecondary)
              .fontWeight(seg.isDiff ? 400 : 500);
          }, (seg: HighlightSegment, i: number) => `${i}-${seg.text}`);
        }
        .width('100%')
        .margin({ bottom: 8 });
      }
    }
    .width('100%')
    .margin({ bottom: 8 });
  }

  @Builder
  PracticeButtonBuilder(label: string, icon: string, onClick: () => void) {
    Column() {
      if (icon === 'skipBack') {
        SkipBackIcon({ color: ThemeColors.textPrimary, iconSize: 24 });
      } else if (icon === 'skipNext') {
        SkipNextIcon({ color: ThemeColors.textPrimary, iconSize: 24 });
      } else if (icon === 'play') {
        PlayIcon({ color: ThemeColors.textPrimary, iconSize: 24 });
      } else if (icon === 'slow') {
        SlowIcon({ color: ThemeColors.textPrimary, iconSize: 24 });
      } else {
        RecordIcon({ color: ThemeColors.textPrimary, iconSize: 24 });
      }

      Text(label)
        .fontSize(12)
        .fontColor(ThemeColors.textSecondary)
        .margin({ top: 6 });
    }
    .width(52)
    .height(52)
    .backgroundColor(ThemeColors.bgCardElevated)
    .borderRadius(14)
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      onClick();
    });
  }

  // ---- 测验 Tab ----
  @Builder
  buildQuizTab() {
    if (!this.currentQuiz) {
      Column() {
        Text('暂无测验题目')
          .fontSize(14)
          .fontColor(ThemeColors.textTertiary);
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center);
    } else {
      Column() {
        // 测验卡片
        QuizCard({
          quiz: this.currentQuiz!,
          selectedIndex: this.quizSelectedIndex,
          showResult: this.quizShowResult,
          onSelect: (index: number) => this.handleQuizSelect(index)
        });

        Blank();

        // 提交/重新答题按钮
        if (!this.quizSubmitted) {
          Text('提交答案')
            .fontSize(15)
            .fontColor('#FFFFFF')
            .fontWeight(600)
            .width('100%')
            .height(48)
            .textAlign(TextAlign.Center)
            .backgroundColor(this.quizSelectedIndex >= 0 ? ThemeColors.primary : ThemeColors.bgCardElevated)
            .borderRadius(12)
            .opacity(this.quizSelectedIndex >= 0 ? 1 : 0.5)
            .onClick(() => {
              if (this.quizSelectedIndex >= 0) {
                this.handleQuizSubmit();
              }
            });
        } else {
          Column() {
            // 得分显示
            Text(`得分：${this.quizScore}分`)
              .fontSize(20)
              .fontColor(this.quizScore >= 60 ? ThemeColors.success : ThemeColors.error)
              .fontWeight(700);

            Text(this.quizScore >= 60 ? '答对了！继续加油~' : '答错了，再试一次吧')
              .fontSize(13)
              .fontColor(ThemeColors.textSecondary)
              .margin({ top: 4 });

            Text('重新答题')
              .fontSize(14)
              .fontColor(ThemeColors.primary)
              .width('100%')
              .height(44)
              .textAlign(TextAlign.Center)
              .backgroundColor(ThemeColors.bgCard)
              .borderRadius(10)
              .margin({ top: 16 })
              .onClick(() => {
                this.handleQuizReset();
              });
          }
          .width('100%')
          .alignItems(HorizontalAlign.Center);
        }
      }
      .width('100%')
      .height('100%');
    }
  }

  // ---- 加载状态 ----
  @Builder
  LoadingBuilder() {
    Column() {
      Text('加载中...')
        .fontSize(14)
        .fontColor(ThemeColors.textSecondary);
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center);
  }

  // ---- 错误状态 ----
  @Builder
  ErrorBuilder() {
    Column() {
      Text('✗')
        .fontSize(48);

      Text(this.loadError || '场景不存在')
        .fontSize(14)
        .fontColor(ThemeColors.textTertiary)
        .margin({ top: 12 });

      Text('返回')
        .fontSize(14)
        .fontColor(ThemeColors.primary)
        .padding({ left: 20, right: 20, top: 10, bottom: 10 })
        .backgroundColor(ThemeColors.bgCard)
        .borderRadius(8)
        .margin({ top: 20 })
        .onClick(() => {
          this.onBack();
        });
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center);
  }

  // ---- 辅助方法 ----
  private getCurrentSentenceJapanese(): string {
    const dialogue = this.currentDialogue;
    if (!dialogue) {
      return '';
    }
    if (this.playerDialogueIndex === this.currentDialogueIndex
      && this.playerSentenceIndex >= 0 && this.playerSentenceIndex < dialogue.sentences.length) {
      return dialogue.sentences[this.playerSentenceIndex].japanese;
    }
    return '';
  }
}
