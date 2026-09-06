"""Author the shared map document; do not overwrite a user's active/library copy."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
objects = []


def vec(x=0, y=0, z=0):
    return dict(x=x, y=y, z=z)


def add(kind, name, x, z, sx=1, sy=1, sz=1, y=0, yaw=0, **props):
    obj = dict(id=f'relic_{len(objects):03d}', name=name, type=kind,
               position=vec(x, y, z), rotation_degrees=vec(0, yaw, 0),
               size=vec(sx, sy, sz), color=dict(r=1, g=1, b=1, a=1), properties=props)
    objects.append(obj)
    return obj


def prop(asset, x, z, yaw=0, scale=1, collision='box', y=0, name=None):
    return add('imported_asset', name or asset.replace('_', ' ').title(), x, z,
               scale, scale, scale, y=y, yaw=yaw,
               asset_path=f'res://assets/environment/relic_depot/{asset}.glb',
               collision_mode=collision, collision_enabled=collision != 'none')


add('ground', 'Depot island / packed earth', 0, 0, 76, .4, 64, y=-.2,
    surface_kind='dirt', uv_scale=0.3)
add('ground', 'Weathered freight apron', -6, 0, 43, .08, 49, y=.04,
    surface_kind='concrete', uv_scale=0.25)
add('player_spawn', 'Depot entry', 0, 25, .8, 1.8, .8, y=.12)
for team, z in [('alpha', 25), ('bravo', -25)]:
    for i, x in enumerate([-6, -2, 2, 6]):
        add(f'team_{team}_spawn', f'{team.title()} spawn {i+1}', x, z, 1, 1.8, 1,
            y=.12, yaw=180 if team == 'bravo' else 0)
add('bomb_pickup', 'Abandoned shipment', 1, 1, .8, .8, .8, y=.45)
add('alpha_bomb_site', 'South freight relay', -10, 21, 4, .2, 4, y=.13)
add('bravo_bomb_site', 'North freight relay', 10, -21, 4, .2, 4, y=.13)

# Warehouse occupies the west yard; containers interrupt the central long sightline.
prop('psx_old_warehouse', -23, 0, y=.08, yaw=90, name='Shuttered depot warehouse')
for a, x, z, yaw in [
    ('container_4', -8, 13, 0), ('container_5', 5, 13, 90),
    ('container_6', -7, -12, 90), ('container_7', 6, -13, 0),
    ('container_5', 0, 3, 15), ('container_6', 4, -4, 90),
    ('container_4', -12, 1, 0), ('container_7', 13, 4, 90),
]:
    prop(a, x, z, yaw, y=.08)
prop('container_6', -8, 13, y=2.17642, name='Stacked freight landmark')
for a, x, z, yaw in [
    ('dumpster', -14, -6, 90), ('generator_unit', -14, 7, 0),
    ('concrete_pipe_pile', 12, -9, 90), ('crate_wood', 1, 18, 0),
    ('crate_metal', -10, -18, 15), ('crate_wood', 8, -19, -15),
    ('crate_metal', 8, 18, 0), ('barrel_oil', -13, 10, 0),
    ('barrel_oil', -12, 10, 0), ('barrel_oil', 11, -14, 0),
    ('barrel_oil', 12, -14, 0), ('tires', -14, -9, 0),
    ('pallet', -12, -7, 30), ('pallet', -11, -8, 10),
]:
    prop(a, x, z, yaw, y=.08)

# Rocky jungle flank: no colliders on leaf cards; solid rocks provide real cover.
for i, (x, z) in enumerate([(22, 20), (27, 12), (23, 3), (29, -5), (23, -15),
                             (29, -24), (33, 25), (34, 3), (-34, 22), (-34, -23)]):
    prop(['big_rock', 'mediun_rock', 'mediun_rock_2'][i % 3], x, z, yaw=i*39,
         scale=1.1 if x < 0 else 1, collision='detailed_mesh')
for i, (x, z) in enumerate([(20, 24), (29, 20), (31, 10), (22, 10), (30, 0),
                             (22, -6), (32, -13), (24, -23), (34, -27),
                             (-33, 24), (-34, 15), (-34, -15), (-32, -26),
                             (-16, 29), (14, 29), (-14, -29), (15, -29)]):
    prop(['palm_tree', 'palm_tree_001', 'palm_tree_002'][i % 3], x, z,
         yaw=i*53, collision='detailed_mesh')
    prop('bush', x+1.3, z+.9, yaw=i*19, collision='none')
    prop('grass', x-1, z-.8, yaw=i*23, collision='none')
# Visible enclosing rock banks coincide with the automatic outer safety boundary.
for i, z in enumerate([-29, -19, -9, 1, 11, 21, 29]):
    prop('big_rock', 37, z, yaw=i*37, scale=2.1, collision='detailed_mesh')
    prop('big_rock', -38, z, yaw=i*53, scale=1.8, collision='detailed_mesh')
for z in [-32, 32]:
    for x in [-25, -15, -5, 5, 15, 25]:
        prop('mediun_rock_2', x, z, yaw=x*7, scale=2, collision='detailed_mesh')

add('moving_training_dummy', 'Yard patrol practice target', 10, -2, .8, 1.8, .8,
    y=.1, patrol_distance=5, patrol_speed=1.2)
environment = json.loads((ROOT/'config/maps/painterly_coastal_village_2v2.json').read_text())['environment']
for key in list(environment):
    if key.startswith('backdrop'):
        del environment[key]
environment.update(preset='painterly_coastal', fog_density=.0025, sun_energy=1.2,
                   ambient_energy=.75, sun_rotation=vec(-38,-40,0), exposure=1)
document = dict(schema_version=1, enabled=True, map_id='relic_depot', name='Relic Depot',
                grid_size=.5, environment=environment, objects=objects,
                gameplay=dict(primary_mode='demolition', supported_modes=['demolition','team_deathmatch'],
                              team_size=4, round_time_seconds=180, rounds_to_win=4, maximum_rounds=7,
                              plant_time_seconds=5, defuse_time_seconds=5, bomb_fuse_seconds=35,
                              elimination_wins_round=True, bomb_detonation_wins_round=True,
                              respawns_enabled=False, round_timeout_result='draw'))
(ROOT/'config/maps/relic_depot.json').write_text(json.dumps(document, indent=2)+'\n')
print(f'Relic Depot authored: {len(objects)} objects')
