import { ThemeColors } from '../constants/ThemeConstants';
import { Scene } from '../model/Scene';
import { Sentence } from '../model/Sentence';
import { FuriganaText } from './FuriganaText';
import { ConversationController, ConversationUiState } from '../service/ConversationController';
import { SherpaAsrEngine } from '../service/SherpaAsrEngine';
import { HighlightSegment } from '../service/SimilarityMatcher';
import { abilityAccessCtrl, common } from '@kit.AbilityKit';
import appLogger from '../utils/Logger';

@Component
export struct ConversationTab {
  @Prop scene: Scene | null = null;
  @Prop currentDialogueIndex: number = 0;
  @Prop practiceSentenceIndex: number = 0;

  @State uiState: ConversationUiState | null = null;
  @State permissionGranted: boolean = false;
  @State modelState: 'idle' | 'loading' | 'ready' | 'failed' = 'idle';
  private stateCallback: ((s: ConversationUiState) => void) | null = null;

  aboutToAppear(): void {
    this.stateCallback = (s: ConversationUiState) => {
      this.uiState = s;
    };
    ConversationController.getInstance().addOnStateChange(this.stateCallback);
    this.requestPermissionAndInitModel();
  }

  private async requestPermissionAndInitModel(): Promise<void> {
    const context = getContext(this) as common.UIAbilityContext;
    // 并行：请求麦克风权限 + 加载 ASR 模型
    const permPromise = abilityAccessCtrl.createAtManager()
      .requestPermissionsFromUser(context, ['ohos.permission.MICROPHONE'])
      .then((res) => {
        const granted = res.authResults && res.authResults[0] === 0;
        this.permissionGranted = granted;
        if (!granted) {
          appLogger.warn('[ConversationTab] microphone permission denied');
        }
      })
      .catch((e: Object) => {
        appLogger.error('[ConversationTab] requestPermissionsFromUser failed', e);
        this.permissionGranted = false;
      });
    this.modelState = 'loading';
    const modelPromise = SherpaAsrEngine.getInstance().init(context)
      .then(() => {
        this.modelState = SherpaAsrEngine.getInstance().isReady ? 'ready' : 'failed';
      })
      .catch((e: Object) => {
        appLogger.error('[ConversationTab] SherpaAsrEngine.init failed', e);
        this.modelState = 'failed';
      });
    await Promise.all([permPromise, modelPromise]);
  }

  private openSettings(): void {
    const context = getContext(this) as common.UIAbilityContext;
    try {
      context.startAbility({ action: 'action.settings' });
    } catch (e) {
      appLogger.error('[ConversationTab] openSettings failed', e);
    }
  }

  aboutToDisappear(): void {
    if (this.stateCallback) {
      ConversationController.getInstance().removeOnStateChange(this.stateCallback);
      this.stateCallback = null;
    }
    ConversationController.getInstance().stopConversation();
  }

  private handleStart(): void {
    const scene = this.scene;
    if (!scene) return;
    ConversationController.getInstance().startConversation(scene, this.currentDialogueIndex, this.practiceSentenceIndex).catch((e: Object) => {
      appLogger.error('ConversationTab: start failed', e);
    });
  }

  private handleRetry(): void {
    ConversationController.getInstance().retry();
  }

  private handleNext(): void {
    ConversationController.getInstance().nextSentence();
  }

  build() {
    Column() {
      if (!this.permissionGranted) {
        this.buildPermissionDenied();
      } else if (this.modelState === 'failed') {
        this.buildModelFailed();
      } else if (this.modelState === 'loading' || this.modelState === 'idle') {
        this.buildModelLoading();
      } else if (this.uiState === null || this.uiState.state === 'IDLE') {
        this.buildIdle();
      } else if (this.uiState.state === 'APP_SPEAKING') {
        this.buildAppSpeaking();
      } else if (this.uiState.state === 'WAITING_USER' || this.uiState.state === 'USER_SPEAKING') {
        this.buildWaitingUser();
      } else if (this.uiState.state === 'RECOGNIZING') {
        this.buildRecognizing();
      } else {
        this.buildFeedback();
      }
    }
    .width('100%')
    .height('100%')
    .padding({ top: 24, bottom: 24 });
  }

