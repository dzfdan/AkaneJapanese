# 朱音日语 · 鸿蒙车机 App 设计文档

> 设计文档版本：v1.0  
> 日期：2026-09-17  
> 产品代号：朱音（Akane）

---

## 一、产品概述

### 1.1 产品定位

**朱音日语**是一款面向鸿蒙（HarmonyOS）生态的日语会话学习应用，以**车机场景**为核心差异化卖点，同时覆盖手机与平板设备。

产品核心主张：**「通勤路上听日语，驻车碎片时间学日语」**——利用驾驶场景的听觉时间和驻车场景的视觉时间，打造完整的车内日语学习体验。

### 1.2 目标用户

- **日语学习者（N4 水平起步）**：认识假名和基本句型，希望通过真实场景会话提升听力和口语
- **有车通勤族**：每日通勤 30 分钟以上，希望把路上时间利用起来
- **鸿蒙生态用户**：使用华为/鸿蒙座舱车型或鸿蒙手机的用户

MVP 内容难度定位为 **N4 基础**，后续版本扩展到 N5~N2 全等级。

### 1.3 双模式设计（核心差异化）

| 模式 | 触发方式 | 核心体验 | 符合规范 |
|---|---|---|---|
| **驾驶模式**（默认） | 应用启动默认进入，安全默认设计 | 大按钮 + 音频优先 + 极简操作 + 语音辅助 | 华为车机应用行车安全要求：行驶中无视频、无弹窗、无付费 |
| **驻车学习模式** | 用户主动点击切换（二次确认防误触） | 完整会话文本 + 跟读练习 + 测验 + 进度统计 | 驻车状态无安全限制，接近平板学习 App 体验 |

> **技术说明**：HarmonyOS 第三方应用无法获取车速/挡位 API（车辆数据能力仅限车厂授权伙伴），因此采用「默认驾驶模式 + 用户主动解锁驻车模式」的安全默认设计，与华为《智能座舱设计指南》「驾驶员与乘员、驾驶态与驻车态」的设计理念一致。

### 1.4 MVP 功能范围

- ✅ 场景会话听力（12 个生活场景，每场景 3~5 组对话）
- ✅ 双模式切换（驾驶音频模式 / 驻车学习模式）
- ✅ 倍速播放（0.75x / 1.0x / 1.25x）
- ✅ 单句定位播放 + 慢速跟读
- ✅ 后台锁屏播放（AVSession + 长时任务）
- ✅ 音频焦点处理（导航播报自动压低音量）
- ✅ 学习进度与打卡统计（本地持久化）
- ✅ 句子收藏
- ✅ 听力小测验
- ✅ 响应式适配（车机超宽屏 / 平板 / 手机）

**不在 MVP 范围内**（二期）：
- ❌ 五十音入门模块
- ❌ JLPT 分级词汇模块
- ❌ 云同步与账号系统
- ❌ 语音评分（跟读准确度）
- ❌ 在线内容包下载
- ❌ 错题本 + 间隔复习系统

---

## 二、技术选型

### 2.1 开发平台

| 项目 | 选型 | 说明 |
|---|---|---|
| 操作系统 | HarmonyOS 7（API 26.0.0） | 2026-08-28 Release，新项目推荐版本 |
| 开发语言 | ArkTS | 鸿蒙原生开发语言 |
| UI 框架 | ArkUI（声明式） | 鸿蒙原生 UI 框架 |
| 工程模型 | Stage 模型 | 当前标准模型 |
| IDE | DevEco Studio 26.0.0 Release | 2026-08-28 发布 |
| compileSdk | 26.0.0 | 编译 SDK 版本 |
| compatibleSdk | 26.0.0 | MVP 阶段目标最新设备；如需覆盖更多存量设备可下调至 5.0.0(12) |

### 2.2 关键 API 与 Kit

