/**
 * 应用主容器页面
 * 管理导航、布局模式、播放状态，以及页面间切换
 */

import { mediaquery } from '@kit.ArkUI';
import { ThemeColors } from '../constants/ThemeConstants';
import { AppConstants } from '../constants/AppConstants';
import { SideNav } from '../components/SideNav';
import { BottomTab } from '../components/BottomTab';
import { PlayerBar } from '../components/PlayerBar';
import { MiniPlayer } from '../components/MiniPlayer';
import { SceneListPage } from './SceneListPage';
import { PlayerPage } from './PlayerPage';
import { StudyPage } from './StudyPage';
import { ProgressPage } from './ProgressPage';
import { SettingsPage } from './SettingsPage';
import { ModeManager, AppMode } from '../service/ModeManager';
import { PlayerController, PlayerUiState } from '../service/PlayerController';
import { SceneRepository } from '../service/SceneRepository';
import { Scene } from '../model/Scene';
import { Segment } from '../model/Sentence';
import appLogger from '../utils/Logger';

@Entry
@Component
struct Index {
  @State currentTab: string = 'scenes';
  @State currentMode: 'driving' | 'parked' = 'parked';
  @State isWideScreen: boolean = false;
  // 横屏（16:9 车机/平板）适配状态
  @State isLandscape: boolean = false;
  @State windowWidth: number = 0;
  @State windowHeight: number = 0;

  // 播放器状态
  @State isPlaying: boolean = false;
  @State currentSentence: string = '';
  @State currentSegments: Segment[] = [];
  @State currentSceneTitle: string = '';
  @State currentTimeMs: number = 0;
  @State durationMs: number = 0;
  @State hasPlayContent: boolean = false;

  // 全屏播放页（驾驶模式）
  @State showPlayerPage: boolean = false;

  // 驻车学习详情页
  @State showStudyPage: boolean = false;
  @State selectedSceneId: string = '';

  private mediaQueryListener: mediaquery.MediaQueryListener | null = null;
  private orientationListener: mediaquery.MediaQueryListener | null = null;
  private modeChangeCallback: ((mode: AppMode) => void) | null = null;
  private stateChangeCallback: ((state: PlayerUiState) => void) | null = null;
  private timeUpdateCallback: ((currentTimeMs: number, durationMs: number) => void) | null = null;

  aboutToAppear() {
    appLogger.info('Index aboutToAppear');

    // 从 ModeManager 获取初始模式
    this.currentMode = ModeManager.getInstance().getMode();

    // 订阅 ModeManager 模式变化
    this.modeChangeCallback = (mode: AppMode) => {
      this.currentMode = mode;
    };
    ModeManager.getInstance().addOnModeChange(this.modeChangeCallback);

    // 从 PlayerController 获取初始状态
    const uiState = PlayerController.getInstance().getUiState();
    this.updatePlayerState(uiState);

    // 订阅 PlayerController 状态变化
    this.stateChangeCallback = (state: PlayerUiState) => {
      this.updatePlayerState(state);
    };
    PlayerController.getInstance().addOnStateChange(this.stateChangeCallback);

    this.timeUpdateCallback = (currentTimeMs: number, durationMs: number) => {
      this.currentTimeMs = currentTimeMs;
      this.durationMs = durationMs;
    };
    PlayerController.getInstance().addOnTimeUpdate(this.timeUpdateCallback);

    // 初始化屏幕宽度判断
    this.initMediaQuery();
  }

  aboutToDisappear() {
    appLogger.info('Index aboutToDisappear');

    // 取消订阅
    if (this.modeChangeCallback) {
      ModeManager.getInstance().removeOnModeChange(this.modeChangeCallback);
      this.modeChangeCallback = null;
    }
    if (this.stateChangeCallback) {
      PlayerController.getInstance().removeOnStateChange(this.stateChangeCallback);
      this.stateChangeCallback = null;
    }
    if (this.timeUpdateCallback) {
      PlayerController.getInstance().removeOnTimeUpdate(this.timeUpdateCallback);
      this.timeUpdateCallback = null;
    }

    // 注销 mediaquery 监听
    if (this.mediaQueryListener) {
      this.mediaQueryListener.off('change');
      this.mediaQueryListener = null;
    }
    if (this.orientationListener) {
      this.orientationListener.off('change');
      this.orientationListener = null;
    }
  }

  private updatePlayerState(state: PlayerUiState): void {
    this.isPlaying = state.isPlaying;
    this.currentSceneTitle = state.sceneTitle;
    this.currentTimeMs = state.currentTimeMs;
    this.durationMs = state.durationMs;
    this.hasPlayContent = !!state.sceneId && !!state.currentSentence;
    if (state.currentSentence) {
      this.currentSentence = state.currentSentence.japanese;
      this.currentSegments = state.currentSentence.segments || [];
    } else {
      this.currentSentence = '';
      this.currentSegments = [];
    }
  }

  private initMediaQuery(): void {
    const breakpoint = AppConstants.BREAKPOINTS.md;
    const condition = `(width >= ${breakpoint}vp)`;
    try {
      this.mediaQueryListener = mediaquery.matchMediaSync(condition);
      this.isWideScreen = this.mediaQueryListener.matches;
      appLogger.info(`Initial screen: isWideScreen=${this.isWideScreen}`);

      this.mediaQueryListener.on('change', (result: mediaquery.MediaQueryResult) => {
        this.isWideScreen = result.matches;
        appLogger.info(`Screen changed: isWideScreen=${this.isWideScreen}`);
      });
    } catch (err) {
      appLogger.error('MediaQuery init failed: ' + JSON.stringify(err));
      // 默认宽屏
      this.isWideScreen = true;
    }

    // 横屏（16:9）监听
    try {
      this.orientationListener = mediaquery.matchMediaSync('(orientation: landscape)');
      this.isLandscape = this.orientationListener.matches;
      this.orientationListener.on('change', (result: mediaquery.MediaQueryResult) => {
        this.isLandscape = result.matches;
        appLogger.info(`Orientation changed: isLandscape=${this.isLandscape}`);
      });
    } catch (err) {
      appLogger.error('Orientation mediaquery init failed: ' + JSON.stringify(err));
    }
  }

