# 朱音日语 · 鸿蒙车机 App

> 「通勤路上听日语，驻车碎片时间学日语」

一款面向鸿蒙（HarmonyOS）生态的日语会话学习应用，以**车机场景**为核心差异化卖点，同时覆盖手机与平板设备。

## ✨ 产品特性

### 🚗 双模式设计
- **驾驶模式**（默认）：大按钮 + 音频优先 + 极简操作，符合行车安全规范
- **驻车学习模式**：完整会话文本 + 跟读练习 + 测验，停车时深度学习
- 模式切换时不中断音频播放

### 🎧 音频播放
- 场景会话听力（内置 3 个示例场景，问路/点餐/便利店）
- 0.75x / 1.0x / 1.25x 三档倍速
- 慢速模式（预置慢速音频，切换不丢失进度）
- 单句定位播放
- **后台锁屏播放**（AVSession + 长时任务）
- **音频焦点处理**（导航播报自动压低音量）
- 系统播控中心控制

### 📚 学习功能
- 会话详情：日文 + 罗马音 + 中文翻译
- 跟读练习模式
- 听力小测验
- 句子收藏
- 学习进度统计
- 连续打卡

### 🎨 视觉设计
- **和风朱音**主题：墨黑底 + 朱红点缀 + 衬线日文字体
- 深色模式优先（夜间行车友好）
- 符合华为智能座舱设计规范

### 📱 多端适配
- 车机超宽屏（侧边栏 + 内容区）
- 平板（紧凑侧边栏）
- 手机（底部 TAB 导航）
- 支持 全屏 / 2⁄3 屏 / 1⁄3 屏窗口尺寸

## 🏗️ 技术架构

```
┌─────────────────────────────────────┐
│  Presentation（UI）                 │
│  Pages · Components                 │
├─────────────────────────────────────┤
│  Domain（业务）                     │
│  PlayerController · SceneRepository │
│  ModeManager · ProgressStore        │
│  SettingsStore · AudioFocusHandler  │
├─────────────────────────────────────┤
│  Data（数据）                       │
│  rawfile JSON · m4a 音频            │
│  Preferences · RDB(二期)            │
├─────────────────────────────────────┤
│  Platform（系统封装）               │
│  AVPlayer · AVSession               │
│  BackgroundTask · ThemeManager      │
└─────────────────────────────────────┘
```

## 📦 工程结构

```
AkaneJapanese/
├── AppScope/                      # 应用级配置
│   ├── app.json5
│   └── resources/
├── entry/                         # 主模块
│   ├── src/main/
│   │   ├── ets/
│   │   │   ├── entryability/      # UIAbility 入口
│   │   │   ├── pages/              # 7 个页面
│   │   │   ├── components/         # 10 个可复用组件
│   │   │   ├── model/              # 数据模型
│   │   │   ├── service/            # 业务服务层
│   │   │   ├── platform/           # 系统能力封装
│   │   │   ├── utils/              # 工具函数
│   │   │   └── constants/          # 常量与主题
│   │   ├── resources/
│   │   │   ├── base/element/       # 颜色/字符串资源
│   │   │   └── rawfile/            # 场景包(JSON) + 音频(m4a)
│   │   └── module.json5
│   └── build-profile.json5
├── docs/superpowers/specs/         # 设计文档
├── build-profile.json5
├── oh-package.json5
└── hvigorfile.ts
```

## 🚀 开发环境

| 项目 | 版本 |
|---|---|
| HarmonyOS | 7.0（API 26.0.0） |
| DevEco Studio | 26.0.0 Release |
| 开发语言 | ArkTS |
| UI 框架 | ArkUI（声明式） |
| 工程模型 | Stage |

### 构建步骤

1. 安装 **DevEco Studio 26.0.0** 或更高版本
2. 打开 DevEco Studio，选择 **File → Open**，选择项目根目录
3. 等待依赖同步（oh-package 安装）
4. 连接真机或启动模拟器
5. 点击 **Run** 按钮运行

