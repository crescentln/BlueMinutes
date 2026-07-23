# Blue Minutes：Meeting 与 Research 双板块扩展
## MVP 与 Codex 集成计划书

**文档版本：** 0.1  
**文档状态：** 可供 Codex 开始“阶段 0：代码库审计与映射”，不授权其直接实施全部功能  
**产品名称：** Blue Minutes  
**产品定位：** Multilateral Meeting Briefing and Documentation Tool  
**长期结构：** `Meeting` 与 `Research` 两个顶层业务板块；Chat 是两者内部共享的交互能力，不是独立板块。

---

## 1. 执行摘要

Blue Minutes 现阶段的首要目标仍是完成并稳定 **Meeting** 板块。未来新增的 **Research** 板块用于联合国会议、决议、秘书长报告、成员国来函及跨会议、跨文件研究。

本计划采用分阶段集成：

1. **当前版本只做必要的架构预留**，不得因未来 Research 功能破坏或拖慢 Meeting 主流程。
2. **Meeting 1.0 稳定后**，再启用 Research MVP。
3. Research MVP 首先覆盖联合国公开资料，不包含 e-deleGATE 自动浏览。
4. e-deleGATE 只读浏览器伴侣作为后续独立阶段，必须受严格权限约束。
5. 所有模块共享工作目录、对象存储、AI Provider、Instructions、Evidence/Citation、任务和导出基础设施，但 Meeting 与 Research 的领域模型必须保持分离。
6. 如果某场联合国会议已经存在可用的 UN Transcript，系统应直接导入并跳过本地 ASR；正式 PV/SR 作为权威引用来源并行保留。

---

## 2. Codex 开工前的关键约束

Codex 必须先审计现有 Blue Minutes 代码库，再将本文件中的概念映射到真实模块、技术栈和数据库。不得基于假设重写现有软件。

### 2.1 不可违反的原则

- 不引入第二套前端技术栈。
- 不重写现有 Meeting 流程。
- 不进行破坏性数据库迁移。
- 不将 Resolution、Document、Topic 强行建模为 Meeting。
- 不让浏览器扩展、Python sidecar 或外部进程直接写主数据库。
- 不在源码、工作目录或扩展存储中保存登录令牌、Cookie、密码或 API 密钥。
- 不以提示词约束代替工具权限和代码权限。
- 不在 Research 尚未启用时向普通用户暴露不完整入口。
- 所有新能力必须通过 feature flag 分阶段启用。
- 每个阶段单独提交、测试和验收，不得一次性大改。

### 2.2 当前未知项

以下信息必须由 Codex 在阶段 0 中确认：

- Blue Minutes 当前使用的 UI、数据库、任务系统和依赖注入方式；
- Meeting、Transcript、Briefing、Evidence、AI Provider 等现有实体和接口；
- 当前工作目录与缓存策略；
- 当前测试覆盖和发布方式；
- 是否已有 Workspace、Conversation、Citation 或 Instructions 抽象；
- 本地 AI/Codex 调用的现有实现；
- 是否存在 Python sidecar、CLI 或浏览器扩展基础。

---

# 第一部分：产品定义

## 3. 产品信息架构

```text
Blue Minutes
├── Meeting
│   ├── New Meeting
│   ├── Recent Meetings
│   ├── Recordings / Imports
│   ├── Transcripts
│   ├── Speakers
│   ├── Briefings
│   └── Meeting Chat
│
├── Research
│   ├── Research Workspaces
│   ├── UN Search
│   ├── Documents
│   ├── Topics
│   ├── Saved Searches
│   └── Research Chat
│
├── Tasks
└── Settings
    ├── General
    ├── Meeting Setup
    ├── Research Setup
    ├── Evidence & Citations
    ├── AI Provider
    ├── Storage
    └── Privacy
```

### 3.1 Meeting 板块

Meeting 聚焦一场具体会议从输入到产出的完整流程：

- 现场录音或媒体导入；
- 导入已有文字稿；
- 选择最佳 Transcript 来源；
- 本地转写与发言人处理；
- Transcript Review；
- Evidence Inspector；
- 会议简报；
- 行动项与后续安排；
- 围绕当前会议持续问答。

### 3.2 Research 板块

Research 聚焦跨资料、跨会议和跨时间的持续研究：

- 联合国会议研究；
- 决议研究；
- 秘书长报告及其他 UN 文件研究；
- 多场会议对比；
- 国家立场演变；
- 时间线；
- 文件引用和关系；
- 专题工作区；
- 后续只读网页研究。