| 能力 | Kit / API | 说明 |
|---|---|---|
| 音频播放 | `@kit.MediaKit` → AVPlayer | 播放本地 m4a 音频（rawfile fdSrc 方式） |
| 媒体会话 | `@kit.AVSessionKit` | 后台播放必须项，支持系统播控中心 |
| 后台长时任务 | `@kit.BackgroundTasksKit` | AUDIO_PLAYBACK 模式，锁屏续播 |
| 音频焦点 | AVPlayer `on('audioInterrupt')` | 导航播报 DUCK 处理 |
| 持久化（KV） | `@kit.ArkData` → Preferences | 设置与学习进度 |
| 持久化（关系型） | `@kit.ArkData` → RDB | 二期错题本/收藏/学习明细 |
| 响应式布局 | GridRow / GridCol + mediaquery | 一多框架，多设备适配 |
| 主题系统 | ArkUI 主题 + 自定义 Theme | 和风朱音深色主题 |

### 2.3 音频方案说明

- **播放格式**：m4a（AAC），体积小、音质好、官方完全支持
- **慢速方案**：AVPlayer `setSpeed()` 支持 0.75x 但不支持 0.5x，因此 MVP 提供 0.75x / 1.0x / 1.25x 三档。如产品需要 0.5x，方案是离线预生成慢速音频随包发布（避免引入 AudioRenderer + 自解码的复杂度）
- **日语发音**：系统 TTS（Core Speech Kit）仅支持中英文，不支持日语。日语发音完全依赖**预置真人录音音频**，与场景包方案一致
- **音频焦点**：导航播报时 Music 流默认 DUCK（降至 20% 音量），播报结束自动恢复，应用无需暂停

### 2.4 分发现状与策略

**现状**（截至 2026-09-17）：
- AGC（华为应用市场）HarmonyOS 应用分发目前支持设备类型：手机、平板、PC/2in1、智慧屏、手表 —— **不含车机**
- 鸿蒙 NEXT 座舱 OS 计划 2026 年 12 月随新问界 M9 商用，生态开放时间待定
- 旧「华为车机应用市场」仅接受 Android APK，不适用于 ArkTS 技术栈

**上线策略**：
1. **MVP 阶段**：以「手机 + 平板」身份上架 AGC，产品形态按车机规范设计（驾驶模式 + 驻车模式 + 超宽屏适配），手机连车载蓝牙时驾驶模式同样成立
2. **跟进阶段**：持续关注鸿蒙座舱生态开放动态，可主动联系 `huaweihicar@huawei.com` 或华为开发者联盟在线提单申请座舱伙伴合作
3. **上车阶段**：座舱生态开放后，同一套代码最小改动适配车机设备类型并上架

---

## 三、架构设计

### 3.1 分层架构

```
┌─────────────────────────────────────────────────────┐
│  Presentation 层（UI）                               │
│  页面：SceneList / PlayerPage / StudyPage / ...     │
│  组件：SceneCard / PlayerBar / SentenceItem / ...   │
│  状态：@State / @Link / 组件级状态管理              │
└───────────────────┬─────────────────────────────────┘
                    │
┌───────────────────▼─────────────────────────────────┐
│  Domain 层（业务状态）                               │
│  PlayerController · SceneRepository                 │
│  ModeManager · ProgressStore · SettingsStore        │
│  （纯业务逻辑，不依赖 UI 框架）                     │
└───────────────────┬─────────────────────────────────┘
                    │
┌───────────────────▼─────────────────────────────────┐
│  Data 层（内容与持久化）                             │
│  ScenePackage(JSON rawfile) · AudioAsset(m4a)       │
│  Preferences(进度/设置) · RDB(学习记录，二期)       │
└───────────────────┬─────────────────────────────────┘
                    │
┌───────────────────▼─────────────────────────────────┐
│  Platform 层（系统能力封装）                         │
│  AVPlayerWrapper · AVSessionManager                 │
│  AudioFocusHandler · BackgroundTaskManager          │
│  ThemeManager · WindowAdapter                       │
└─────────────────────────────────────────────────────┘
```

依赖方向自上而下，下层不感知上层。Platform 层隔离系统 API，便于未来替换或单元测试 Mock。

### 3.2 核心模块

#### PlayerController（播放控制器）
- 管理 AVPlayer 生命周期（idle → initialized → prepared → playing ↔ paused → released）
- 封装倍速切换、单句定位、播放/暂停/上一首/下一首
- 维护当前场景、当前对话、当前句子索引
- 对外暴露状态流（播放状态、当前进度、当前句子）