  /**
   * 同步窗口尺寸到 AppStorage，供各页面做横屏布局判断
   */
  private syncWindowSize(width: number, height: number): void {
    if (isNaN(width) || isNaN(height) || width <= 0 || height <= 0) {
      return;
    }
    if (Math.abs(width - this.windowWidth) > 0.5 || Math.abs(height - this.windowHeight) > 0.5) {
      this.windowWidth = width;
      this.windowHeight = height;
      AppStorage.setOrCreate('windowWidth', width);
      AppStorage.setOrCreate('windowHeight', height);
      AppStorage.setOrCreate('isLandscape', width > height);
    }
  }

  build() {
    Stack() {
      // 主界面
      Column() {
        // 主内容区
        if (this.isWideScreen || this.isLandscape) {
          // 宽屏模式：SideNav + 内容页
          Row() {
            SideNav({
              currentTab: $currentTab,
              onTabChange: (tab: string) => {
                this.currentTab = tab;
              }
            });

            Column() {
              this.buildContentPage();
            }
            .layoutWeight(1)
            .height('100%');
          }
          .layoutWeight(1)
          .width('100%');
        } else {
          // 窄屏模式：内容页 + BottomTab
          Column() {
            this.buildContentPage();
          }
          .layoutWeight(1)
          .width('100%');

          // 窄屏底部 TAB
          BottomTab({
            currentTab: $currentTab,
            onTabChange: (tab: string) => {
              this.currentTab = tab;
            }
          });
        }

        // 底部播放条（有播放内容时显示）
        if (this.hasPlayContent) {
          if (this.isWideScreen) {
            PlayerBar({
              sceneTitle: this.currentSceneTitle,
              sentenceJapanese: this.currentSentence,
              segments: this.currentSegments,
              isPlaying: this.isPlaying,
              currentTimeMs: this.currentTimeMs,
              durationMs: this.durationMs,
              onPlayPause: () => {
                PlayerController.getInstance().togglePlay();
              },
              onPrev: () => {
                PlayerController.getInstance().prevSentence();
              },
              onNext: () => {
                PlayerController.getInstance().nextSentence();
              },
              onBarClick: () => {
                // 驾驶模式点击播放条进入全屏播放页
                if (this.currentMode === 'driving') {
                  this.showPlayerPage = true;
                }
              }
            })
            .width('100%')
            .padding(this.isLandscape ? 8 : 12);
          } else {
            MiniPlayer({
              sentenceJapanese: this.currentSentence,
              segments: this.currentSegments,
              isPlaying: this.isPlaying,
              onPlayPause: () => {
                PlayerController.getInstance().togglePlay();
              },
              onBarClick: () => {
                // 驾驶模式点击进入全屏播放页
                if (this.currentMode === 'driving') {
                  this.showPlayerPage = true;
                }
              }
            })
            .width('100%');
          }
        }
      }
      .width('100%')
      .height('100%');

      // 全屏播放页（驾驶模式覆盖层）
      if (this.showPlayerPage) {
        PlayerPage({
          isVisible: this.showPlayerPage,
          onClose: () => {
            this.showPlayerPage = false;
          }
        })
        .width('100%')
        .height('100%');
      }

      // 驻车学习详情页（覆盖层）
      if (this.showStudyPage) {
        StudyPage({
          isVisible: this.showStudyPage,
          sceneId: this.selectedSceneId,
          onBack: () => {
            this.showStudyPage = false;
          }
        })
        .width('100%')
        .height('100%');
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(ThemeColors.bgApp)
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      this.syncWindowSize(Number(newArea.width), Number(newArea.height));
    });
  }

  @Builder
  buildContentPage() {
    if (this.currentTab === 'scenes') {
      SceneListPage({
        onSceneClick: (sceneId: string) => {
          this.handleSceneClick(sceneId);
        }
      })
      .width('100%')
      .height('100%');
    } else if (this.currentTab === 'progress') {
      ProgressPage()
        .width('100%')
        .height('100%');
    } else if (this.currentTab === 'settings') {
      SettingsPage()
        .width('100%')
        .height('100%');
    }
  }

  private handleSceneClick(sceneId: string): void {
    appLogger.info(`handleSceneClick: sceneId=${sceneId}, mode=${this.currentMode}`);

    if (this.currentMode === 'driving') {
      // 驾驶模式：开始播放并显示全屏播放页
      const targetScene: Scene | undefined = SceneRepository.getInstance().getSceneById(sceneId);
      if (targetScene) {
        PlayerController.getInstance().playScene(targetScene).then(() => {
          this.showStudyPage = false;
          this.showPlayerPage = true;
        }).catch((err: Object) => {
          appLogger.error('Play scene failed: ' + JSON.stringify(err));
        });
      }
    } else {
      // 驻车模式：进入学习详情页
      this.selectedSceneId = sceneId;
      this.showPlayerPage = false;
      this.showStudyPage = true;
    }
  }
}