### 3.3 Chat 的定位

Chat 不作为顶层模式。它是两个板块内部的共同交互组件：

| 所在位置 | 默认上下文 |
|---|---|
| Meeting Chat | 当前会议、Transcript、录音、发言人、简报和证据 |
| Research Chat | 当前研究工作区、选定资料、检索结果和引用 |

---

## 4. 分阶段 MVP 范围

## 4.1 MVP-A：当前版本的基础预留

**目标：** 保持 Meeting 优先，同时消除未来 Research 集成时最可能发生的结构性重构。

应完成：

- 通用 `Source` 与 `Provenance` 模型；
- 可扩展 `Artifact` 类型；
- 可扩展 `Conversation` 与上下文范围；
- `InstructionProfile` 与 Instructions 编译基础；
- `TranscriptProvider` 和 `TranscriptSourceResolver` 接口；
- 内容寻址对象存储或兼容层；
- feature flag 基础；
- Meeting Setup Guide；
- 保持现有 Meeting 界面和行为不变。

不应完成：

- Research 公开入口；
- UN Digital Library、ODS 或 UN Transcript 真实连接器；
- 决议、报告和 Topic 工作区；
- e-deleGATE 浏览器扩展；
- 全库向量索引；
- 复杂知识图谱。

## 4.2 MVP-B：Research 板块首个可用版本

**启动条件：** Meeting 1.0 主流程稳定、回归测试通过、数据模型迁移验证完成。

应完成：

- 顶层 `Meeting / Research` 板块切换；
- Research 首页与 Workspace；
- Meeting Research、Resolution、Document、Topic 四类工作区；
- UN Digital Library 元数据检索；
- ODS/UNDOCS 正式文件按需获取；
- UN Transcript 检测和导入；
- 本地文件、现有 Meeting 和 UN 文件加入工作区；
- 混合检索；
- 资料范围控制；
- 持续问答；
- Citation 点击回源；
- 三类核心 Artifact：
  - Meeting Brief
  - Resolution Analysis
  - Document Analysis
- Setup Guide 的 Research 模块。

不应完成：

- e-deleGATE 自动跨页面浏览；
- 全量镜像整个 UN 文件库；
- 自动执行浏览器写操作；
- 多用户协同；
- 开放式插件市场；
- 完整 GraphRAG；
- 自动提交或发送任何材料。

## 4.3 MVP-C：只读 Browser Companion

后续独立实施：

- 读取当前授权页面；
- 读取选中文字；
- 提取标题、正文、表格、链接和附件信息；
- 用户可见的有限页面导航；
- 页面加入 Research Workspace；
- 不填写、不提交、不上传、不发送；
- 不读取 Cookie 或登录凭证；
- 受保护页面内容仅保存在本地私有域。

---

# 第二部分：用户体验与流程

## 5. 顶层导航

建议沿用 Blue Minutes 现有设计语言，在窗口顶部或主侧栏提供清晰的业务板块切换：

```text
[ Meeting ]   [ Research ]
```

要求：

- 切换后保留各自最后状态；
- 两个板块具有不同空状态和快捷操作；
- 不能用颜色 alone 表示当前板块；
- Research 未启用时入口隐藏，而不是显示半成品；
- Meeting 现有导航路径不得因新增 Research 增加多余步骤。

---

## 6. Meeting 核心流程

```text
创建或导入 Meeting
      ↓
识别媒体、已有文本和外部来源
      ↓
TranscriptSourceResolver 探测来源
      ↓
选择主 Transcript 来源
      ↓
必要时运行本地 ASR
      ↓
Transcript Review / Speaker Review
      ↓
生成 Meeting Brief
      ↓
在 Meeting Chat 中追问
      ↓
可选：发送到 Research
```

### 6.1 Transcript 来源优先策略

必须区分两个概念：

- **Primary Transcript Source：** 适合逐句阅读和时间戳定位的文本来源；
- **Authoritative Reference Source：** 适合正式引用的 PV/SR 或正式文件。

推荐决策：

1. 用户已导入并明确指定的经过校订文本；
2. 完整可用的 UN Transcript；
3. 其他外部可验证 Transcript；
4. 本地 ASR；
5. 不完整来源与局部补转写组合。

正式 PV/SR 不应简单替代时间戳 Transcript，而应作为权威引用并行保存。

### 6.2 UN Transcript 跳过转写

当未来 UN Transcript Provider 启用时：