#### ModeManager（模式管理器）
- 管理「驾驶模式 / 驻车学习模式」状态
- 持久化用户偏好（Preferences）
- 切换模式时不中断音频播放
- 提供模式切换二次确认逻辑

#### SceneRepository（场景仓库）
- 从 rawfile 加载场景 JSON 并解析为领域模型
- 管理场景列表、场景详情、对话、句子
- 提供按分类、难度筛选
- 单例缓存，避免重复 IO

#### ProgressStore（进度存储）
- 记录已完成场景、每场景进度、累计学习时长、连续打卡天数
- 基于 Preferences KV 存储
- 提供打卡逻辑（跨天判断、连续天数计算）

#### AudioFocusHandler（音频焦点处理）
- 监听 AVPlayer `audioInterrupt` 事件
- 按 InterruptEvent 类型处理：DUCK/UNDUCK 只更新 UI、PAUSE 同步状态、STOP 彻底停止
- 封装焦点策略，业务层不感知底层细节

---

## 四、界面与交互设计

### 4.1 视觉风格：和风朱音

| 设计元素 | 规范 |
|---|---|
| 主色调 | 朱红 `#D4553A`（品牌色，用于按钮、高亮、进度条） |
| 底色 | 墨黑 `#0E0B08`（驾驶模式默认深色，夜间行车不刺眼） |
| 卡片色 | 深棕 `#1A1510` / `#2A231C`（两级卡片层次） |
| 正文文字 | 米白 `#F5E6D8`（深色对比度 ≥ 10:1） |
| 次要文字 | 暖灰 `#A89880` / `#8A7A66` |
| 日文字体 | 衬线字体（Noto Serif JP 风格），强化文化气质 |
| UI 字体 | 系统无衬线字体（HarmonyOS Sans） |
| 卡片圆角 | 16vp（符合车机卡片规范） |
| 触控热区 | 核心按钮 ≥ 15.4mm（≈ 56vp 常见密度下），必须 ≥ 10.7mm |

> 驻车学习模式可选浅色版本，驾驶模式强制深色。MVP 先统一深色，二期增加浅色主题。

### 4.2 页面导航结构

```
侧边栏导航（车机/平板，>600vp）      底部 TAB（手机，<600vp）
├── 会话（场景列表页）              ├── 会话
├── 进度                           ├── 进度
├── 收藏                           ├── 收藏
└── 设置                           └── 设置
```

应用主容器（Index.ets）根据窗口宽度自动切换导航位置。

### 4.3 驾驶模式页面

**场景列表页（驾驶模式）**：
- 4 列大卡片网格（车机宽屏），2 列（手机）
- 每张卡片：日文标题 + 中文翻译 + 进度条 + 状态标签
- 底部常驻播放条：当前句子日文 + 上一首/播放/下一首大按钮 + 进度/时长
- 右上角：难度切换 + 「切换驻车模式」按钮（二次确认）
- 核心按钮**居左**（符合主驾易操作规范）

**播放页（驾驶模式）**：
- 居中大字号日文句子
- 罗马音（可设置开关）
- 中文翻译（小字号，可选显示）
- 超大播放控制区（播放/暂停、上一句/下一句）
- 倍速切换（0.75x / 1x / 1.25x）
- 进度条 + 时间显示

### 4.4 驻车学习模式页面

**场景列表页（驻车模式）**：
- 同驾驶模式但卡片信息更丰富（对话数量、难度、已学百分比）
- 支持按分类/难度筛选

**会话详情页**：
- 左右分栏（>840vp）：左侧会话列表 / 右侧对话详情
- 窄屏（<840vp）：上下结构，列表可折叠
- 每句对话：说话人角色 + 日文 + 罗马音 + 中文翻译 + 单句播放 + 收藏
- 顶部：倍速选择 + 「开始跟读」按钮
- Tab 切换：对话 / 跟读练习 / 测验

