"""The map of the game, built in Blender: every circle as a round platform, laid out from the
seed outward, with real tiles of the game on it. A board a child can open carries four tiles,
one from each of four of its groups; a group with no board inside it yet is a small grey pad
with one tile.

It reads game_map.json beside it (written by game_map_data.py). It builds in a scene of its
own, "Game map", and touches no other scene; run again, it clears only what it built.

    python tools/illustration/game_map_data.py
    blender --background --python tools/illustration/game_map_blender.py -- docs/game_map.png

Without the last two words it only builds the scene, for looking at in Blender.
"""
import json
import math
import pathlib
import sys

import bmesh
import bpy
from mathutils import Euler, Vector

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[1]
SCENE = "Game map"

data = json.loads((HERE / "game_map.json").read_text(encoding="utf-8"))

# ---------------------------------------------------------------- a scene of its own
scene = bpy.data.scenes.get(SCENE) or bpy.data.scenes.new(SCENE)
for obj in list(scene.collection.all_objects):
    bpy.data.objects.remove(obj, do_unlink=True)
if bpy.context.window:
    bpy.context.window.scene = scene


def hex_rgb(code, alpha=1.0):
    code = code.lstrip("#")
    srgb = [int(code[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    lin = [c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4 for c in srgb]
    return (*lin, alpha)


def socket(node, identifier):
    return next(s for s in node.inputs if s.identifier == identifier)


def principled(mat):
    try:
        mat.use_nodes = True
    except Exception:
        pass
    return next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")


def flat(name, code, rough=0.6):
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    bsdf = principled(mat)
    socket(bsdf, "Base Color").default_value = hex_rgb(code)
    socket(bsdf, "Roughness").default_value = rough
    return mat


def picture(path):
    """A material that shows a tile exactly as the game does: lit by itself, not by the sun."""
    name = "tile " + pathlib.Path(path).name
    mat = bpy.data.materials.get(name)
    if mat:
        return mat
    mat = bpy.data.materials.new(name)
    bsdf = principled(mat)
    tex = mat.node_tree.nodes.new("ShaderNodeTexImage")
    tex.image = bpy.data.images.load(str(ROOT / path), check_existing=True)
    socket(bsdf, "Base Color").default_value = (0, 0, 0, 1)
    mat.node_tree.links.new(tex.outputs[0], socket(bsdf, "Emission Color"))
    socket(bsdf, "Emission Strength").default_value = 1.0
    socket(bsdf, "Roughness").default_value = 1.0
    return mat


def add(name, mesh_or_data, location, material=None, rotation=(0, 0, 0)):
    obj = bpy.data.objects.new(name, mesh_or_data)
    obj.location, obj.rotation_euler = location, rotation
    if material:
        obj.data.materials.append(material)
    scene.collection.objects.link(obj)
    return obj


def disc(name, radius, height, location, material):
    mesh = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=72, radius1=radius, radius2=radius, depth=height)
    bmesh.ops.translate(bm, verts=bm.verts, vec=(0, 0, height / 2))
    bm.to_mesh(mesh)
    bm.free()
    for poly in mesh.polygons:
        poly.use_smooth = len(poly.vertices) == 4
    obj = add(name, mesh, location, material)
    bevel = obj.modifiers.new("soft edge", "BEVEL")
    bevel.width, bevel.segments, bevel.limit_method = min(0.12, height * 0.4), 3, "ANGLE"
    return obj


def box(name, size, location, material, rotation=(0, 0, 0)):
    mesh = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, verts=bm.verts, vec=size)
    bm.to_mesh(mesh)
    bm.free()
    return add(name, mesh, location, material, rotation)


def card(name, path, size, location):
    """One tile of the game: a white card with its picture on top."""
    x, y, z = location
    box(name + " card", (size, size, 0.07), (x, y, z + 0.035), WHITE)
    mesh = bpy.data.meshes.new(name)
    half = size * 0.46
    mesh.from_pydata([(-half, -half, 0), (half, -half, 0), (half, half, 0), (-half, half, 0)], [], [(0, 1, 2, 3)])
    uv = mesh.uv_layers.new(name="UVMap")
    for loop, co in zip(uv.data, [(0, 0), (1, 0), (1, 1), (0, 1)]):
        loop.uv = co
    add(name, mesh, (x, y, z + 0.073), picture(path))


def words(name, text, size, location, material, align="CENTER"):
    curve = bpy.data.curves.new(name, "FONT")
    curve.body, curve.size, curve.align_x, curve.align_y = text, size, align, "TOP"
    curve.extrude = 0.012
    curve.space_line = 0.95
    return add(name, curve, location, material)


def wrap(label, longest=12):
    line, lines = "", []
    for word in label.split():
        if line and len(line) + 1 + len(word) > longest:
            lines.append(line)
            line = word
        else:
            line = (line + " " + word).strip()
    return "\n".join(lines + [line])


def spread(objects):
    """How far these objects reach, as the camera sees them: across, and up the picture."""
    scene.view_layers[0].update()
    xs, ys = [], []
    for obj in objects:
        for corner in obj.bound_box:
            p = obj.matrix_world @ Vector(corner)
            xs.append(p.x)
            ys.append(p.y * math.cos(TILT) + p.z * math.sin(TILT))
    return min(xs), max(xs), min(ys), max(ys)


# ---------------------------------------------------------------- colours, as in the game
BRANCH = {"animal": "#6C5CE7", "plant": "#138A7C", "nature_not_alive": "#B4791A", "made_by_people": "#C24E70"}
LIGHT = {"animal": "#B9B1F5", "plant": "#8FD3C8", "nature_not_alive": "#E9C98C", "made_by_people": "#EBA9BD"}
WHITE = flat("card white", "#FFFFFF", 0.5)
INK = flat("ink", "#1F2426", 0.8)
SOFT = flat("soft ink", "#565E63", 0.8)
CLOSED = flat("not open yet", "#AEB6BF", 0.8)
SEED = flat("seed", "#FFD86B", 0.5)
GROUND = flat("ground", "#F3E9D6", 0.9)
TILT = math.radians(24)

# ---------------------------------------------------------------- where each circle stands
ANGLE = {"animal": 135, "plant": 45, "nature_not_alive": -45, "made_by_people": 225}
R1, R2 = 10.0, 21.0
STEP = {7: 13.5, 5: 15.0, 4: 15.0}
place, facing = {"seed": Vector((0, 0, 0))}, {}
for branch, degrees in ANGLE.items():
    place[branch] = Vector((R1 * math.cos(math.radians(degrees)), R1 * math.sin(math.radians(degrees)), 0))
    children = [n for n in data["nodes"] if n["parent"] == branch]
    step = STEP.get(len(children), 14.0)
    angles = [math.radians(degrees + (i - (len(children) - 1) / 2) * step) for i in range(len(children))]
    # the boards a child can open stand together, nearest the top or the bottom of the map
    angles.sort(key=lambda a: abs(math.cos(a)))
    children.sort(key=lambda n: not n["open"])
    for a, child in zip(angles, children):
        place[child["id"]] = Vector((R2 * math.cos(a), R2 * math.sin(a), 0))
        facing[child["id"]] = Vector((math.cos(a), math.sin(a), 0))

box("ground", (160, 160, 0.2), (0, 0, -0.1), GROUND)

for node in data["nodes"]:
    cid, at = node["id"], place[node["id"]]
    branch = cid.split("/")[0]
    level, is_open = node["level"], node["open"]
    if level == 0:
        radius, height, tile, mat = 3.3, 0.9, 2.1, SEED
    elif level == 1:
        radius, height, tile, mat = 2.9, 0.7, 1.85, flat("branch " + branch, BRANCH[branch], 0.5)
    elif is_open:
        radius, height, tile, mat = 2.05, 0.5, 1.3, flat("board " + branch, LIGHT[branch], 0.55)
    else:
        radius, height, tile, mat = 1.25, 0.2, 1.2, CLOSED
    disc(node["label"], radius, height, at, mat)

    # the path from the board above
    if node["parent"]:
        start, end = place[node["parent"]], at
        mid, length = (start + end) / 2, (end - start).length
        angle = math.atan2(end.y - start.y, end.x - start.x)
        path_mat = flat("path " + branch, BRANCH[branch], 0.6) if is_open else CLOSED
        box(f"path to {node['label']}", (length, 0.38 if is_open else 0.24, 0.06), (mid.x, mid.y, 0.03), path_mat, (0, 0, angle))

    # four tiles of the game, one from each of four groups, on every board that can open;
    # one tile on a group that has no board inside it yet
    if is_open:
        gap = tile * 1.06
        for i, path in enumerate(node["tiles"][:4]):
            dx, dy = ((-0.5, 0.5), (0.5, 0.5), (-0.5, -0.5), (0.5, -0.5))[i]
            card(f"{node['label']} tile {i + 1}", path, tile, (at.x + dx * gap, at.y + dy * gap, height))
    elif node["tiles"]:
        card(f"{node['label']} tile", node["tiles"][0], tile, (at.x, at.y, height))

    # its name and how many things it holds, on the side away from the paths that reach it
    reach = radius + 0.45
    if level == 0:
        anchor, align, rise = Vector((at.x, at.y - reach, 0)), "CENTER", -1
    elif level == 1:
        # between the board and the middle line of the map, clear of the path from the seed
        left, upper = at.x < 0, at.y > 0
        anchor = Vector((at.x + (1.0 if left else -1.0), at.y - reach if upper else at.y + reach, 0))
        align, rise = "RIGHT" if left else "LEFT", -1 if upper else 1
    else:
        way = facing[cid]
        anchor = at + way * reach
        align = "RIGHT" if way.x < -0.4 else "LEFT" if way.x > 0.4 else "CENTER"
        if align == "CENTER":
            anchor = Vector((at.x, at.y + (reach if way.y > 0 else -reach), 0))
        rise = 1 if way.y > 0.3 else -1 if way.y < -0.3 else 0
    label = wrap(node["label"], 18 if level < 2 else 12 if align == "CENTER" else 16)
    size = {0: 1.2, 1: 1.0}.get(level, 0.85 if is_open else 0.75)
    lines = label.count("\n") + 1
    small = size * 0.7
    block = lines * size * 0.95 + size * 0.12 + small
    top = anchor.y + block * (rise + 1) / 2
    words(node["label"] + " name", label, size, (anchor.x, top, 0.02), INK if is_open else SOFT, align)
    words(node["label"] + " count", f"{node['things']} things", small,
          (anchor.x, top - lines * size * 0.95 - size * 0.12, 0.02), SOFT, align)

# ---------------------------------------------------------------- the title and the key
drawn = [o for o in scene.collection.all_objects if o.name != "ground"]
west, east, south, north = spread(drawn)
north_y = north / math.cos(TILT)          # the same edge, measured on the ground
words("title", "What is in the game", 2.2, (west, north_y + 5.6, 0.02), INK, "LEFT")
words("subtitle", f"{data['things']} things  ·  {data['boards']} boards a child can open", 1.15,
      (west, north_y + 2.9, 0.02), SOFT, "LEFT")
key = east - 13.6
disc("key open", 0.8, 0.3, (key, north_y + 4.6, 0), flat("board animal", LIGHT["animal"], 0.55))
words("key open words", "a board he can open, with one tile\nfrom each of four of its groups", 0.8,
      (key + 1.3, north_y + 5.45, 0.02), SOFT, "LEFT")
disc("key closed", 0.6, 0.15, (key, north_y + 2.2, 0), CLOSED)
words("key closed words", "a group with no board inside it yet", 0.8, (key + 1.3, north_y + 2.6, 0.02), SOFT, "LEFT")

# ---------------------------------------------------------------- light, camera, render settings
sun = bpy.data.lights.new("sun", "SUN")
sun.energy, sun.angle = 2.0, math.radians(10)
add("sun", sun, (0, 0, 30), rotation=(math.radians(38), math.radians(-18), 0))
world = bpy.data.worlds.get("Game map sky") or bpy.data.worlds.new("Game map sky")
try:
    world.use_nodes = True
except Exception:
    pass
background = next(n for n in world.node_tree.nodes if n.type == "BACKGROUND")
background.inputs[0].default_value = (1, 1, 1, 1)
background.inputs[1].default_value = 0.5
scene.world = world

# the camera looks straight at the whole map, a little from the south, and fits it with a margin
drawn = [o for o in scene.collection.all_objects if o.name not in ("ground", "sun")]
west, east, south, north = spread(drawn)
MARGIN = 1.6
across, up = east - west + 2 * MARGIN, north - south + 2 * MARGIN
camera = bpy.data.cameras.new("map camera")
camera.type, camera.ortho_scale, camera.clip_end = "ORTHO", max(across, up), 400
tilt = Euler((TILT, 0, 0))
looking = Vector((0, 0, -1))
looking.rotate(tilt)
eye = Vector(((west + east) / 2, (south + north) / 2 / math.cos(TILT), 0)) - looking * 120
scene.camera = add("map camera", camera, eye, rotation=tilt)
scene.render.resolution_x, scene.render.resolution_y = 2600, round(2600 * up / across)
scene.render.resolution_percentage = 100

for engine in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE"):
    try:
        scene.render.engine = engine
        break
    except TypeError:
        continue
scene.render.film_transparent = False
scene.render.dither_intensity = 0.0     # flat colours stay flat, and the picture file stays small
scene.render.image_settings.file_format = "PNG"
scene.render.image_settings.color_mode, scene.render.image_settings.compression = "RGB", 100
try:
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
except Exception:
    pass
print(f"built: {len(scene.collection.all_objects)} objects in scene '{SCENE}', engine {scene.render.engine}")

# ---------------------------------------------------------------- the picture, when asked for
if "--" in sys.argv[1:] and sys.argv[sys.argv.index("--") + 1:]:
    out = pathlib.Path(sys.argv[sys.argv.index("--") + 1])
    scene.render.filepath = str(out if out.is_absolute() else ROOT / out)
    bpy.ops.render.render(write_still=True, scene=scene.name)
    print("picture written:", scene.render.filepath)
