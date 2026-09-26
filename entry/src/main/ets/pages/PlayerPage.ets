/**
 * 驾驶模式全屏播放页
 * 大字号、大按钮、信息精简，符合驾驶安全
 */

import { ThemeColors } from '../constants/ThemeConstants';
import { AppConstants } from '../constants/AppConstants';
import { PlayerController, PlayerUiState } from '../service/PlayerController';
import { SceneRepository } from '../service/SceneRepository';
import { SettingsStore } from '../service/SettingsStore';
import { UserSettings } from '../model/UserSettings';
import { Sentence, Segment } from '../model/Sentence';
import { FuriganaText } from '../components/FuriganaText';
import { formatDuration } from '../utils/TimeUtil';
import appLogger from '../utils/Logger';

@Component
export struct PlayerPage {
  @Prop isVisible: boolean = false;
  onClose: () => void = () => {};

  @State sceneTitle: string = '';
  @State dialogueTitle: string = '';
  @State japanese: string = '';
  @State currentSegments: Segment[] = [];
  @State romaji: string = '';
  @State translation: string = '';
  @State isPlaying: boolean = false;
  @State currentTimeMs: number = 0;
  @State durationMs: number = 0;
  @State speed: number = 1.0;
  @State showRomaji: boolean = true;
  @State showTranslation: boolean = true;
  @State sentenceIndex: number = 0;
  @State totalSentences: number = 0;
  @State dialogueIndex: number = 0;
  @State totalDialogues: number = 0;

  private stateCallback: ((state: PlayerUiState) => void) | null = null;
  private timeCallback: ((currentTimeMs: number, durationMs: number) => void) | null = null;
  private settingsCallback: ((settings: UserSettings) => void) | null = null;

  aboutToAppear() {
    appLogger.info('PlayerPage aboutToAppear');

    // 从 PlayerController 获取初始状态
    const uiState = PlayerController.getInstance().getUiState();
    this.updateFromPlayerState(uiState);

    // 订阅 PlayerController 状态变化
    this.stateCallback = (state: PlayerUiState) => {
      this.updateFromPlayerState(state);
    };
    PlayerController.getInstance().addOnStateChange(this.stateCallback);

    // 订阅时间更新
    this.timeCallback = (currentTimeMs: number, durationMs: number) => {
      this.currentTimeMs = currentTimeMs;
      this.durationMs = durationMs;
    };
    PlayerController.getInstance().addOnTimeUpdate(this.timeCallback);

    // 从 SettingsStore 获取显示偏好
    const settings = SettingsStore.getInstance().getSettings();
    this.showRomaji = settings.showRomaji;
    this.showTranslation = settings.showTranslation;

    // 订阅设置变化
    this.settingsCallback = (newSettings: UserSettings) => {
      this.showRomaji = newSettings.showRomaji;
      this.showTranslation = newSettings.showTranslation;
    };
    SettingsStore.getInstance().addOnSettingsChange(this.settingsCallback);
  }

  aboutToDisappear() {
    appLogger.info('PlayerPage aboutToDisappear');

    // 取消订阅
    if (this.stateCallback) {
      PlayerController.getInstance().removeOnStateChange(this.stateCallback);
    }
    if (this.timeCallback) {
      PlayerController.getInstance().removeOnTimeUpdate(this.timeCallback);
    }
    if (this.settingsCallback) {
      SettingsStore.getInstance().removeOnSettingsChange(this.settingsCallback);
    }

    this.stateCallback = null;
    this.timeCallback = null;
    this.settingsCallback = null;
  }

  private updateFromPlayerState(state: PlayerUiState): void {
    this.isPlaying = state.isPlaying;
    this.sceneTitle = state.sceneTitle;
    this.dialogueTitle = state.dialogueTitle;
    this.speed = state.speed;
    this.dialogueIndex = state.dialogueIndex;

    if (state.currentSentence) {
      this.japanese = state.currentSentence.japanese;
      this.currentSegments = state.currentSentence.segments || [];
      this.romaji = state.currentSentence.romaji;
      this.translation = state.currentSentence.translation;
      this.sentenceIndex = state.sentenceIndex + 1;
    } else {
      this.japanese = '';
      this.currentSegments = [];
      this.romaji = '';
      this.translation = '';
      this.sentenceIndex = 0;
    }

    if (state.sceneId) {
      const scene = SceneRepository.getInstance().getSceneById(state.sceneId);
      const dialogue = scene ? scene.dialogues[state.dialogueIndex] : undefined;
      this.totalDialogues = scene ? scene.dialogues.length : 0;
      this.totalSentences = dialogue ? dialogue.sentences.length : 0;
    } else {
      this.totalDialogues = 0;
      this.totalSentences = 0;
    }
  }

  private handlePlayPause(): void {
    PlayerController.getInstance().togglePlay();
  }

  private handlePrev(): void {
    PlayerController.getInstance().prevSentence();
  }

  private handleNext(): void {
    PlayerController.getInstance().nextSentence();
  }

  private handleSpeedChange(speed: number): void {
    PlayerController.getInstance().setSpeed(speed);
  }

  private handleSeek(ratio: number): void {
    const targetTime = this.durationMs * ratio;
    PlayerController.getInstance().seekTo(targetTime);
  }