**跟读练习模式**：
- 单句放大显示
- 「播放原音」「慢速播放」「录音跟读」三个大按钮
- 句子自动依次推进（MVP 不做语音评分，仅提供练习流程）

**听力测验**：
- 播放句子音频，四选一选择含义/假名读音
- 答完显示正确答案与解析
- 完成后显示得分

### 4.5 设计规范遵循（华为智能座舱设计指南）

| 规范项 | 要求 | 本方案实现 |
|---|---|---|
| 触控热区 | 推荐 ≥ 15.4mm，必须 ≥ 10.7mm（以物理尺寸为准） | 核心播放按钮设计目标 48~56vp（按车机屏幕密度折算约 12~16mm），卡片可点击区域 ≥ 80vp |
| 主驾易操作 | 高频按钮居左 | 底部播放条按钮居左排列 |
| 关键信息布局 | 靠近左上角 | 场景标题、当前句子均靠左上 |
| 文字大小 | 最小 ≥ 9fp，正文 ≥ 15fp | 正文 16fp，标题 24~32fp |
| 对比度 | 深色背景 10:1~17:1 | 米白 #F5E6D8 / 墨黑 #0E0B08 约 12:1 |
| 窗口尺寸 | 支持全屏/2⁄3/1⁄3 | GridCol 响应式 + 断点适配 |
| 架构 | 侧边栏 + 内容区（推荐） | 宽屏侧边栏，窄屏底部 TAB |
| 深浅色模式 | 必须项 | 深色已设计，浅色二期 |
| 行车安全 | 行驶中无视频/无弹窗/无付费 | 默认驾驶模式，无视频，无行车中弹窗 |

---

## 五、数据结构

### 5.1 场景包文件结构

```
resources/rawfile/
├── scenes/
│   ├── index.json          # 场景总索引
│   ├── scene-001.json      # 问路
│   ├── scene-002.json      # 餐厅点餐
│   ├── scene-003.json      # 便利店
│   └── ...
└── audio/
    ├── scene-001-normal.m4a   # 正常速完整音频
    ├── scene-001-slow.m4a     # 慢速完整音频
    ├── scene-002-normal.m4a
    ├── scene-002-slow.m4a
    └── ...
```

### 5.2 场景总索引（index.json）

```json
{
  "version": "1.0.0",
  "scenes": [
    {
      "id": "scene-001",
      "titleJa": "道を尋ねる",
      "titleZh": "问路",
      "level": "N4",
      "category": "travel",
      "dialogueCount": 3,
      "durationSec": 490,
      "file": "scenes/scene-001.json"
    }
  ]
}
```

### 5.3 单场景 JSON

```json
{
  "id": "scene-001",
  "titleJa": "道を尋ねる",
  "titleZh": "问路",
  "level": "N4",
  "category": "travel",
  "descriptionZh": "在日本街头向当地人问路的常用表达",
  "audioNormal": "audio/scene-001-normal.m4a",
  "audioSlow": "audio/scene-001-slow.m4a",
  "dialogues": [
    {
      "id": "d1",
      "titleJa": "駅への道",
      "titleZh": "去车站的路",
      "sentences": [
        {
          "id": "s1",
          "speaker": "A",
          "speakerRoleJa": "旅人",
          "speakerRoleZh": "旅客",
          "japanese": "すみません、駅はどこですか？",
          "romaji": "sumimasen, eki wa doko desu ka?",
          "translation": "不好意思，请问车站在哪里？",
          "startTime": 0.0,
          "endTime": 2.8,
          "slowStartTime": 0.0,
          "slowEndTime": 3.7
        },
        {
          "id": "s2",
          "speaker": "B",
          "speakerRoleJa": "地元の人",
          "speakerRoleZh": "当地人",
          "japanese": "あの交差点を右に曲がると、すぐ左にあります。",
          "romaji": "ano kousaten o migi ni magaru to, sugu hidari ni arimasu.",
          "translation": "在那个路口右转，马上就在左边。",
          "startTime": 3.0,
          "endTime": 7.2,
          "slowStartTime": 4.0,
          "slowEndTime": 9.5
        }
      ],
      "quiz": [
        {
          "id": "q1",
          "type": "listening",
          "questionZh": "「駅」的正确读音是？",
          "options": ["えき", "いえ", "えが", "えきょう"],
          "correctIndex": 0,
          "explanationZh": "駅（えき）：车站。注意与 家（いえ）区分。"
        }
      ]
    }
  ]
}
```

