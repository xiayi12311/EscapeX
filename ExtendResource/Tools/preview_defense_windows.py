"""Preview configured EscapeX window points in the current editor world.

Run as a file through the Oasis editor Python interface. Select window points
first to preview just those windows. The script draws transient lines and
returns an inspection report without saving the map.
"""

import math
import re
from collections import Counter
from pathlib import Path

import unreal_engine as ue
from unreal_engine import FLinearColor, FVector


def read_queue_offsets():
    source = Path(ue.project_get_path('script')) / 'Gameplay/ZombieDefense/DefenseCatalog.lua'
    match = re.search(r'WindowQueue\s*=\s*\{\s*WaitOffsets\s*=\s*\{([^}]+)\},\s*RetreatOffset\s*=\s*([-\d.]+)',
                      source.read_text(encoding='utf-8'))
    if match is None:
        raise ValueError('无法读取窗户等候位配置')
    waits, retreat = match.groups()
    return [-float(value.strip()) for value in waits.split(',')], -float(retreat)


def outline(a, geometry, extent, color):
    x, y, z = extent
    corners = [geometry(s * x, t * y, u * z)
               for s in (-1, 1) for t in (-1, 1) for u in (-1, 1)]
    for i, point in enumerate(corners):
        for bit in (1, 2, 4):
            j = i ^ bit
            if j > i:
                a.draw_debug_line(point, corners[j], color, 30.0, 1.5)


def inspect(world, a, duplicate, queue_offsets):
    errors = []
    if duplicate:
        errors.append('重复的 PointId')
    if not a.PointId or not a.EncounterId:
        errors.append('缺少 PointId 或 EncounterId')
    skill = a.VaultSkillClass
    if not skill:
        errors.append('未指定翻窗技能')
    for field in ('BoardsPerWindow', 'BoardDurability', 'InstallSeconds', 'InstallRange',
                  'VaultDistance', 'OutsideDistance', 'BoardWidth', 'SlotSpacing',
                  'GateHalfDepth', 'GateHalfHeight', 'QueryHalfDepth', 'QueryHalfWidth',
                  'QueryHalfHeight', 'StartRadius', 'LandingRadius', 'FootTolerance',
                  'NavProjectionHeight'):
        value = getattr(a, field)
        if not math.isfinite(value) or value <= 0:
            errors.append(f'{field} 必须大于 0')
    p = a.get_actor_location()
    rotation = a.get_actor_rotation()
    angle = math.radians(rotation.yaw)
    dx, dy = math.cos(angle), math.sin(angle)

    def point(x, y, z):
        return FVector(p.x + dx*x - dy*y, p.y + dy*x + dx*y, p.z + z)

    outside = a.OutsideDistance
    inside = a.VaultDistance - outside
    floor_out = a.OutsideFloorOffset - a.FloorBelow
    floor_in = a.InsideFloorOffset - a.FloorBelow
    if min(outside, inside) <= a.GateHalfDepth:
        errors.append('起跳或落点落在封窗盒内')
    if max(abs(rotation.roll), abs(rotation.pitch)) > 0.1:
        errors.append('点位只允许水平旋转')
    scale = a.get_actor_scale()
    if max(abs(value-1) for value in (scale.x, scale.y, scale.z)) > 0.001:
        errors.append('点位缩放须为 1，请用窗型规格设置尺寸')
    if abs(floor_out - floor_in) > a.FootTolerance:
        errors.append('起跳点与落点高差超出技能容差')

    def mark(x, y, z, color):
        a.draw_debug_line(point(x-12, y, z), point(x+12, y, z), color, 30.0, 2.0)
        a.draw_debug_line(point(x, y-12, z), point(x, y+12, z), color, 30.0, 2.0)
        a.draw_debug_line(point(x, y, z), point(x, y, z+35), color, 30.0, 2.0)

    def check_floor(name, x, y, z):
        hit = world.line_trace_single_by_channel(point(x, y, z+45), point(x, y, z-35), 3)
        if hit is None or abs(hit.impact_point.z - (p.z+z)) > a.FootTolerance:
            errors.append(f'{name}附近没有在容差内的地面')

    cyan = FLinearColor(0, 0.9, 1, 1)
    green = FLinearColor(0.1, 1, 0.2, 1)
    orange = FLinearColor(1, 0.5, 0.1, 1)
    red = FLinearColor(1, 0.15, 0.2, 1)
    a.draw_debug_line(point(-outside, 0, floor_out+35), point(inside, 0, floor_in+35), cyan, 30.0, 2.0)
    mark(-outside, 0, floor_out, orange)
    mark(inside, 0, floor_in, green)
    mark(a.InteractIn + a.InteractionDepthOffset, 0, 0, cyan)
    check_floor('起跳点', -outside, 0, floor_out)
    check_floor('落点', inside, 0, floor_in)

    def gate(x, y, z):
        return point(x, y, z+a.BoardHeightOffset+a.GateUp)

    def query(x, y, z):
        return point(x+a.QueryIn, y, z)

    outline(a, gate, (a.GateHalfDepth, a.BoardWidth/2, a.GateHalfHeight), red)
    outline(a, query, (a.QueryHalfDepth, a.QueryHalfWidth, a.QueryHalfHeight), cyan)
    capacity = a.BoardsPerWindow
    for slot in range(capacity):
        z = a.BoardHeightOffset + (slot-(capacity-1)/2)*a.SlotSpacing
        a.draw_debug_line(point(0, -a.BoardWidth/2, z), point(0, a.BoardWidth/2, z), orange, 30.0, 3.0)

    if a.QueueEnabled:
        wait_offsets, retreat = queue_offsets
        for i, y in enumerate(wait_offsets, 1):
            mark(-outside, y, floor_out, cyan)
            check_floor(f'等候位 {i}', -outside, y, floor_out)
        mark(-outside, retreat, floor_out, red)
        check_floor('退让位', -outside, retreat, floor_out)
    return {'label': a.get_actor_label(), 'point_id': str(a.PointId),
            'skill': skill.get_name() if skill else None, 'queue': a.QueueEnabled, 'errors': errors}


world = ue.get_editor_world()
windows = [a for a in world.all_actors() if a.get_class().get_name() == 'BP_ZS_WindowPoint_C'
           and a.Enabled]
selected = {a.get_path_name() for a in ue.editor_get_selected_actors()}
active = [a for a in windows if a.get_path_name() in selected] or windows
counts = Counter((a.EncounterId, a.PointId) for a in windows)
queue_offsets = read_queue_offsets()
__askq_result = [inspect(world, a, counts[a.EncounterId, a.PointId] > 1, queue_offsets) for a in active]
ue.redraw_all_viewports()
