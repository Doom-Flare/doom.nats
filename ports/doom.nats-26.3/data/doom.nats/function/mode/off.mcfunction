# doom.nats:mode/off —— 退场：静默清掉本包生物，本包停止刷怪，并把原版自然生成还回去
# ★ `$mode.off` 是退场锁：core/tick 第 3 行靠它整函数 return。
#   v4.30.1 及更早没有这把锁 —— 跑完 mode/off 之后本包仍在 spawn/batch 里 summon 生物，
#   与文档（16/21/24/25 与 wiki 安装与升级）声称的「退场」不符。解锁用 mode/survival 或 mode/auto。
function doom.nats:debug/clear
scoreboard players set $mode.off doom.nats 1
gamerule spawn_mobs true
say [nats] mode/off —— 已静默清场，本包停止刷怪，并把自然生成还给原版（重新接管用 mode/survival）