```text
探测到完整 UN Transcript
→ 导入 Transcript、speaker、timestamp、meeting metadata
→ 不运行本地 ASR
→ 显示“未转写：已有 UN Transcript”
→ 如有正式 PV/SR，同时关联为权威来源
```

用户仍可显式选择“运行本地转写进行对照”，但不得默认浪费资源。

### 6.3 来源显示

Meeting 页面必须显示：

```text
文字来源
✓ UN Transcript       自动生成、非正式、含时间戳
✓ S/PV.xxxx           联合国正式会议记录
○ Local ASR           未运行：已有完整外部 Transcript
```

---

## 7. Research 首页

Research 首页应保持克制，不做复杂仪表盘。建议包含：

- 新建研究；
- 最近 Workspaces；
- 快速 UN Search；
- 从 Meeting 创建研究；
- 最近使用资料；
- 保存的查询。

### 7.1 新建研究入口

```text
New Research
├── Meeting Research
├── Resolution
├── Document
└── Topic
```

用户也可以从搜索结果或 Meeting 页面直接创建对应 Workspace。

---

## 8. Research Workspace 布局

建议采用三栏结构，并允许折叠：

```text
┌──────────────────────────────────────────────────────────┐
│ Sources            │ Analysis / Chat       │ Evidence    │
│                    │                       │             │
│ 已选文件           │ 核心结论              │ 引用详情    │
│ 会议               │ 追问                  │ 原文片段    │
│ 网页               │ Artifact              │ 页码定位    │
│ 检索建议           │                       │ 来源状态    │
└──────────────────────────────────────────────────────────┘
```

### 8.1 Sources 栏

- 显示资料类型、正式性、语言、日期；
- 支持 pin、排除、重新同步；
- 不在 Workspace 内复制原始文件；
- 显示资料是否已解析、已索引；
- 支持“查找相关文件”。

### 8.2 Analysis / Chat

- 先给核心结论；
- 后给分析；
- 显示当前资料范围；
- 支持继续追问；
- 可将回答保存为 Artifact；
- 支持重新生成单一章节，而不是重做全文。

### 8.3 Evidence 栏

- 文号；
- 文件标题；
- 来源等级；
- 页码、段落或时间戳；
- 原文；
- 点击打开 PDF 原页、Transcript 段落或 Meeting 时刻；
- 显示该引文支持哪一项结论。

---

## 9. 跨板块流程

### 9.1 Meeting → Research

Meeting 页面提供：

```text
[在 Research 中继续]
```

系统创建或选择 Research Workspace，并带入：

- Meeting 记录；
- Transcript；
- Briefing；
- Evidence；
- 相关正式文件；
- 当前 Conversation 的可选摘要。

不应复制媒体和 PDF。

### 9.2 Research → Meeting

当 Research 搜索发现具体会议时：

```text
[在 Meeting 中打开]
```

如果该会议已存在 Meeting 记录，直接关联；否则创建外部 Meeting 引用或按用户确认导入。

---

# 第三部分：模块化 Setup Guide 与 Instructions

## 10. Setup Guide 原则

普通用户不应被要求编写大段 prompt。默认入口采用选择式向导，高级用户可查看和编辑系统生成的 Instructions。

Setup Guide 可随时重新运行，不仅限首次启动。

## 10.1 模块结构

```text
Assistant Setup
├── General
├── Meeting
├── Research
├── Evidence & Citations
├── AI Provider
├── Storage
└── Privacy
```

## 10.2 Meeting 设置示例

- 默认语言；
- 简报风格；
- 是否保留关键原文；
- 是否提取行动项；
- Transcript 来源优先级；
- 已有外部 Transcript 时是否跳过 ASR；
- 发言人识别策略；
- 引用密度。

## 10.3 Research 设置示例

- 默认研究类型；
- 默认检索范围；
- 是否自动扩展相关文件；
- 是否比较历史文件；
- 是否生成国家立场矩阵；
- 是否保留英文原文；
- 默认 Artifact 模板。

## 10.4 Instructions 层级

不可覆盖的系统规则之下，按以下顺序合并：

```text
Global Instructions
→ Task Template
→ Workspace Instructions
→ Current Request Instructions
```

后层覆盖前层，但不得覆盖安全和证据规则。

## 10.5 结构化配置

Setup Guide 保存结构化配置，而不是只保存自然语言 prompt：

```yaml
language: zh-CN
tone: professional
meeting:
  prefer_external_transcript: true
  skip_asr_when_complete_external_exists: true
  extract_action_items: true
research:
  expand_related_documents: true
  compare_historical_sources: false
citations:
  key_claims_required: true
  show_original_quote: true
  show_page_or_timestamp: true
```