### 5.4 领域模型（ArkTS 接口）

```typescript
// Scene.ets
export interface Scene {
  id: string;
  titleJa: string;
  titleZh: string;
  level: string;          // N5 / N4 / N3 / N2 / N1
  category: string;       // travel / food / shopping / daily / ...
  descriptionZh: string;
  audioNormal: string;
  audioSlow: string;
  dialogues: Dialogue[];
}

// Dialogue.ets
export interface Dialogue {
  id: string;
  titleJa: string;
  titleZh: string;
  sentences: Sentence[];
  quiz: QuizItem[];
}

// Sentence.ets
export interface Sentence {
  id: string;
  speaker: string;        // "A" / "B" / "C"
  speakerRoleJa: string;
  speakerRoleZh: string;
  japanese: string;
  romaji: string;
  translation: string;
  startTime: number;      // seconds, normal speed audio
  endTime: number;
  slowStartTime: number;  // seconds, slow speed audio
  slowEndTime: number;
}

// QuizItem.ets
export interface QuizItem {
  id: string;
  type: 'listening' | 'reading' | 'meaning';
  questionZh: string;
  options: string[];
  correctIndex: number;
  explanationZh: string;
}
```

### 5.5 学习进度数据（Preferences）

```typescript
interface UserProgress {
  completedScenes: string[];          // 已完成场景 ID 列表
  sceneProgress: Record<string, number>; // 场景ID → 进度百分比 0~100
  totalStudyMinutes: number;          // 累计学习时长（分钟）
  streakDays: number;                 // 连续打卡天数
  lastStudyDate: string;              // 上次学习日期 YYYY-MM-DD
  favoriteSentences: string[];        // 收藏句子ID列表 "sceneId:dialogueId:sentenceId"
}

interface UserSettings {
  defaultMode: 'driving' | 'parked';  // 默认模式
  defaultSpeed: number;               // 默认倍速 0.75 / 1.0 / 1.25
  showRomaji: boolean;                // 显示罗马音
  showTranslation: boolean;           // 显示中文翻译
  theme: 'dark' | 'light' | 'system'; // 主题
}
```

---

## 六、工程结构

```
AkaneJapanese/
├── AppScope/
│   └── app.json5                     # 应用级配置
├── entry/
│   ├── src/main/
│   │   ├── ets/
│   │   │   ├── entryability/
│   │   │   │   └── EntryAbility.ets  # UIAbility 入口
│   │   │   ├── pages/
│   │   │   │   ├── Index.ets         # 主容器（导航+内容区）
│   │   │   │   ├── SceneListPage.ets # 场景列表页
│   │   │   │   ├── PlayerPage.ets    # 驾驶模式播放页
│   │   │   │   ├── StudyPage.ets     # 驻车学习详情页
│   │   │   │   ├── ProgressPage.ets  # 学习进度页
│   │   │   │   ├── FavoritePage.ets  # 收藏页
│   │   │   │   └── SettingsPage.ets  # 设置页
│   │   │   ├── components/
│   │   │   │   ├── SceneCard.ets
│   │   │   │   ├── PlayerBar.ets
│   │   │   │   ├── MiniPlayer.ets
│   │   │   │   ├── SentenceItem.ets
│   │   │   │   ├── SideNav.ets
│   │   │   │   ├── BottomTab.ets
│   │   │   │   ├── ModeSwitcher.ets
│   │   │   │   └── QuizCard.ets
│   │   │   ├── model/
│   │   │   │   ├── Scene.ets
│   │   │   │   ├── Dialogue.ets
│   │   │   │   ├── Sentence.ets
│   │   │   │   └── QuizItem.ets
│   │   │   ├── service/
│   │   │   │   ├── PlayerController.ets
│   │   │   │   ├── SceneRepository.ets
│   │   │   │   ├── ModeManager.ets
│   │   │   │   ├── ProgressStore.ets
│   │   │   │   ├── SettingsStore.ets
│   │   │   │   └── AudioFocusHandler.ets
│   │   │   ├── platform/
│   │   │   │   ├── AVPlayerWrapper.ets
│   │   │   │   ├── AVSessionManager.ets
│   │   │   │   ├── BackgroundTaskManager.ets
│   │   │   │   └── ThemeManager.ets
│   │   │   ├── utils/
│   │   │   │   ├── TimeUtil.ets
│   │   │   │   ├── DateUtil.ets
│   │   │   │   └── Logger.ets
│   │   │   └── constants/
│   │   │       ├── AppConstants.ets
│   │   │       └── ThemeConstants.ets
│   │   ├── resources/
│   │   │   ├── base/
│   │   │   │   ├── element/string.json
│   │   │   │   └── media/           # 图标/图片
│   │   │   ├── rawfile/             # 场景包 + 音频
│   │   │   └── dark/                # 深色模式资源
│   │   └── module.json5             # 模块配置 + 权限
│   └── build-profile.json5
└── oh-package.json5
```