  build() {
    Column() {
      // 顶部：返回按钮 + 场景名
      Row() {
        // 返回按钮
        Stack() {
          Circle()
            .width(44)
            .height(44)
            .fill(ThemeColors.bgCardElevated);

          Text('←')
            .fontSize(20)
            .fontColor(ThemeColors.textPrimary);
        }
        .width(44)
        .height(44)
        .onClick(() => {
          this.onClose();
        });

        // 场景标题
        Column() {
          Text(this.sceneTitle)
            .fontSize(16)
            .fontColor(ThemeColors.textPrimary)
            .fontWeight(600)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .maxLines(1);

          if (this.dialogueTitle) {
            Text(this.dialogueTitle)
              .fontSize(12)
              .fontColor(ThemeColors.textTertiary)
              .margin({ top: 2 })
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .maxLines(1);
          }
        }
        .layoutWeight(1)
        .margin({ left: 16 })
        .alignItems(HorizontalAlign.Start);
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 16, bottom: 16 });

      // 中部：当前句子内容
      Column() {
        // 日文（大字号，居中，含振假名注音）
        FuriganaText({
          segments: this.currentSegments,
          japanese: this.japanese || '—',
          fontSize: 32,
          fontColor: ThemeColors.textPrimary,
          fontWeight: 500,
          textAlign: TextAlign.Center,
          containerWidth: '100%'
        });

        // 罗马音
        if (this.showRomaji && this.romaji) {
          Text(this.romaji)
            .fontSize(16)
            .fontColor(ThemeColors.textSecondary)
            .textAlign(TextAlign.Center)
            .width('100%')
            .margin({ top: 16 });
        }

        // 翻译
        if (this.showTranslation && this.translation) {
          Text(this.translation)
            .fontSize(14)
            .fontColor(ThemeColors.textTertiary)
            .textAlign(TextAlign.Center)
            .width('100%')
            .margin({ top: 12 });
        }
      }
      .layoutWeight(1)
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .padding({ left: 24, right: 24 });

      // 下部：控制区
      Column() {
        // 进度条 + 时间
        Column() {
          // 进度条
          Stack({ alignContent: Alignment.Start }) {
            Rect()
              .width('100%')
              .height(6)
              .fill(ThemeColors.bgCardElevated)
              .borderRadius(3);

            Rect()
              .width(this.getProgressWidth())
              .height(6)
              .fill(ThemeColors.primary)
              .borderRadius(3);
          }
          .width('100%');

          // 时间显示
          Row() {
            Text(formatDuration(this.currentTimeMs / 1000))
              .fontSize(12)
              .fontColor(ThemeColors.textTertiary);

            Blank();

            Text(formatDuration(this.durationMs / 1000))
              .fontSize(12)
              .fontColor(ThemeColors.textTertiary);
          }
          .width('100%')
          .margin({ top: 8 });
        }
        .width('100%')
        .padding({ left: 24, right: 24 });

        // 控制按钮：上一首 / 播放暂停 / 下一首
        Row() {
          // 上一首按钮（大按钮）
          Stack() {
            Circle()
              .width(64)
              .height(64)
              .fill(ThemeColors.bgCardElevated);

            Text('⏮')
              .fontSize(28)
              .fontColor(ThemeColors.textPrimary);
          }
          .width(64)
          .height(64)
          .onClick(() => {
            this.handlePrev();
          });

          // 播放/暂停按钮（主按钮，更大）
          Stack() {
            Circle()
              .width(88)
              .height(88)
              .fill(ThemeColors.primary);

            Text(this.isPlaying ? '⏸' : '▶')
              .fontSize(36)
              .fontColor('#FFFFFF');
          }
          .width(88)
          .height(88)
          .margin({ left: 32, right: 32 })
          .onClick(() => {
            this.handlePlayPause();
          });

          // 下一首按钮（大按钮）
          Stack() {
            Circle()
              .width(64)
              .height(64)
              .fill(ThemeColors.bgCardElevated);

            Text('⏭')
              .fontSize(28)
              .fontColor(ThemeColors.textPrimary);
          }
          .width(64)
          .height(64)
          .onClick(() => {
            this.handleNext();
          });
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .margin({ top: 28 });

        // 倍速切换
        Row() {
          ForEach(AppConstants.SPEED_OPTIONS, (speed: number) => {
            Text(`${speed}x`)
              .fontSize(14)
              .fontColor(this.speed === speed ? '#FFFFFF' : ThemeColors.textSecondary)
              .backgroundColor(this.speed === speed ? ThemeColors.primary : ThemeColors.bgCardElevated)
              .borderRadius(18)
              .padding({ left: 16, right: 16, top: 8, bottom: 8 })
              .margin({ left: 4, right: 4 })
              .onClick(() => {
                this.handleSpeedChange(speed);
              });
          }, (speed: number) => speed.toString());
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .margin({ top: 24 });

        // 句子导航信息
        if (this.sentenceIndex > 0 && this.totalSentences > 0) {
          Column() {
            Text(`第 ${this.sentenceIndex} / ${this.totalSentences} 句`)
              .fontSize(12)
              .fontColor(ThemeColors.textTertiary);

            if (this.totalDialogues > 1) {
              Text(`对话 ${this.dialogueIndex + 1} / ${this.totalDialogues}`)
                .fontSize(12)
                .fontColor(ThemeColors.textTertiary)
                .margin({ top: 4 });
            }
          }
          .margin({ top: 16 });
        }
      }
      .width('100%')
      .padding({ left: 24, right: 24, top: 16, bottom: 32 });
    }
    .width('100%')
    .height('100%')
    .backgroundColor(ThemeColors.bgApp);
  }

  private getProgressWidth(): string {
    if (this.durationMs <= 0) {
      return '0%';
    }
    const percent = Math.max(0, Math.min(1, this.currentTimeMs / this.durationMs));
    return `${percent * 100}%`;
  }
}