`InstructionCompiler` 将结构化配置转换为模型指令。

## 10.6 版本与可重复性

每个 Artifact 保存：

- Instruction Profile ID；
- 编译后的 Instructions hash；
- Provider 和模型；
- 资料范围；
- 检索运行 ID；
- 生成时间；
- 引用清单。

---

# 第四部分：领域模型与数据模型

## 11. 共享平台对象

### 11.1 Workspace

```text
Workspace
- id
- kind: meeting | meeting_research | resolution | document | topic
- title
- status
- created_at
- updated_at
- instruction_profile_id
- privacy_class
- archived_at
```

Meeting 可以继续保留现有领域实体，仅通过可选 `workspace_id` 或关联表接入 Workspace。不得强制将所有旧 Meeting 立即迁移为通用对象。

### 11.2 Source

```text
Source
- id
- kind
- canonical_key
- title
- provenance
- authority_level
- language
- source_url
- object_hash
- metadata_json
- created_at
- last_checked_at
```

`canonical_key` 示例：

- UN 文号；
- UN Transcript meeting slug；
- Web TV asset ID；
- 本地文件 hash；
- 浏览器页面 URL + 内容 hash。

### 11.3 WorkspaceSource

```text
WorkspaceSource
- workspace_id
- source_id
- role: primary | background | comparison | excluded
- pinned
- added_at
- added_by
```

### 11.4 Conversation 与 Message

```text
Conversation
- id
- context_kind: meeting | research
- workspace_id nullable
- title
- created_at
- updated_at

Message
- id
- conversation_id
- role
- content
- instruction_snapshot_id
- research_run_id nullable
- created_at
```

### 11.5 Artifact

```text
Artifact
- id
- workspace_id
- kind
- title
- current_version_id
- status
- created_at
- updated_at
```

Artifact 类型必须可扩展：

- MeetingBriefing
- TranscriptSummary
- ResolutionAnalysis
- DocumentAnalysis
- PositionComparison
- TimelineReport

### 11.6 Citation

```text
Citation
- id
- artifact_version_id or message_id
- source_id
- locator_type: page | paragraph | timestamp | segment | section
- locator_value
- excerpt
- claim_id nullable
- verification_status
```

### 11.7 Transcript

```text
Transcript
- id
- meeting_id
- provider
- status
- completeness
- language
- authority_level
- source_id
- created_at
- updated_at

TranscriptSegment
- id
- transcript_id
- sequence
- speaker_id nullable
- start_time nullable
- end_time nullable
- text
- provenance
- confidence nullable
```

每个 segment 保留来源，禁止把 UN Transcript、本地 ASR 和用户校订文本无标记混合。

### 11.8 ResearchRun

```text
ResearchRun
- id
- workspace_id
- query
- scope
- status
- connector_calls
- retrieved_count
- selected_count
- provider
- started_at
- completed_at
- error
```

### 11.9 InstructionProfile 与 Snapshot

```text
InstructionProfile
- id
- scope: global | template | workspace
- name
- structured_config
- raw_override nullable
- version
- updated_at

InstructionSnapshot
- id
- compiled_text
- config_hash
- profile_versions
- created_at
```

---

# 第五部分：工作目录与存储

## 12. 用户指定统一工作目录

Blue Minutes 只能使用一个用户指定的数据根目录。不得为 Research 再创建独立数据根。

建议逻辑结构：

```text
Blue Minutes/
├── config/
│   ├── settings.json
│   └── instructions/
├── database/
├── objects/
│   ├── media/
│   ├── documents/
│   ├── transcripts/
│   ├── parsed/
│   └── browser-snapshots/
├── indexes/
├── workspaces/
├── cache/
├── temp/
├── logs/
├── exports/
└── backups/
```

实际目录应适配现有 Blue Minutes 结构，不要求机械照搬。

## 12.1 内容寻址存储

所有下载和导入文件计算 SHA-256：

```text
objects/documents/ab/cd/<sha256>.pdf
```

多个 Meeting 或 Workspace 引用同一文件时只保存一份。

## 12.2 Workspace 目录

每个 Workspace 目录只保存少量人类可读文件和导出：

```text
workspaces/<workspace-id>/
├── workspace.json
├── instructions.md
├── current-brief.md
└── exports/
```

聊天、引用、任务、检索运行和对象关系保存在中央数据库，不为每轮对话生成散乱文件。

## 12.3 清理策略