### 关键配置（module.json5）

```json
{
  "module": {
    "name": "entry",
    "type": "entry",
    "description": "$string:module_desc",
    "mainElement": "EntryAbility",
    "deviceTypes": ["default", "tablet", "car"],
    "deliveryWithInstall": true,
    "installationFree": false,
    "pages": "$profile:main_pages",
    "abilities": [
      {
        "name": "EntryAbility",
        "srcEntry": "./ets/entryability/EntryAbility.ets",
        "description": "$string:EntryAbility_desc",
        "icon": "$media:icon",
        "label": "$string:EntryAbility_label",
        "startWindowIcon": "$media:icon",
        "startWindowBackground": "$color:start_window_background",
        "backgroundModes": ["audioPlayback"],
        "exported": true,
        "skills": [
          {
            "entities": ["entity.system.home"],
            "actions": ["action.system.home"]
          }
        ]
      }
    ],
    "requestPermissions": [
      {
        "name": "ohos.permission.KEEP_BACKGROUND_RUNNING",
        "reason": "$string:bg_running_reason",
        "usedScene": {
          "abilities": ["EntryAbility"],
          "when": "inuse"
        }
      },
      {
        "name": "ohos.permission.INTERNET",
        "reason": "$string:internet_reason"
      }
    ]
  }
}
```

> 注：`deviceTypes` 包含 `car`，但 AGC 发布时需确认车机设备类型是否已开放。如未开放可先移除 `car`，仅保留 `default`（手机/平板）。

---

## 七、多端适配方案

### 7.1 断点策略

| 断点 | 宽度范围 (vp) | 对应设备 | 布局形态 |
|---|---|---|---|
| sm | [320, 600) | 手机竖屏 | 底部 TAB + 单列卡片 + 详情单列 |
| md | [600, 840) | 平板 / 手机横屏 / 车机 1⁄3 屏 | 侧边栏(图标+文字) + 2~3列卡片 + 左右分栏详情 |
| lg | [840, +∞) | 车机超宽屏 / 平板横屏 | 侧边栏 + 4列卡片 + 左列表右详情 |

使用 `GridRow` + `GridCol` + `breakpoints` 配置实现响应式栅格。

### 7.2 导航适配

- **lg / md**：左侧侧边栏导航（图标 + 文字）
- **sm**：底部 TAB 导航（图标 + 文字）
- 极端窄窗口（<400vp）：侧边栏仅图标，底部 TAB 文字缩小

### 7.3 内容层适配

组件按断点自动调整：
- **SceneCard**：lg 横版大卡 / md 标准版 / sm 紧凑版
- **PlayerBar**：lg 完整信息 + 三按钮 / sm 迷你版（仅播放键+标题）
- **StudyPage**：lg/md 左右分栏 / sm 上下结构（列表可折叠）

---

## 八、错误处理

### 8.1 音频播放异常

