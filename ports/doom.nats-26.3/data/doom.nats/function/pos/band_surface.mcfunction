# doom.nats:pos/band_surface —— 模式 0 第二步：玩家层扫不到时，把锚点搬到该列地表再扫
#
# 为什么需要（v4.31）：原版 getRandomPosWithin 的 y = random(minY, 该列 WORLD_SURFACE + 1)，
#   **与玩家高度完全无关**；模式 0 的第一个窗口只有「玩家层 +2 .. -16」，玩家飞在高空时整窗都是空气，
#   v4.19 的回退虽把上界抬到玩家层+2，但候选点绝大多数落在空气里被 check/block 拒掉
#   （真机：玩家 y=200、午间、90 秒 0 生成；玩家 y=64 也是 0，而同条件纯原版刷了 12 只）。
# 这里用 heightmap（motion_blocking_no_leaves，与 ON_GROUND 落位判据所用 heightmap 同源）
#   把锚点搬到候选列的真实地表，再复用玩家层那同一份 19 层几何往下扫。
# 只在「地表低于玩家层」时接管：玩家在洞穴/地下时地表在头顶，跳过本步、落回 v4.19 的整列回退，行为同 v4.30。
# 前置：执行位置已由 pos/band_at 定为 (px, 玩家y, pz)。
execute if score $band.dy doom.nats matches 9999 if loaded ~ ~ ~ positioned over motion_blocking_no_leaves run function doom.nats:pos/band_surface_at