| 数据 | 默认策略 |
|---|---|
| temp | 应用退出或 24 小时后清理 |
| cache | 容量上限 + LRU |
| logs | 自动轮转，默认 30 天 |
| 未保存浏览器快照 | 7—30 天 |
| 未引用对象 | 宽限期后列入可清理，不自动立即删除 |
| Workspace 已引用对象 | 不自动删除 |
| 向量索引 | 可重建，可按策略清理 |
| 导出文件 | 仅用户主动删除 |

应用应提供 Storage Dashboard，显示占用和可清理数据。

---

# 第六部分：架构与接口

## 13. 模块边界

不限定现有技术栈，但建议逻辑模块如下：

```text
BlueMinutesApp
├── MeetingFeature
├── ResearchFeature
├── SharedWorkspaceCore
├── ConversationCore
├── InstructionEngine
├── SourceRegistry
├── CitationEngine
├── TranscriptResolver
├── AIOrchestrator
├── TaskRunner
├── ObjectStore
├── Persistence
└── Integrations
    ├── LocalASR
    ├── ImportedTranscript
    ├── UNTranscript
    ├── UNDigitalLibrary
    ├── ODS
    └── BrowserCompanion
```

## 13.1 TranscriptProvider

语言无关接口：

```text
probe(meeting_context) -> availability
fetch(reference) -> transcript_payload
refresh(reference) -> transcript_payload
```

实现：

- LocalASRTranscriptProvider
- ImportedTranscriptProvider
- UNTranscriptProvider（后续）
- OfficialRecordProvider（权威文件，不一定作为时间戳 transcript）

## 13.2 TranscriptSourceResolver

输入：

- Meeting metadata；
- 用户偏好；
- 已有来源；
- 网络状态；
- 来源完整度。

输出：

```text
ResolutionDecision
- selected_primary_transcript
- authoritative_reference
- should_run_local_asr
- reason
- alternatives
```

任何跳过 ASR 的决定必须有可解释原因并显示给用户。

## 13.3 SearchConnector

```text
search(query, filters, cursor) -> normalized_results
get_metadata(id) -> source_metadata
```

## 13.4 DocumentFetcher

```text
fetch(canonical_key, language) -> object_reference
check_update(canonical_key) -> update_status
```

## 13.5 AIProvider

必须复用或扩展 Blue Minutes 现有 Provider，而不是在功能代码中直接调用 Codex：

```text
generate(request) -> streamed_response
supports(capability) -> bool
health_check() -> provider_status
```

MVP 默认可使用现有 Codex 路径，但：

- 不读取 ChatGPT Cookie；
- 不把凭证写入工作目录；
- 凭证使用操作系统安全存储或官方登录机制；
- 预留 API Provider 和本地模型；
- Provider 不可用时，文件检索、查看和历史 Artifact 仍可使用。

## 13.6 CitationEngine

负责：

- 将模型结论绑定到来源；
- 校验 locator；
- 生成统一 Citation；
- 点击回源；
- 标注无法核验的结论；
- 阻止模型生成不存在的文号、页码或时间戳。

---

# 第七部分：Research MVP 功能

## 14. Meeting Research

输入：

- 一个或多个 Meeting；
- 相关 UN 文件；
- 用户上传资料。

输出：

- 多场会议比较；
- 国家立场矩阵；
- 变化与不变；
- 时间线；
- 可追问的研究简报。

## 15. Resolution Workspace

自动收集：

- 正式案文；
- 通过日期；
- 投票；
- 通过会议；
- 提案国；
- 被引用的既有决议；
- 后续实施文件；
- 相关报告和会议。

默认 Artifact：

```text
Resolution Analysis
1. 基本信息
2. 核心内容
3. 关键执行段
4. 建立的机制和义务
5. 报告与审查安排
6. 与此前决议的关系
7. 后续实施
8. 法律和政治争议
9. 引用
```

## 16. Document Workspace

适用于：

- 秘书长报告；
- 成员国来函；
- 主席说明；
- 概念文件；
- 委员会报告。

默认 Artifact：

```text
Document Analysis
1. 文件信息
2. 授权与范围
3. 核心发现
4. 关键数据
5. 建议或结论
6. 与前期文件比较
7. 执行问题与风险
8. 相关决议和会议
9. 引用
```

## 17. Topic Workspace

用于跨文件主题，例如：

- DPRK；
- Resolution 2231；
- 1540；
- 网络安全；
- 维和授权；
- 制裁执行。

MVP 只实现资料集合、持续问答、时间线和基础立场比较，不实现完整知识图谱。

---

# 第八部分：UN 数据策略