| 异常场景 | 处理方式 | 用户感知 |
|---|---|---|
| rawfile 音频加载失败 | try-catch 捕获，toast 提示，回退到场景列表 | 「音频加载失败」提示 |
| 播放中出错（error 回调） | 记录日志，尝试 reset + 重新 prepare | 自动重试 1 次，失败则提示 |
| 导航播报打断 | 监听 audioInterrupt，DUCK 只降音量不停 | 音量轻微降低，播报完恢复 |
| 电话/语音打断 | INTERRUPT_FORCE + PAUSE，系统强制暂停，同步 UI 状态 | 播放暂停，UI 显示暂停态 |
| 长时任务被回收 | 恢复播放时重新申请 startBackgroundRunning | 无感恢复 |
| 耳机拔出 | 系统行为（自动暂停），同步 UI 状态 | 播放暂停 |

### 8.2 内容数据异常

| 异常场景 | 处理方式 |
|---|---|
| 场景 JSON 解析失败 | 跳过该场景，记录日志，场景列表不展示损坏项 |
| 场景总索引损坏 | 展示空状态 + 「内容加载失败」提示 |
| 句子时间戳越界 | clamp 到音频时长，避免 seek 越界 |
| Preferences 写入失败 | 降级到内存缓存，下次启动重试写入 |

### 8.3 行车安全兜底

1. **默认驾驶模式**：首次启动永远进入驾驶模式（安全默认设计）
2. **驻车模式二次确认**：切换到驻车模式需弹确认框（「确认切换到驻车学习模式？请勿在行驶中操作」）
3. **无视频内容**：全应用无视频播放，从根本上符合行车安全规范
4. **无弹窗干扰**：行车中不自启动、不弹通知、不弹付费
5. **大按钮设计**：核心操作按钮热区 ≥ 56vp（≈16mm），降低误触

---

## 九、测试计划

### 9.1 测试分层

| 测试类型 | 覆盖范围 | 工具/框架 |
|---|---|---|
| 单元测试 | SceneRepository JSON 解析、PlayerController 状态机、ModeManager 逻辑、ProgressStore 读写、工具函数 | arkUnit |
| 组件测试 | SceneCard 各状态、PlayerBar 播放控制、SentenceItem 展开/收藏、SideNav 激活态 | @ohos.test 组件测试 |
| 集成测试 | 完整学习流程（列表→详情→播放→跟读→测验）、模式切换、断点切换 | DevEco Studio 自动化测试 |
| 专项测试 | 音频焦点（导航打断）、后台长时间播放、内存泄漏、性能分析 | DevEco Profiler |

### 9.2 关键测试用例

**音频播放**：
- [ ] 正常播放/暂停/上一首/下一首
- [ ] 倍速切换（0.75x / 1.0x / 1.25x）
- [ ] 单句定位播放（seek 精度）
- [ ] 慢速音频切换
- [ ] 后台播放不中断
- [ ] 导航播报 DUCK 处理
- [ ] 电话打断自动暂停

**双模式**：
- [ ] 首次启动进入驾驶模式
- [ ] 切换驻车模式二次确认
- [ ] 模式切换不中断音频
- [ ] 模式偏好持久化

**多端适配**：
- [ ] 超宽屏（lg）布局正确
- [ ] 平板（md）布局正确
- [ ] 手机（sm）布局正确
- [ ] 1⁄3 屏窄窗口布局不溢出
- [ ] 窗口尺寸实时调整无错位

**数据持久化**：
- [ ] 学习进度正确保存与恢复
- [ ] 连续打卡计算（跨天/跨多天未学）
- [ ] 收藏句子持久化

---

## 十、里程碑与上线计划

### 10.1 MVP 开发里程碑（4 迭代，6~8 周）

| 迭代 | 周期 | 目标 | 交付内容 |
|---|---|---|---|
| **一** | W1~W2 | 工程脚手架 + 基础播放 | DevEco 工程、和风主题系统、侧边栏布局、场景列表页、JSON 解析、AVPlayer 基础播放（正常速） |
| **二** | W3~W4 | 双模式 + 驻车学习 | ModeManager、会话详情页（左右分栏）、倍速切换、单句定位、慢速音频、句子收藏 |
| **三** | W5~W6 | 后台播放 + 学习进度 | AVSession 接入、后台长时任务、音频焦点处理、Preferences 进度、打卡统计、跟读练习模式 |
| **四** | W7~W8 | 多端适配 + 测验 + 上架 | 响应式断点适配（车机/平板/手机）、听力测验、设置页、测试、性能优化、打包上架 AGC |

