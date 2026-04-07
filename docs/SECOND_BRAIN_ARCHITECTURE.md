# MemoryPal 第二大脑架构

## 架构概述

基于Claudecode架构设计，实现真正的"终身陪伴型AI第二大脑"。

```
┌─────────────────────────────────────────────────────────────┐
│  第三层：主动认知层（大脑）                                     │
│  ┌─────────────────┬─────────────────┬─────────────────┐   │
│  │ 画像进化引擎     │ 主动对话引擎     │ 需求预测引擎     │   │
│  │ ProfileEvolution│ ProactiveDialogue│ NeedPrediction  │   │
│  │ Engine          │ Engine           │ Engine          │   │
│  └─────────────────┴─────────────────┴─────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│  第二层：长期记忆层（知识）                                     │
│  ┌─────────────────┬─────────────────┬─────────────────┐   │
│  │ 对话历史分析     │ 行为模式学习     │ 画像自动进化     │   │
│  │ Conversation    │ Behavior         │ Profile         │   │
│  │ Analysis        │ Learning         │ Evolution       │   │
│  └─────────────────┴─────────────────┴─────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│  第一层：工具执行层（手脚）← 已实现                            │
│  ┌─────────────────┬─────────────────┬─────────────────┐   │
│  │ 创建待办/提醒    │ 搜索记忆         │ 播放录音         │   │
│  │ 更新画像         │ 导入通话录音     │ ...             │   │
│  └─────────────────┴─────────────────┴─────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

## 核心组件

### 1. SecondBrainOrchestrator（中央协调器）
- **职责**：协调三层架构的交互，类似Claudecode的QueryEngine
- **功能**：
  - 管理对话状态机
  - 决策何时主动/被动响应
  - 维护记忆流动（感知→短期→长期）
  - 广播消息流给UI

### 2. ProfileEvolutionEngine（画像进化引擎）
- **职责**：长期学习用户，自动更新画像
- **核心功能**：
  - 从对话中提取画像更新
  - 自动分析行为模式
  - 识别情绪状态变化
  - 学习目标完成进度
  - 发现新兴趣点和生活变化
- **学习机制**：
  - 高价值对话即时分析
  - 关键行为触发学习
  - 定时批量处理队列
  - 置信度阈值过滤

### 3. ProactiveDialogueEngine（主动对话引擎）
- **职责**：让AI主动与用户互动
- **核心功能**：
  - 定时检查触发条件
  - 生成主动消息
  - 管理对话时机（不打扰用户）
  - 早晚问候和总结
- **触发条件**：
  - 目标截止提醒
  - 情绪低谷检测
  - 习惯模式提醒
  - 重要日期提醒

### 4. NeedPredictionEngine（需求预测引擎）
- **职责**：预测用户可能需要什么
- **核心功能**：
  - 基于历史行为预测
  - 时间上下文分析（早/晚、工作日/周末）
  - 行为序列分析
  - 外部事件关联
- **预测类型**：
  - 每日概览需求
  - 快速记录需求
  - 深度反思需求
  - 话题整理需求

### 5. AgentService（工具执行层）
- **职责**：执行实际操作
- **可用工具（12个）**：
  - `create_todo` - 创建待办
  - `search_recordings` - 搜索录音
  - `search_notes` - 搜索笔记
  - `play_recording` - 播放录音
  - `get_recording_transcript` - 获取转写
  - `set_reminder` - 设置提醒
  - `start_recording` - 开始录音
  - `import_call_recordings` - 导入通话录音
  - `update_profile` - 更新用户画像
  - `complete_todo` - 完成待办
  - `get_today_summary` - 今日概览
  - `delete_recording` - 删除录音

## 数据流

### 用户输入处理流程
```
用户输入 → SecondBrainOrchestrator
    ↓
┌────────────────────────────────────────┐
│ 第一层：AgentService.parseToolCalls()   │
│ 第一层：AgentService.executeToolCalls() │
└────────────────────────────────────────┘
    ↓
┌────────────────────────────────────────┐
│ 第二层：ProfileEvolutionEngine.        │
│         recordConversation()           │
│ 第二层：ProfileEvolutionEngine.        │
│         triggerEvolution()             │
└────────────────────────────────────────┘
    ↓
┌────────────────────────────────────────┐
│ 第三层：NeedPredictionEngine.          │
│         predictCurrentNeeds()          │
└────────────────────────────────────────┘
    ↓
生成AI响应 → 返回给用户
```

### 主动触发流程
```
定时器触发 → SecondBrainOrchestrator.triggerProactiveEngagement()
    ↓
ProfileEvolutionEngine.analyzeForProactiveEngagement()
    ↓
获取主动建议列表 → 过滤高优先级
    ↓
生成主动消息 → 发送通知
    ↓
记录到数据库
```

## 新增数据库表

### emotional_states（情绪状态）
- 记录用户情绪变化历史
- 支持情绪趋势分析

### evolution_logs（进化日志）
- 记录画像字段的更新历史
- 追踪AI的学习轨迹

### behavior_patterns（行为模式）
- 记录用户高频行为
- 支持模式识别和预测

### proactive_messages（主动消息）
- 记录AI主动发送的消息
- 避免过度打扰

### user_behaviors（用户行为）
- 详细记录用户操作
- 支持行为分析和预测

## 使用示例

### 用户说："提醒我明天下午3点开会"
```
1. AgentService检测到 set_reminder 工具调用
2. 执行设置提醒
3. EvolutionEngine记录"用户有会议安排"
4. PredictionEngine预测"可能需要会议准备"
5. AI回复：已设置提醒，并询问是否需要准备会议资料
```

### 早上8:30主动问候
```
1. ProactiveDialogueEngine定时触发
2. 获取今日待办和记录
3. 生成个性化问候
4. 发送通知给用户
5. 记录到proactive_messages表
```

### 检测到情绪变化
```
1. 对话中检测到焦虑关键词
2. EvolutionEngine记录情绪状态
3. 对比历史情绪，发现显著变化
4. 触发主动关怀消息
5. 建议放松活动或倾听
```

## 配置参数

### ProfileEvolutionEngine
- `minConversationsBeforeEvolve`: 3（至少3次对话后开始进化）
- `evolutionCooldownHours`: 24（画像更新冷却时间）

### ProactiveDialogueEngine
- `minHoursBetweenMessages`: 4（最少间隔4小时）
- `maxDailyMessages`: 5（每天最多主动消息数）

### NeedPredictionEngine
- `confidenceThreshold`: 0.6（预测置信度阈值）

## 与Claudecode架构的对应

| Claudecode | MemoryPal Second Brain |
|------------|----------------------|
| CLAUDE.md | UserProfile（用户画像） |
| Auto-Memory | ProfileEvolutionEngine |
| ClearTool压缩 | 对话摘要和关键信息提取 |
| Coordinator模式 | SecondBrainOrchestrator |
| Sub-agents | 三层引擎分工协作 |
| Context Management | 完整上下文构建 |
| QueryEngine | SecondBrainOrchestrator |

## 后续优化方向

1. **知识图谱**：建立用户知识的图结构，支持更复杂的关联推理
2. **时序预测**：基于RNN/LSTM的行为时序预测
3. **情绪识别**：集成语音情绪分析，从录音中识别情绪
4. **个性化推荐**：基于画像的内容推荐系统
5. **多模态记忆**：整合文字、语音、图片等多模态信息