## 18. 不镜像整个 UN 文件库

采用：

```text
广泛元数据索引
+ 重点资料预取
+ 正式文件按需下载
+ 内容寻址缓存
```

AI 不需要“预先学习”全部文件。每次研究通过检索找到候选资料，再将相关段落提供给模型。

## 18.1 检索组合

- 文号精确匹配；
- 元数据过滤；
- 全文搜索；
- 语义检索；
- reranking；
- 文件关系扩展。

## 18.2 权威性层级

建议：

```text
正式决议/决定
> 正式 PV/SR
> 秘书长报告、正式来函和正式文件
> UN 自动 Transcript
> 其他公开元数据
> 用户授权的本地或受保护页面
> 模型分析
```

模型分析不得被呈现为正式立场或原始事实。

---

# 第九部分：安全与隐私

## 19. 数据域

```text
Public UN Corpus
- 可公开同步
- 可在服务器或本机索引

Private Local Workspace
- 用户文件
- Meeting 原始资料
- e-deleGATE 页面
- 用户批注
- 私有对话
```

两个域必须在数据模型和日志中显式标记。

## 19.1 Browser Companion 后续安全边界

只允许：

- 用户主动授权当前标签页；
- 读取可见内容；
- 提取链接；
- GET 导航；
- 用户可见地打开页面；
- 停止和返回。

禁止：

- 填表；
- submit；
- 上传；
- 发送；
- sponsor；
- confirm；
- POST/PUT/PATCH/DELETE；
- Cookie 权限；
- 密码读取；
- 任意 JavaScript 执行；
- 后台批量遍历。

所有 e-deleGATE 页面默认仅本地保存，并标记“无法通过公开来源独立核验”。

---

# 第十部分：实施计划

## 20. 阶段 0：代码库审计与映射

### 目标

确认 Blue Minutes 实际架构，建立本计划与代码库的映射。

### 交付物

- `docs/BLUE_MINUTES_ARCHITECTURE_MAP.md`
- `docs/MEETING_RESEARCH_INTEGRATION_ADR.md`
- 当前实体、模块、数据流和测试清单；
- 差距分析；
- 推荐迁移路径；
- feature flag 方案；
- 风险清单。

### 测试

- 运行现有全部测试；
- 记录基线结果；
- 建立关键 Meeting 流程 smoke test。

### 完成定义

- 没有业务代码重构；
- 已明确哪些现有模块可复用；
- 已明确所有数据库迁移风险；
- 用户或维护者可审阅后决定是否进入阶段 1。

---

## 21. 阶段 1：共享抽象与兼容层

### 目标

新增未来 Research 所需的最小基础，不改变 Meeting UX。

### 交付物

- Source/Provenance；
- 可扩展 Artifact；
- Conversation 上下文；
- InstructionProfile 基础；
- TranscriptProvider 接口；
- feature flags；
- 数据迁移；
- 旧数据兼容层。

### 测试

- 旧 Meeting 可正常打开；
- 旧 Transcript、Briefing、Evidence 不丢失；
- 数据迁移可重复执行；
- 可回滚；
- Research flag 关闭时无可见变化。

### 完成定义

- 现有 Meeting 回归测试全通过；
- 无破坏性 schema 修改；
- 新接口有 contract tests。

---

## 22. 阶段 2：Meeting Setup Guide 与 Instructions Engine

### 目标

用模块化设置替代要求用户编写大量 prompt。

### 交付物

- Assistant Setup 页面；
- Meeting 配置模块；
- Evidence/Citation 模块；
- AI Provider 模块；
- 结构化配置；
- InstructionCompiler；
- Instructions 预览与高级编辑；
- Artifact 生成时保存 InstructionSnapshot。

### 测试

- 设置选择能稳定编译为同一 Instructions；
- 不可覆盖系统安全规则；
- Workspace override 正确；
- 重启后配置保留；
- 旧用户得到合理默认配置。

### 完成定义

- 用户无需写 prompt 即可完成会议简报设置；
- 高级用户可查看和修改生成指令；
- 已有 Meeting 输出无明显质量回退。

---

## 23. 阶段 3：Transcript Source Resolver

### 目标

使 Meeting 不再假设所有内容必须本地转写。

### 交付物

- TranscriptProvider registry；
- availability probe；
- resolver；
- 来源状态 UI；
- user override；
- provenance 到 segment；
- 跳过 ASR 的可解释状态；
- imported transcript provider；
- external provider stub。

### 测试

