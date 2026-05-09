# Malody Catch Mobile TODO（代码真相版 / 细化执行）

更新日期：2026-05-10
适用仓库：`Malody_catch_mobile`
协作约束：不修改桌面仓库，仅维护 mobile/core 两份分册。

## 状态语义

- `[x]` 完成
- `[~]` 进行中
- `[ ]` 待做

## M1 可发布最小闭环（进行中）

| ID | 优先级 | 状态 | 任务 | 备注 |
| --- | --- | --- | --- | --- |
| MOB-M1-001 | P0 | [x] | 固化 build 入口与产物说明 | 已补 `tools/build_android_release.ps1` 与 `docs/release_build.md` |
| MOB-M1-002 | P0 | [~] | release 签名与包体配置 | 已接入 `key.properties` 读取；真实证书/最终包名图标待定 |
| MOB-M1-003 | P0 | [x] | 权限与文件访问策略 | 已补 `docs/permissions_file_access_strategy.md` |
| MOB-M1-004 | P0 | [x] | `.mcz` 导出后系统分享 | 已接入 `share_plus`，失败回退错误提示 |
| MOB-M1-005 | P0 | [x] | 真机回归清单 v1 | 已补 `docs/smoke_checklist.md` |
| MOB-M1-006 | P0 | [x] | 异常路径用例集 | 已补 `docs/error_path_cases.md` + 自动化用例 |
| MOB-M1-007 | P0 | [x] | 桌面术语 -> 移动入口映射 | 已补 `docs/desktop_to_mobile_mapping.md` |
| MOB-M1-008 | P1 | [x] | 手势冲突优先级规则 | 已补 `docs/gesture_conflict_rules.md` |
| MOB-M1-009 | P1 | [x] | 桌面操作回放验收脚本 | 已补 `docs/desktop_operation_replay_checklist.md` |

### M1 退出检查

- [ ] 干净环境可生成并安装 release 包（待真实签名）。
- [ ] `.mc/.mcz` 核心链路在至少 2 台 arm64 真机验证通过。
- [x] 导出后分享流程可用，失败时有回退与提示。

## M2 体验与稳定性增强（部分完成）

| ID | 优先级 | 状态 | 任务 | 备注 |
| --- | --- | --- | --- | --- |
| MOB-M2-003 | P1 | [x] | 前后台播放策略 | 已实现 lifecycle pause/resume 策略并补测试 |

## M3 跨仓协同（进行中）

| ID | 优先级 | 状态 | 任务 | 备注 |
| --- | --- | --- | --- | --- |
| MOB-M3-001 | P1 | [~] | ABI 升级流程 | 已有 cross-repo preflight，仍需团队发布纪律固化 |
| MOB-M3-002 | P1 | [x] | `.so` 同步流程 | 已补同步元数据与校验脚本 |
| MOB-M3-003 | P1 | [x] | 对齐桌面 `v1.10.2` 行为与基线 | 已同步两阶段 seek/播放帧脉冲，baseline 更新至 `f3088da`（仅 `2f60ae6..f3088da` 范围） |

## 最小发布验收清单（执行面）

- [ ] 真机启动通过 startup self-check。
- [ ] `.mc/.mcz` 打开、编辑、保存、重开一致。
- [ ] `.mcz` 导出包结构正确，桌面端可打开。
- [ ] 音频播放、暂停、定位、变速与播放头联动正常。
- [ ] 异常路径（库缺失/损坏文件/保存失败）可见提示且不崩溃。

## 责任边界

- mobile 负责：文件入口、`.mcz` 工作流、音频编排、UI/交互、发布工程化。
- core 负责：编辑规则、数据结构、撤销重做、FFI 稳定接口。