### 10.2 上架计划

**第一阶段：手机/平板上架（MVP 完成后立即执行）**
- 注册华为开发者联盟 + 实名认证
- 软件著作权申请（或电子版权认证）
- APP 备案（工信部要求）
- AGC 创建应用（设备类型：手机 + 平板）
- 上传 APP 包（HarmonyOS 应用包格式） + 完善应用信息
- 提交审核

**第二阶段：车机端跟进（持续关注）**
- 关注鸿蒙 NEXT 座舱生态开放动态
- 主动联系华为了解座舱伙伴通道（huaweihicar@huawei.com / 开发者联盟提单）
- 座舱生态开放后，第一时间申请准入并适配车机设备类型
- 同一套代码最小改动上车

### 10.3 二期路线图

| 优先级 | 功能模块 | 说明 |
|---|---|---|
| P1 | 五十音入门模块 | 零基础用户入口，扩大用户群 |
| P1 | JLPT 分级词汇 | N5~N2 词卡，间隔复习 |
| P1 | 账号 + 云同步 | 手机/车机进度互通 |
| P2 | 语音评分 | 跟读准确度评估（需第三方语音 SDK） |
| P2 | 错题本 | 测验错题收集 + 针对性复习 |
| P2 | 在线内容包 | 后端内容池，可远程更新下载 |
| P3 | Car Kit 流转 | 手机碰一碰车机，学习进度流转 |

---

## 十一、风险与应对

| 风险 | 影响 | 概率 | 应对措施 |
|---|---|---|---|
| 鸿蒙座舱车机分发开放延迟 | 车机端无法按计划上架 | 中 | MVP 先上手机/平板，保持代码对车机兼容，随时可上车 |
| 日语真人录音制作成本高 | 内容数量受限 | 高 | MVP 控制在 12 场景以内，先验证产品方向再扩内容；可用高质量 TTS 预生成过渡 |
| 音频后台播放稳定性 | 影响核心体验 | 中 | 严格按官方文档接入 AVSession + 长时任务，充分测试各种打断场景 |
| 车机审核行车安全不通过 | 上架被拒 | 中 | 严格遵守华为 4 条行车安全要求，默认驾驶模式设计，审核前自查清单 |
| 教育类应用资质要求高 | 上架需要额外资质 | 低 | 提前向华为审核团队确认日语学习类所需资质，MVP 阶段避免在线课程/付费培训表述 |
| 超宽屏适配工作量超预期 | 开发延期 | 低 | 采用 GridRow 栅格系统，组件级响应式，尽早在模拟器验证多种分辨率 |

---

## 附录：参考资料

1. [HarmonyOS 开发套件版本总览 - 华为开发者](https://developer.huawei.com/consumer/cn/doc/harmonyos-releases/overview-allversion)
2. [使用 AVPlayer 播放音频 - Media Kit 开发指导](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/using-avplayer-for-playback)
3. [长时任务 - Background Tasks Kit](https://developer.huawei.com/consumer/cn/doc/HarmonyOS-Guides/continuous-task)
4. [音频焦点介绍 - Audio Kit](https://device.harmonyos.com/cn/docs/apiref/harmonyos-guides/audio-playback-concurrency)
5. [智能座舱设计指南 - 华为开发者](https://developer.huawei.com/consumer/cn/doc/design-guides/smart-cockpit-basic-experience-0000002592646356)
6. [车机应用业务介绍 - 华为开发者](https://developer.huawei.com/consumer/cn/doc/distribution/app/ins-0000001064954596)
7. [文本转语音 - Core Speech Kit（确认不支持日语）](https://device.harmonyos.com/cn/docs/apiref/harmonyos-guides/texttospeech-guide)
8. [HarmonyOS 一次开发，多端部署概览](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/introduction)