- 有完整外部 Transcript 时不运行 ASR；
- 不完整 Transcript 时可局部补转写；
- 用户可强制本地 ASR；
- 每个 segment 保留来源；
- 切换来源不删除旧版本；
- Resolver 决策可审计。

### 完成定义

- Meeting 主流程支持“导入、外部、本地”多来源；
- 不要求 UN Connector 已上线；
- 现有本地 ASR 流程保持可用。

---

## 24. 阶段 4：Meeting 1.0 稳定与 Research 入口准备

### 目标

完成 Meeting 主产品并准备未来顶层导航。

### 交付物

- Meeting 全流程稳定；
- 顶层导航组件支持两个板块；
- Research 仍由 flag 隐藏；
- “在 Research 中继续”命令占位，但不对普通用户启用；
- 存储仪表盘；
- 回归测试套件。

### 完成定义

- Meeting 1.0 达到发布标准；
- Research 不影响 Meeting 性能、启动和界面；
- 数据目录可备份和恢复。

---

## 25. 阶段 5：Research Shell 与本地资料 MVP

### 目标

先验证 Workspace、Sources、Chat 和 Citations，不立即接入全部 UN API。

### 交付物

- Research 顶层板块；
- Research 首页；
- 四种 Workspace；
- Sources/Analysis/Evidence 三栏；
- 从 Meeting 加入 Research；
- 上传本地文件；
- 工作区内持续问答；
- Artifact 基础；
- Research Setup Guide。

### 测试

- Meeting 可无复制地加入 Research；
- Workspace 删除不删除共享原始对象；
- Citation 可回到本地来源；
- Research flag 可独立开关；
- Research 数据不污染 Meeting 列表。

### 完成定义

- 用户可以用现有 Meeting 和本地文件完成一个可追问研究；
- 无 UN Connector 也能形成完整闭环。

---

## 26. 阶段 6：UN Connectors 与三大研究场景

### 目标

接入公开 UN 资料并通过会议、决议、报告三大验收场景。

### 交付物

- UN Digital Library Connector；
- ODS/UNDOCS Fetcher；
- UN Transcript Provider；
- 元数据归一化；
- 按需下载和缓存；
- 混合检索；
- Meeting Brief；
- Resolution Analysis；
- Document Analysis；
- 正式性和权威性标记。

### 测试

- 文号精确查询；
- UN Transcript 存在时跳过 ASR；
- 正式 PV/SR 与 Transcript 并行；
- PDF 页码引用；
- 缓存命中；
- API 错误和限流恢复；
- 同一文件不重复存储。

### 完成定义

- 会议、决议、秘书长报告三个核心用例全部通过；
- 关键事实必须有有效引用；
- 无法核验的信息明确标注。

---

## 27. 阶段 7：质量、评估与发布

### 目标

使 Research MVP 达到可长期维护和可信使用的标准。

### 交付物

- Golden Questions；
- Citation 验证；
- 检索评估；
- UI 回归；
- 性能监控；
- 失败恢复；
- 日志脱敏；
- 数据导出和备份恢复测试；
- 用户文档。

### 完成定义

- Meeting 回归测试全部通过；
- Research 核心场景通过；
- 无 P0/P1 数据丢失或隐私问题；
- 所有新模块有 owner、文档和测试。

---

## 28. 阶段 8：Browser Companion（后续）

必须作为单独项目和安全审查实施，不属于 Research 首个 MVP 的完成条件。

---

# 第十一部分：验收用例

## 29. UC-M01：已有 UN Transcript 的会议

**用户行为：** 导入或识别一场已有 UN Transcript 的会议。

**预期：**

- 系统探测到 Transcript；
- 展示来源和完整度；
- 默认不运行本地 ASR；
- 可打开时间戳；
- 如果存在 PV/SR，同时关联；
- 简报引用可区分 Transcript 与正式记录；
- 用户可继续问各国具体说法。

## 30. UC-M02：无外部 Transcript 的会议

- 系统探测不到可用外部文本；
- 运行现有本地 ASR；
- 保留本地来源；
- 后续外部 Transcript 出现时提示更新或比较，不静默覆盖用户校订。

## 31. UC-R01：会议简报与持续问答

- 找到会议；
- 创建 Meeting 或 Meeting Research Workspace；
- 生成会议简报；
- 用户追问“某国具体怎么说”；
- 回答定位到 speaker、timestamp 或 PV 页码；
- 回答不混淆正式记录和自动 Transcript。

## 32. UC-R02：决议分析