  @Builder
  buildIdle() {
    Column() {
      Text('🤖').fontSize(48).margin({ bottom: 24 });
      Text('对话模式').fontSize(20).fontWeight(700).margin({ bottom: 8 });
      Text('App 说一句，你跟一句，App 判断你说得对不对').fontSize(12).fontColor(ThemeColors.textSecondary).margin({ bottom: 32 });
      Button('▶ 开始对话')
        .width('80%').height(48).fontSize(16).fontWeight(600)
        .backgroundColor(ThemeColors.primary).fontColor('#FFFFFF')
        .borderRadius(12)
        .onClick(() => this.handleStart());
    }
    .width('100%').height('100%').justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center);
  }

  @Builder
  buildPermissionDenied() {
    Column() {
      Text('🔒').fontSize(48).margin({ bottom: 24 });
      Text('需要麦克风权限').fontSize(18).fontWeight(700).margin({ bottom: 8 });
      Text('对话模式需要使用麦克风进行语音识别').fontSize(12).fontColor(ThemeColors.textSecondary).margin({ bottom: 32 });
      Button('⚙ 去设置')
        .width('80%').height(48).fontSize(16).fontWeight(600)
        .backgroundColor(ThemeColors.primary).fontColor('#FFFFFF')
        .borderRadius(12)
        .onClick(() => this.openSettings());
    }
    .width('100%').height('100%').justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center);
  }

  @Builder
  buildModelFailed() {
    Column() {
      Text('⚠').fontSize(48).margin({ bottom: 24 });
      Text('模型未就绪').fontSize(18).fontWeight(700).margin({ bottom: 8 });
      Text('语音识别模型加载失败，请重启 App').fontSize(12).fontColor(ThemeColors.textSecondary);
    }
    .width('100%').height('100%').justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center);
  }

  @Builder
  buildModelLoading() {
    Column() {
      LoadingProgress().width(48).height(48).margin({ bottom: 16 });
      Text('⏳ 模型加载中…').fontSize(14).fontColor(ThemeColors.textSecondary);
    }
    .width('100%').height('100%').justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center);
  }

  @Builder
  buildAppSpeaking() {
    Column() {
      Text('🤖').fontSize(48).margin({ bottom: 12 });
      Text('App 说话中…').fontSize(14).fontColor(ThemeColors.textSecondary).margin({ bottom: 24 });
      if (this.uiState && this.uiState.currentSentence) {
        FuriganaText({
          segments: this.uiState.currentSentence.segments || [],
          japanese: this.uiState.currentSentence.japanese,
          fontSize: 24,
          fontColor: ThemeColors.textPrimary,
          fontWeight: 600,
          textAlign: TextAlign.Center,
          containerWidth: '90%'
        });
      }
    }
    .width('100%').height('100%').justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center);
  }

  @Builder
  buildWaitingUser() {
    Column() {
      Text('🎤').fontSize(48).margin({ bottom: 12 });
      Text('● 录音中（请跟读）').fontSize(14).fontColor(ThemeColors.error).margin({ bottom: 24 });
      if (this.uiState && this.uiState.currentSentence) {
        FuriganaText({
          segments: this.uiState.currentSentence.segments || [],
          japanese: this.uiState.currentSentence.japanese,
          fontSize: 24,
          fontColor: ThemeColors.textPrimary,
          fontWeight: 600,
          textAlign: TextAlign.Center,
          containerWidth: '90%'
        });
      }
    }
    .width('100%').height('100%').justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center);
  }

  @Builder
  buildRecognizing() {
    Column() {
      LoadingProgress().width(48).height(48).margin({ bottom: 16 });
      Text('⏳ 识别中…').fontSize(14).fontColor(ThemeColors.textSecondary);
    }
    .width('100%').height('100%').justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center);
  }

  @Builder
  buildFeedback() {
    Column() {
      // App 说
      Text('🤖 App 说:').fontSize(12).fontColor(ThemeColors.textSecondary).width('100%').margin({ bottom: 4 });
      if (this.uiState && this.uiState.currentSentence) {
        FuriganaText({
          segments: this.uiState.currentSentence.segments || [],
          japanese: this.uiState.currentSentence.japanese,
          fontSize: 20,
          fontColor: ThemeColors.textPrimary,
          fontWeight: 500,
          textAlign: TextAlign.Left,
          containerWidth: '100%'
        }).margin({ bottom: 16 });
      }

      // 用户说
      Text('🎤 你说:').fontSize(12).fontColor(ThemeColors.textSecondary).width('100%').margin({ bottom: 4 });
      if (this.uiState && this.uiState.lastMatch) {
        // 差异高亮：isDiff 标红，否则正常
        Text() {
          ForEach(this.uiState.lastMatch.userHighlighted, (seg: HighlightSegment, i: number) => {
            Text(seg.text)
              .fontSize(20)
              .fontColor(seg.isDiff ? ThemeColors.error : ThemeColors.textPrimary)
              .fontWeight(seg.isDiff ? 700 : 500);
          }, (seg: HighlightSegment, i: number) => `${i}-${seg.text}`);
        }
        .width('100%').margin({ bottom: 8 });
      }

      // 相似度
      if (this.uiState && this.uiState.lastMatch) {
        Row() {
          Text(`相似度 ${Math.round(this.uiState.lastMatch.similarity * 100)}%`)
            .fontSize(16)
            .fontColor(this.uiState.lastMatch.isCorrect ? ThemeColors.success : ThemeColors.error)
            .fontWeight(700);
          Text(this.uiState.lastMatch.isCorrect ? '  ✓ 正确！' : '  ⚠ 接近，再试一次')
            .fontSize(14)
            .fontColor(this.uiState.lastMatch.isCorrect ? ThemeColors.success : ThemeColors.error);
        }
        .width('100%').margin({ bottom: 16 });
      }

      // 错误时显示"应该说" + 漏字灰色
      if (this.uiState && this.uiState.lastMatch && !this.uiState.lastMatch.isCorrect) {
        Text('💡 应该说:').fontSize(12).fontColor(ThemeColors.textSecondary).width('100%').margin({ bottom: 4 });
        Text() {
          ForEach(this.uiState.lastMatch.originalHighlighted, (seg: HighlightSegment, i: number) => {
            Text(seg.text)
              .fontSize(18)
              .fontColor(seg.isDiff ? ThemeColors.textTertiary : ThemeColors.textSecondary)
              .fontWeight(seg.isDiff ? 400 : 500);
          }, (seg: HighlightSegment, i: number) => `${i}-${seg.text}`);
        }
        .width('100%').margin({ bottom: 16 });
      }

      // 重试次数
      if (this.uiState && this.uiState.retryCount > 0) {
        Text(`已重试 ${this.uiState.retryCount} 次`).fontSize(11).fontColor(ThemeColors.textTertiary).margin({ bottom: 12 });
      }

      Blank();

      // 按钮组
      Row() {
        Button('🔁 重试')
          .layoutWeight(1).height(44).fontSize(14)
          .backgroundColor(ThemeColors.bgCard).fontColor(ThemeColors.textPrimary)
          .borderRadius(10).margin({ right: 8 })
          .onClick(() => this.handleRetry());
        Button('⏭ 下一句')
          .layoutWeight(1).height(44).fontSize(14)
          .backgroundColor(ThemeColors.primary).fontColor('#FFFFFF')
          .borderRadius(10)
          .onClick(() => this.handleNext());
      }
      .width('100%');
    }
    .width('100%').height('100%').padding({ left: 16, right: 16 });
  }
}

