/**
 * 收藏页
 * 展示用户收藏的所有句子
 */

import { ThemeColors } from '../constants/ThemeConstants';
import { Sentence } from '../model/Sentence';
import { Scene } from '../model/Scene';
import { ProgressStore } from '../service/ProgressStore';
import { SceneRepository } from '../service/SceneRepository';
import { PlayerController } from '../service/PlayerController';
import { SentenceItem } from '../components/SentenceItem';
import appLogger from '../utils/Logger';

interface FavoriteKeyInfo {
  sceneId: string;
  dialogueIndex: number;
  sentenceIndex: number;
}

interface FavoriteSentenceItem {
  key: string;
  sceneTitle: string;
  sceneId: string;
  dialogueIndex: number;
  sentenceIndex: number;
  sentence: Sentence;
}

@Component
export struct FavoritePage {
  @State favoriteSentences: FavoriteSentenceItem[] = [];
  @State isLoading: boolean = true;
  @State showRomaji: boolean = true;
  @State showTranslation: boolean = true;

  aboutToAppear(): void {
    this.loadFavorites();
  }

  private async loadFavorites(): Promise<void> {
    this.isLoading = true;

    try {
      const progressStore = ProgressStore.getInstance();
      const progress = progressStore.getProgress();
      const favoriteKeys = progress.favoriteSentences;

      if (favoriteKeys.length === 0) {
        this.favoriteSentences = [];
        return;
      }

      // 从 SceneRepository 获取所有场景
      const repo = SceneRepository.getInstance();
      const allScenes = repo.getAllScenes();

      const result: FavoriteSentenceItem[] = [];

      for (const key of favoriteKeys) {
        const parsed = this.parseFavoriteKey(key);
        if (!parsed) {
          continue;
        }

        const sceneId = parsed.sceneId;
        const dialogueIndex = parsed.dialogueIndex;
        const sentenceIndex = parsed.sentenceIndex;
        const scene = allScenes.find((s: Scene): boolean => s.id === sceneId);

        if (!scene || !scene.dialogues[dialogueIndex]) {
          continue;
        }

        const dialogue = scene.dialogues[dialogueIndex];
        const sentence = dialogue.sentences[sentenceIndex];

        if (sentence) {
          result.push({
            key: key,
            sceneTitle: scene.titleZh,
            sceneId: sceneId,
            dialogueIndex: dialogueIndex,
            sentenceIndex: sentenceIndex,
            sentence: sentence
          });
        }
      }

      this.favoriteSentences = result;
    } catch (error) {
      appLogger.error('FavoritePage: loadFavorites failed', error);
    } finally {
      this.isLoading = false;
    }
  }

  /**
   * 解析收藏 key
   * 格式：sceneId:dialogueIndex:sentenceIndex
   */
  private parseFavoriteKey(key: string): FavoriteKeyInfo | null {
    const parts = key.split(':');
    if (parts.length !== 3) {
      return null;
    }
    const dialogueIndex = parseInt(parts[1], 10);
    const sentenceIndex = parseInt(parts[2], 10);
    if (isNaN(dialogueIndex) || isNaN(sentenceIndex)) {
      return null;
    }
    return {
      sceneId: parts[0],
      dialogueIndex: dialogueIndex,
      sentenceIndex: sentenceIndex
    };
  }

  private async handleToggleFavorite(item: FavoriteSentenceItem): Promise<void> {
    const progressStore = ProgressStore.getInstance();
    await progressStore.toggleFavorite(item.key);

    // 从列表中移除
    this.favoriteSentences = this.favoriteSentences.filter(
      (fav: FavoriteSentenceItem): boolean => fav.key !== item.key
    );
  }

  private handlePlaySentence(item: FavoriteSentenceItem): void {
    const scene = SceneRepository.getInstance().getSceneById(item.sceneId);
    if (!scene) {
      appLogger.error(`FavoritePage: scene ${item.sceneId} not found`);
      return;
    }
    PlayerController.getInstance().playSentence(scene, item.dialogueIndex, item.sentenceIndex).catch((err: Object) => {
      appLogger.error('FavoritePage: play sentence failed', err);
    });
  }

  build() {
    Column() {
      // 顶部标题
      Text('我的收藏')
        .fontSize(24)
        .fontWeight(700)
        .fontColor(ThemeColors.textPrimary)
        .width('100%')
        .margin({ bottom: 4 });

      Text(`共 ${this.favoriteSentences.length} 句`)
        .fontSize(12)
        .fontColor(ThemeColors.textSecondary)
        .width('100%')
        .margin({ bottom: 16 });

      if (this.isLoading) {
        this.LoadingBuilder();
      } else if (this.favoriteSentences.length === 0) {
        this.EmptyStateBuilder();
      } else {
        // 收藏句子列表
        List() {
          ForEach(this.favoriteSentences, (item: FavoriteSentenceItem, index: number) => {
            ListItem() {
              Column() {
                // 场景来源标签
                Text(item.sceneTitle)
                  .fontSize(11)
                  .fontColor(ThemeColors.primary)
                  .fontWeight(500)
                  .width('100%')
                  .margin({ bottom: 6 });

                SentenceItem({
                  sentence: item.sentence,
                  showRomaji: this.showRomaji,
                  showTranslation: this.showTranslation,
                  isFavorite: true,
                  isPlaying: false,
                  onPlay: () => this.handlePlaySentence(item),
                  onToggleFavorite: () => this.handleToggleFavorite(item)
                });
              }
              .width('100%');
            }
            .margin({ bottom: index < this.favoriteSentences.length - 1 ? 12 : 0 });
          }, (item: FavoriteSentenceItem) => item.key);
        }
        .width('100%')
        .layoutWeight(1);
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(ThemeColors.bgApp)
    .padding(16);
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
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center);
  }

  // ---- 空状态 ----
  @Builder
  EmptyStateBuilder() {
    Column() {
      Text('⭐')
        .fontSize(48);

      Text('还没有收藏的句子')
        .fontSize(14)
        .fontColor(ThemeColors.textTertiary)
        .margin({ top: 12 });

      Text('学习时长按爱心收藏喜欢的句子')
        .fontSize(12)
        .fontColor(ThemeColors.textTertiary)
        .margin({ top: 4 });
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center);
  }
}
