# 《一念》— 双人反应博弈 PvP

## 项目信息
- 引擎：Godot 4.7.1，GL Compatibility 模式
- 分辨率：2560×1440，窗口模式（编辑器设置搜「窗口」改运行模式）
- Godot 可执行文件：`E:\gamemaker\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64.exe`
- MCP 连接：Godot-MCP-Native 插件，HTTP `localhost:9080/mcp`

## 场景结构
| 文件 | 用途 |
|------|------|
| `battle_ui.tscn` | 主场景 |
| `battle_ui2.tscn` | 备份副本（未同步更新） |
| `scenes/battle_ui.gd` | 战斗 UI 逻辑 |
| `assets/stage_bg.png` | 格斗场景背景 |
| `assets/p1_attack/` | P1（铁链女）攻击序列帧 34 帧，帧朝左 |
| `assets/p2_attack/` | P2（棒球男）攻击序列帧 20 帧，帧朝右 |
| `assets/attack_icon.png` | 攻击按钮图标 |
| `assets/block_icon.png` | 格挡按钮图标 |

## 当前 BattleUI 节点树
```
BattleUI (Control) → battle_ui.gd
├── Background (TextureRect) — stage_bg.png
├── Label — 金色倒计时，字号 200，居中
├── Timer
├── P1Sprite (AnimatedSprite2D) — idle 远(640,900) / 近(1100,900), flip_h=true, 48 FPS
├── P2Sprite (AnimatedSprite2D) — idle 远(1920,900) / 近(1460,900), flip_h=false, 24 FPS
├── AttackBtn (Button) — 左下，深红，显示 "Q / O 攻击"
└── BlockBtn (Button) — 右下，金色，显示 "W / P 格挡"
```
- 编辑器会提示 SpriteFrames 缺失 — 不影响运行，脚本在 _ready() 中设置
- 按钮有呼吸动画（Tween 循环，上下 8px）

## 操作
- P1：Q = 攻击，W = 格挡（仅倒数 > 2 秒可用）
- P2：O = 攻击，P = 格挡（仅倒数 > 2 秒可用）
- 空格 = 重置回合
- ESC = 退出游戏

## 战斗流程（状态机）
```
WAITING → 空格 → COUNTDOWN(5秒,远距离) → TELEPORT_IN(消失→贴脸)
  → IMPACT(顿帧0.06s→播动画→延迟0.58s命中→屏震) → ANIMATE(动画播完)
  → TELEPORT_OUT(消失→回位) → WAITING
```
- 双方都做出选择 → 立即结束倒计时进入判定
- 顿帧 = Engine.time_scale=0 冻结画面
- 屏震 = BattleUI 节点随机抖动，强度24px/10步，衰减式
- 命中延迟按帧率计算：P1(48FPS)第28帧 / P2(24FPS)第14帧
- 格挡动画尚未实现，暂用 idle 代替

## 动画状态
| 动画 | P1(链女) | P2(棒球男) | 循环 |
|------|----------|------------|------|
| idle | 20帧, 10FPS | 20帧, 10FPS | 循环 |
| attack | 34帧, 48FPS | 20帧, 24FPS | 不循环 |
| hurt | 26帧, 24FPS | 20帧, 24FPS | 不循环 |
| block | 暂无 | 暂无 | - |

- 挨打触发条件：一方攻击且另一方没格挡也没对攻 → 挨打方播 hurt
- 双方对攻 → 都播 attack（拼刀），不播 hurt
- 攻击被格挡 → 攻击方播 attack，格挡方播 idle（反弹伤害不额外播 hurt）
- 播完自动回 idle

## 已知问题
- F5 全屏：需在编辑器设置中搜「窗口」，改运行模式为「窗口模式」
- 编辑器看不到角色动画帧：运行时才加载，正常现象

## 缺失资产
- [ ] P1/P2 Idle（待机）序列帧 — 暂用攻击第1帧
- [ ] P1/P2 Block（格挡）序列帧 — 暂用 idle
- [ ] P1/P2 Hurt（受伤）序列帧

## 待办
- [x] 换攻击/格挡按钮图标
- [x] 按钮呼吸动画
- [x] F5 全屏修复 + ESC 退出
- [x] P1/P2 角色 AnimatedSprite2D + 攻击帧加载
- [x] 键盘输入分离（P1 Q/W vs P2 O/P）
- [x] 回合流程状态机 + 瞬移效果
- [x] 顿帧 + 屏震
- [x] 伤害判定 + HP/回合/格挡次数 + 胜负
- [ ] HP 血条 UI（当前用纯文字）
- [ ] 缺失序列帧生成
- [ ] 实现 P2P 联机（Godot ENET）
