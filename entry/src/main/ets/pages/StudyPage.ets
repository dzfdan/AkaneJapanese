/**
 * 驻车学习详情页
 * 左右分栏布局，包含对话、跟读练习、测验三个 Tab
 */

import { ThemeColors } from '../constants/ThemeConstants';
import { AppConstants } from '../constants/AppConstants';
import { Scene } from '../model/Scene';
import { Dialogue } from '../model/Dialogue';
import { Sentence } from '../model/Sentence';
import { QuizItem } from '../model/QuizItem';
import { SceneRepository } from '../service/SceneRepository';
import { SettingsStore } from '../service/SettingsStore';
import { ProgressStore } from '../service/ProgressStore';
import { SentenceItem } from '../components/SentenceItem';
import { QuizCard } from '../components/QuizCard';
import { PlayerBar } from '../components/PlayerBar';
import appLogger from '../utils/Logger';

type TabType = 'dialogue' | 'practice' | 'quiz';

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
  @State currentSentenceIndex: number = 0;
  @State currentTimeMs: number = 0;
  @State durationMs: number = 0;

  // 测验相关状态
  @State quizSelectedIndex: number = -1;
  @State quizShowResult: boolean = false;
  @State quizScore: number = 0;
  @State quizSubmitted: boolean = false;

  // 跟读练习相关状态
  @State practiceSentenceIndex: number = 0;

  // 屏幕宽度断点
  @State screenWidth: number = 600;

  aboutToAppear(): void {
    this.loadData();
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

      // 初始化播放时长
      if (this.scene && this.currentDialogue) {
        const sentences = this.currentDialogue.sentences;
        if (sentences.length > 0) {
          const lastSentence = sentences[sentences.length - 1];
          this.durationMs = lastSentence.endTime * 1000;
        }
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
    return this.scene.dialogues[this.currentDialogueIndex];
  }

  private get isWideScreen(): boolean {
    return this.screenWidth >= AppConstants.BREAKPOINTS.lg;
  }

  private getSentenceKey(dialogueIdx: number, sentenceIdx: number): string {
    return `${this.sceneId}:${dialogueIdx}:${sentenceIdx}`;
  }

  private handlePlaySentence(dialogueIdx: number, sentenceIdx: number): void {
    this.currentSentenceIndex = sentenceIdx;
    this.isPlaying = !this.isPlaying;
    // 实际播放逻辑由 PlayerController 处理，此处仅更新 UI 状态
    appLogger.debug(`StudyPage: play sentence ${sentenceIdx} in dialogue ${dialogueIdx}`);
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
    this.isPlaying = !this.isPlaying;
  }

  private handlePrevSentence(): void {
    if (this.currentSentenceIndex > 0) {
      this.currentSentenceIndex -= 1;
    }
  }

  private handleNextSentence(): void {
    const dialogue = this.currentDialogue;
    if (dialogue && this.currentSentenceIndex < dialogue.sentences.length - 1) {
      this.currentSentenceIndex += 1;
    }
  }

  // ---- 跟读练习相关 ----
  private get practiceSentence(): Sentence | null {
    const dialogue = this.currentDialogue;
    if (!dialogue || this.practiceSentenceIndex < 0 || this.practiceSentenceIndex >= dialogue.sentences.length) {
      return null;
    }
    return dialogue.sentences[this.practiceSentenceIndex];
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
    appLogger.debug('StudyPage: play original audio for practice');
  }

  private handlePracticeSlow(): void {
    appLogger.debug('StudyPage: play slow audio for practice');
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
        this.ContentBuilder()
          .layoutWeight(1);

        // 底部 PlayerBar
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
    .width('100%')
    .height('100%')
    .backgroundColor(ThemeColors.bgApp)
    .padding(16)
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
    .height(56)
    .alignItems(VerticalAlign.Center);
  }

  // ---- Tab 切换栏 ----
  @Builder
  TabBarBuilder() {
    Row() {
      this.TabItemBuilder('对话', 'dialogue');
      this.TabItemBuilder('跟读练习', 'practice');
      this.TabItemBuilder('测验', 'quiz');
    }
    .width('100%')
    .height(40)
    .backgroundColor(ThemeColors.bgCard)
    .borderRadius(10)
    .padding(4)
    .margin({ top: 8, bottom: 12 });
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
        this.currentTab = tab;
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
      this.buildQuizTab();
    }
  }

  // ---- 对话 Tab ----
  @Builder
  buildDialogueTab() {
    if (this.isWideScreen) {
      // 宽屏：左右分栏
      Row() {
        // 左侧：对话列表
        this.DialogueListBuilder()
          .width('35%')
          .margin({ right: 12 });

        // 右侧：句子列表
        this.SentenceListBuilder()
          .layoutWeight(1);
      }
      .width('100%')
      .height('100%');
    } else {
      // 窄屏：上下结构
      Column() {
        // 对话选择器（横滑）
        this.DialogueScrollBuilder()
          .margin({ bottom: 12 });

        // 句子列表
        this.SentenceListBuilder()
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
      this.currentDialogueIndex = index;
      this.currentSentenceIndex = 0;
      this.practiceSentenceIndex = 0;
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
            this.currentDialogueIndex = index;
            this.currentSentenceIndex = 0;
            this.practiceSentenceIndex = 0;
            this.handleQuizReset();
          });
        }, (dialogue: Dialogue) => dialogue.id);
      }
    }
    .width('100%')
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off);
  }

  // ---- 句子列表 ----
  @Builder
  SentenceListBuilder() {
    const dialogue = this.currentDialogue;
    if (!dialogue || dialogue.sentences.length === 0) {
      Column() {
        Text('暂无对话内容')
          .fontSize(14)
          .fontColor(ThemeColors.textTertiary);
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center);
    } else {
      List() {
        ForEach(dialogue.sentences, (sentence: Sentence, sIndex: number) => {
          ListItem() {
            SentenceItem({
              sentence: sentence,
              showRomaji: this.showRomaji,
              showTranslation: this.showTranslation,
              isFavorite: this.favorites.has(this.getSentenceKey(this.currentDialogueIndex, sIndex)),
              isPlaying: this.isPlaying && this.currentSentenceIndex === sIndex,
              onPlay: () => this.handlePlaySentence(this.currentDialogueIndex, sIndex),
              onToggleFavorite: () => this.handleToggleFavorite(this.currentDialogueIndex, sIndex)
            });
          }
          .margin({ bottom: sIndex < dialogue.sentences.length - 1 ? 8 : 0 });
        }, (sentence: Sentence) => sentence.id);
      }
      .width('100%')
      .layoutWeight(1);
    }
  }

  // ---- 跟读练习 Tab ----
  @Builder
  buildPracticeTab() {
    const sentence = this.practiceSentence;
    if (!sentence) {
      Column() {
        Text('暂无练习内容')
          .fontSize(14)
          .fontColor(ThemeColors.textTertiary);
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center);
    } else {
      Column() {
        // 进度指示
        Text(`${this.practiceSentenceIndex + 1} / ${this.currentDialogue?.sentences.length || 0}`)
          .fontSize(12)
          .fontColor(ThemeColors.textTertiary)
          .margin({ bottom: 24 });

        // 说话人
        Text(sentence.speakerRoleZh)
          .fontSize(12)
          .fontColor(ThemeColors.primary)
          .fontWeight(600)
          .margin({ bottom: 12 });

        // 日文原文（放大显示）
        Text(sentence.japanese)
          .fontSize(24)
          .fontColor(ThemeColors.textPrimary)
          .fontWeight(600)
          .textAlign(TextAlign.Center)
          .width('100%')
          .margin({ bottom: 12 });

        // 罗马音
        if (this.showRomaji) {
          Text(sentence.romaji)
            .fontSize(14)
            .fontColor(ThemeColors.textSecondary)
            .textAlign(TextAlign.Center)
            .width('100%')
            .margin({ bottom: 8 });
        }

        // 中文翻译
        if (this.showTranslation) {
          Text(sentence.translation)
            .fontSize(13)
            .fontColor(ThemeColors.textTertiary)
            .textAlign(TextAlign.Center)
            .width('100%');
        }

        Blank();

        // 三个操作按钮
        Row() {
          this.PracticeButtonBuilder('原音', '▶', () => this.handlePracticePlay());
          this.PracticeButtonBuilder('慢速', '🐢', () => this.handlePracticeSlow());
          this.PracticeButtonBuilder('下一句', '⏭', () => this.handlePracticeNext());
        }
        .width('100%')
        .justifyContent(FlexAlign.SpaceAround)
        .margin({ bottom: 24 });
      }
      .width('100%')
      .height('100%')
      .alignItems(HorizontalAlign.Center)
      .padding({ top: 40, bottom: 20 });
    }
  }

  @Builder
  PracticeButtonBuilder(label: string, icon: string, onClick: () => void) {
    Column() {
      Text(icon)
        .fontSize(24)
        .fontColor(ThemeColors.textPrimary);

      Text(label)
        .fontSize(12)
        .fontColor(ThemeColors.textSecondary)
        .margin({ top: 6 });
    }
    .width(80)
    .height(80)
    .backgroundColor(ThemeColors.bgCard)
    .borderRadius(16)
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      onClick();
    });
  }

  // ---- 测验 Tab ----
  @Builder
  buildQuizTab() {
    const quiz = this.currentQuiz;
    if (!quiz) {
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
          quiz: quiz,
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
      Text('😕')
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
    if (!dialogue || this.currentSentenceIndex < 0 || this.currentSentenceIndex >= dialogue.sentences.length) {
      return '';
    }
    return dialogue.sentences[this.currentSentenceIndex].japanese;
  }
}