> **注意**：音频文件（rawfile/audio/ 下的 .m4a）目前是占位空文件，开发阶段不会有声音。上线前需要替换为真实的日语录音。

## 📋 模块清单

### 页面（7 个）
| 页面 | 路径 | 说明 |
|---|---|---|
| Index | pages/Index | 主容器，导航与布局管理 |
| SceneListPage | pages/SceneListPage | 场景列表页（双模式） |
| PlayerPage | pages/PlayerPage | 驾驶模式全屏播放页 |
| StudyPage | pages/StudyPage | 驻车学习详情页 |
| ProgressPage | pages/ProgressPage | 学习进度统计页 |
| FavoritePage | pages/FavoritePage | 收藏句子页 |
| SettingsPage | pages/SettingsPage | 设置页 |

### 组件（10 个）
| 组件 | 说明 |
|---|---|
| SideNav | 侧边栏导航（宽屏） |
| BottomTab | 底部 TAB 导航（窄屏） |
| SceneCard | 场景卡片 |
| PlayerBar | 底部播放条（完整模式） |
| MiniPlayer | 迷你播放条（窄屏） |
| SentenceItem | 句子条目 |
| ModeSwitcher | 模式切换器（含确认） |
| QuizCard | 测验题卡片 |
| SettingItemSwitch | 开关设置行 |
| SettingItemSelect | 选择设置行 |

### 服务（5 个）
| 服务 | 说明 |
|---|---|
| SceneRepository | 场景数据仓库（rawfile JSON） |
| PlayerController | 播放控制器（核心） |
| ModeManager | 双模式切换管理 |
| ProgressStore | 学习进度存储（Preferences） |
| SettingsStore | 设置存储（Preferences） |
| AudioFocusHandler | 音频焦点处理 |

### 平台封装（4 个）
| 模块 | 说明 |
|---|---|
| AVPlayerWrapper | AVPlayer 封装 |
| AVSessionManager | 媒体会话（后台播放必须） |
| BackgroundTaskManager | 长时任务管理 |
| ThemeManager | 主题管理 |

## 🗺️ 路线图

### ✅ MVP（已完成设计与代码骨架）
- 场景会话听力（3 个示例场景）
- 双模式切换（驾驶/驻车）
- 倍速播放（0.75x / 1.0x / 1.25x）
- 单句定位 + 慢速跟读
- 后台锁屏播放
- 音频焦点处理
- 学习进度与打卡
- 句子收藏
- 听力测验
- 响应式适配（车机/平板/手机）

### 📅 二期规划
- 五十音入门模块
- JLPT 分级词汇（N5~N2）
- 账号 + 云同步
- 语音评分（跟读准确度）
- 错题本 + 间隔复习
- 在线内容包下载
- Car Kit 手机-车机流转
- 鸿蒙座舱原生适配（待生态开放）

## 📄 设计文档

完整设计文档见：[`docs/superpowers/specs/2026-09-17-akane-japanese-car-app-design.md`](docs/superpowers/specs/2026-09-17-akane-japanese-car-app-design.md)

包含：产品概述、技术选型、架构设计、界面交互、数据结构、工程结构、多端适配、错误处理、测试计划、里程碑与上线计划、风险应对。

## ⚠️ 注意事项

1. **音频占位**：`resources/rawfile/audio/` 下的 .m4a 文件是空文件，仅作开发占位。实际使用需要替换为真实日语录音。
2. **车机分发**：截至 2026 年 9 月，华为应用市场（AGC）的 HarmonyOS 应用分发暂不包含「车机」设备类型。鸿蒙 NEXT 座舱预计 2026 年 12 月商用，届时可申请上车。当前可先以手机/平板身份上架。
3. **日语 TTS**：HarmonyOS 系统 TTS 不支持日语，因此日语发音完全依赖预置录音。
4. **行车检测**：车速/挡位 API 不对第三方开发者开放，因此采用「默认驾驶模式 + 用户主动解锁驻车模式」的安全默认设计。

## 📄 许可证

本项目为学习与产品原型用途。