- 用户按文号或自然语言搜索决议；
- 系统取得正式案文；
- 输出核心内容和关键执行段；
- 列出相关此前和后续文件；
- 用户可继续追问历史关系；
- 每项法律依据回到正式案文。

## 33. UC-R03：秘书长报告分析

- 用户查找指定或最新报告；
- 系统识别报告依据、覆盖期间和相关决议；
- 生成要点；
- 用户可追问具体章节、与前期报告的差异；
- 引用定位到页码或章节。

## 34. UC-X01：Meeting 转 Research

- Meeting 中点击“在 Research 中继续”；
- 新 Workspace 引用现有资料；
- 不复制媒体和 PDF；
- 对话可选择摘要迁移；
- Meeting 原记录保持不变。

## 35. UC-S01：Setup Guide

- 新用户通过若干选择完成设置；
- 系统生成可预览 Instructions；
- 用户不写 prompt 也能生成符合偏好的简报；
- 修改设置只影响新输出，旧 Artifact 保留原快照。

## 36. UC-D01：去重和清理

- 同一 PDF 加入多个 Workspace；
- 磁盘只保存一份；
- 删除一个 Workspace 不删除仍被引用的对象；
- temp/cache 按策略清理；
- 备份恢复后所有引用有效。

---

# 第十二部分：性能与非功能要求

## 37. 可靠性

- 所有后台任务幂等；
- 应用中断后可恢复；
- Connector 错误不损坏 Workspace；
- Artifact 版本不可因重新生成而丢失；
- 数据迁移有备份和回滚。

## 38. 性能

实际指标由阶段 0 根据现有架构校准。建议目标：

- Meeting/Research 板块切换无明显阻塞；
- UI 主线程不得执行解析、索引或网络任务；
- 已缓存资料打开应近实时；
- 长任务显示进度和取消；
- 首批检索结果优先返回，深度扩展可继续进行；
- 大文件解析和 embedding 可暂停与恢复。

## 39. 可维护性

- 接口版本化；
- Connector contract tests；
- Prompt/Instructions 不散落在 UI 代码；
- 每个 feature flag 有移除计划；
- 日志包含 run ID，不包含敏感正文；
- Sidecar 或扩展只通过受控 API 与主应用通信。

## 40. 可访问性与 UX

- 键盘可操作；
- 清晰焦点状态；
- 不只使用颜色表达来源或状态；
- 长回答提供层级和折叠；
- 高级选项渐进披露；
- 用户始终知道当前资料范围；
- 用户始终知道系统正在检索、分析还是引用已有资料。

---

# 第十三部分：风险与缓解

| 风险 | 缓解 |
|---|---|
| Research 拖慢 Meeting 交付 | 分成 MVP-A/B/C，feature flag |
| 领域模型污染 | Shared Platform 与业务域分离 |
| 双技术栈失控 | 沿用现有 UI；sidecar 仅做明确任务 |
| 文件膨胀 | 内容寻址、共享对象、LRU |
| 引用幻觉 | CitationEngine、locator 校验 |
| UN 接口不稳定 | Connector、缓存、重试、离线可读 |
| Instructions 难用 | Setup Guide + 结构化配置 |
| 外部 Transcript 质量差 | 完整度评分、用户覆盖、来源并存 |
| 私有资料泄露 | 数据域、显式授权、本地默认 |
| Codex 一次性大改 | 阶段 PR、审计先行、停止点 |

---

# 第十四部分：Codex 交付规范

每一阶段必须返回：

1. 当前架构理解；
2. 修改文件清单；
3. 数据迁移说明；
4. 新增或修改接口；
5. 测试结果；
6. 未解决风险；
7. 手工验证步骤；
8. 回滚方法；
9. 是否满足该阶段 Definition of Done。

不得以“代码能编译”代替完成标准。

---

# 第十五部分：最终产品原则

1. Blue Minutes 的顶层业务板块是 **Meeting** 与 **Research**。
2. Chat 是嵌入两者的交互能力。
3. Meeting 继续作为当前开发和发布优先级。
4. Research 在 Meeting 稳定后分阶段启用。
5. 已有高质量外部 Transcript 时避免重复本地转写。
6. 正式 PV/SR 与时间戳 Transcript 并行使用。
7. Instructions 以模块化 Setup Guide 为默认入口。
8. 所有资料和产出使用统一工作目录及内容寻址存储。
9. Public UN Corpus 与私有资料分域。
10. 核心事实、立场和法律依据必须可回到证据。
11. 新能力必须模块化、可关闭、可测试、可迁移。
12. Codex 必须先审计，再按阶段实施。
