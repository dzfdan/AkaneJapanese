import { UIAbility, Want, AbilityConstant } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { SceneRepository } from '../service/SceneRepository';
import { ProgressStore } from '../service/ProgressStore';
import { SettingsStore } from '../service/SettingsStore';
import { PlayerController } from '../service/PlayerController';
import { ModeManager } from '../service/ModeManager';
import appLogger from '../utils/Logger';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    appLogger.info('EntryAbility onCreate');
    const ctx = this.context;

    // 同步初始化 SceneRepository（传入 context）
    SceneRepository.init(ctx);

    // 初始化 ModeManager（单例，无需 context）
    ModeManager.getInstance();

    // 异步初始化 ProgressStore 和 SettingsStore
    Promise.all([
      ProgressStore.getInstance().init(ctx),
      SettingsStore.getInstance().init(ctx)
    ]).then(() => {
      appLogger.info('All stores initialized');
      // 初始化 PlayerController（包含 AVSession、BackgroundTaskManager、AudioFocusHandler）
      return PlayerController.init(ctx);
    }).then(() => {
      appLogger.info('PlayerController initialized');
      // 加载场景数据
      return SceneRepository.getInstance().loadAll();
    }).then(() => {
      appLogger.info('Scenes loaded');
    }).catch(err => {
      appLogger.error('Init failed: ' + JSON.stringify(err));
    });
  }

  onDestroy(): void {
    appLogger.info('EntryAbility onDestroy');
    PlayerController.getInstance().release().catch(err => {
      appLogger.error('Release player failed: ' + JSON.stringify(err));
    });
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    appLogger.info('EntryAbility onWindowStageCreate');
    windowStage.loadContent('pages/Index', (err, data) => {
      if (err.code) {
        appLogger.error('Failed to load content: ' + JSON.stringify(err));
        return;
      }
    });
  }

  onWindowStageDestroy(): void {
    appLogger.info('EntryAbility onWindowStageDestroy');
  }

  onForeground(): void {
    appLogger.info('EntryAbility onForeground');
  }

  onBackground(): void {
    appLogger.info('EntryAbility onBackground');
  }
}
