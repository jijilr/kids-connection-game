"""The Instagram film's set, in Blender 5.2 (EEVEE): a phone lying on a desk, the game playing on it.

Made the way the owner's Glym promos 4 and 8 were (vocabulary_swipe_app, tool/deck_engine/blender/
promo4_scene.py and parents_scene.py; read, not changed): varnished wood in warm light, a phone with
the app's own film on its screen, a few things of a child's play beside it, and one camera that is
never still: in on the pictures as they are touched, in on the clue, back for the web, wide for the
close. The words go over the frames afterwards (insta_make.py), so wording can change without a render.

The light and the wood are Poly Haven's (CC0): tools/insta/set/, listed with their sources in
tools/insta/set_sources.json. The scene is built from nothing on every run; no .blend is kept.

    blender -b --factory-startup -P tools/insta/insta_scene.py -- \\
        --times tools/insta/out/times.json --track tools/insta/out/track [--stills 2,12] [--frames 1-120] [--preview]
"""
import argparse
import json
import math
import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Matrix, Vector

HERE = Path(__file__).resolve().parent
SET = HERE / "set"
FPS, W, H = 30, 1080, 1920
LENS = 85
# Where the phone may sit in the upright frame (shares from the bottom-left): under the words at the top,
# and clear of Instagram's own buttons along the foot and the right edge.
ON_PHONE = (0.08, 0.10, 0.88, 0.70)
PHONE_AT = Vector((8.6, -0.6, 0.0))
PHONE_TURN = math.radians(4.0)
SCREEN_W = 3.1          # units; its height follows the track's shape
BEZEL = 0.15
BODY_R = 0.56
BODY_Z, BODY_T = 0.05, 0.13


# ------------------------------------------------------------------ small helpers

def _set(target, **values):
    for key, value in values.items():
        if hasattr(target, key):
            setattr(target, key, value)


def linear(hex_color, alpha=1.0):
    h = hex_color.lstrip("#")

    def chan(i):
        c = int(h[i:i + 2], 16) / 255
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
    return (chan(0), chan(2), chan(4), alpha)


def look_at(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


def plain(name, colour, roughness, specular=0.3):
    mat = bpy.data.materials.get(name)
    if mat is None:
        mat = bpy.data.materials.new(name)
        if mat.node_tree is None:
            mat.use_nodes = True
        bsdf = mat.node_tree.nodes["Principled BSDF"]
        bsdf.inputs["Base Color"].default_value = linear(colour)
        bsdf.inputs["Roughness"].default_value = roughness
        bsdf.inputs["Specular IOR Level"].default_value = specular
    return mat


def rounded_outline(w, h, r, segments=14):
    pts = []
    for cx, cy, start in ((w / 2 - r, h / 2 - r, 0), (-w / 2 + r, h / 2 - r, 90), (-w / 2 + r, -h / 2 + r, 180),
                          (w / 2 - r, -h / 2 + r, 270)):
        for i in range(segments + 1):
            a = math.radians(start + 90 * i / segments)
            pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts


def rounded_slab(name, w, h, r, z0, z1, segments=14):
    """A slab with rounded corners, lying flat: its top at z1, its underside at z0."""
    outline = rounded_outline(w, h, r, segments)
    bm = bmesh.new()
    top = [bm.verts.new((x, y, z1)) for x, y in outline]
    bottom = [bm.verts.new((x, y, z0)) for x, y in outline]
    bm.faces.new(top)
    bm.faces.new(list(reversed(bottom)))
    for i in range(len(outline)):
        j = (i + 1) % len(outline)
        bm.faces.new((bottom[i], bottom[j], top[j], top[i])).smooth = True
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def smoother(u):
    u = min(1.0, max(0.0, u))
    return u * u * u * (u * (6 * u - 15) + 10)


def frame_at(t):
    return round(t * FPS) + 1


def direction(elevation, azimuth):
    el, az = math.radians(elevation), math.radians(azimuth)
    return Vector((math.sin(az) * math.cos(el), -math.cos(az) * math.cos(el), math.sin(el)))


def place(cam, centre, view, distance, shift):
    cam.location = Vector(centre) + direction(*view) * distance
    look_at(cam, centre)
    cam.data.shift_x, cam.data.shift_y = shift


# ------------------------------------------------------------------ the set

def reset_and_render_settings(preview):
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    bpy.data.orphans_purge(do_local_ids=True, do_linked_ids=True, do_recursive=True)
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x, scene.render.resolution_y = W, H
    scene.render.resolution_percentage = 50 if preview else 100
    scene.render.fps = FPS
    scene.render.film_transparent = False
    scene.render.image_settings.file_format = "JPEG"
    scene.render.image_settings.quality = 94
    # Standard, not AgX: the game's own colours must come out as they are on the screen.
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    _set(scene.eevee, taa_render_samples=16 if preview else 64, use_raytracing=True, use_shadows=True,
         shadow_ray_count=3, shadow_step_count=12, use_fast_gi=True, fast_gi_method="GLOBAL_ILLUMINATION")
    return scene


def world_light(strength=0.55):
    """The studio light from all round (warm), its picture never seen: past the desk the camera sees dark."""
    world = bpy.data.worlds.new("Insta World")
    bpy.context.scene.world = world
    world.use_nodes = True
    nodes, links = world.node_tree.nodes, world.node_tree.links
    back = nodes["Background"]
    env = nodes.new("ShaderNodeTexEnvironment")
    env.image = bpy.data.images.load(str(SET / "ferndale_studio_11_hdri_2k.hdr"), check_existing=True)
    links.new(env.outputs["Color"], back.inputs["Color"])
    back.inputs["Strength"].default_value = strength
    seen = nodes.new("ShaderNodeBackground")
    seen.inputs["Color"].default_value = linear("#1A140F")
    path = nodes.new("ShaderNodeLightPath")
    mix = nodes.new("ShaderNodeMixShader")
    links.new(path.outputs["Is Camera Ray"], mix.inputs["Fac"])
    links.new(back.outputs["Background"], mix.inputs[1])
    links.new(seen.outputs["Background"], mix.inputs[2])
    links.new(mix.outputs["Shader"], nodes["World Output"].inputs["Surface"])


def add_desk():
    mesh = bpy.data.meshes.new("Desk")
    s = 160.0
    mesh.from_pydata([(-s, -s, 0), (s, -s, 0), (s, s, 0), (-s, s, 0)], [], [(0, 1, 2, 3)])
    uv = mesh.uv_layers.new(name="UVMap")
    for loop_index in mesh.polygons[0].loop_indices:
        x, y, _ = mesh.vertices[mesh.loops[loop_index].vertex_index].co
        uv.data[loop_index].uv = (x / 58.0, y / 58.0)
    mat = bpy.data.materials.new("Desk Wood")
    if mat.node_tree is None:
        mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    bsdf = nodes["Principled BSDF"]

    def tex(name, colour):
        node = nodes.new("ShaderNodeTexImage")
        node.image = bpy.data.images.load(str(SET / name), check_existing=True)
        node.image.colorspace_settings.name = "sRGB" if colour else "Non-Color"
        return node

    tone = nodes.new("ShaderNodeHueSaturation")      # a little lighter and less red than the varnish
    tone.inputs["Value"].default_value = 1.38
    tone.inputs["Saturation"].default_value = 0.78
    links.new(tex("wood_table_001_diffuse_2k.jpg", True).outputs["Color"], tone.inputs["Color"])
    links.new(tone.outputs["Color"], bsdf.inputs["Base Color"])
    soften = nodes.new("ShaderNodeMath")
    soften.operation = "MULTIPLY_ADD"
    soften.inputs[1].default_value = 0.45
    soften.inputs[2].default_value = 0.42
    links.new(tex("wood_table_001_rough_2k.jpg", False).outputs["Color"], soften.inputs[0])
    links.new(soften.outputs["Value"], bsdf.inputs["Roughness"])
    normal_map = nodes.new("ShaderNodeNormalMap")
    normal_map.inputs["Strength"].default_value = 0.3
    links.new(tex("wood_table_001_nor_gl_2k.jpg", False).outputs["Color"], normal_map.inputs["Color"])
    links.new(normal_map.outputs["Normal"], bsdf.inputs["Normal"])
    mesh.materials.append(mat)
    desk = bpy.data.objects.new("Desk", mesh)
    bpy.context.scene.collection.objects.link(desk)


def add_lights():
    """A big warm key from the upper left (a lamp out of frame), a cool faint fill from the right."""
    for name, location, size, energy, colour in (("Key", (-22.0, 18.0, 30.0), 22.0, 60000.0, (1.0, 0.86, 0.68)),
                                                ("Fill", (30.0, -14.0, 22.0), 26.0, 9000.0, (0.86, 0.92, 1.0))):
        data = bpy.data.lights.new(name, "AREA")
        data.shape, data.size, data.energy, data.color = "DISK", size, energy, colour
        obj = bpy.data.objects.new(name, data)
        obj.location = location
        bpy.context.scene.collection.objects.link(obj)
        look_at(obj, Vector((6.0, 0.0, 0.0)))


def track_material(track):
    """The phone's screen: the game's own frames (t00001.jpg ...), one per film frame, as emission."""
    frames = sorted(Path(track).glob("t*.jpg"))
    if not frames:
        sys.exit(f"no screen track in {track}")
    mat = bpy.data.materials.new("Phone Screen")
    if mat.node_tree is None:
        mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    bsdf = nodes["Principled BSDF"]
    node = nodes.new("ShaderNodeTexImage")
    image = bpy.data.images.load(str(frames[0]), check_existing=True)
    image.source = "SEQUENCE"
    node.image = image
    user = node.image_user
    user.frame_duration = len(frames)
    user.frame_start = 1
    user.frame_offset = int(frames[0].stem[1:]) - 1
    user.use_auto_refresh = True
    node.interpolation = "Cubic"
    bsdf.inputs["Base Color"].default_value = (0.0, 0.0, 0.0, 1.0)
    links.new(node.outputs["Color"], bsdf.inputs["Emission Color"])
    bsdf.inputs["Emission Strength"].default_value = 1.0
    bsdf.inputs["Roughness"].default_value = 0.2       # glass: the lamp shows a little in it
    bsdf.inputs["Specular IOR Level"].default_value = 0.35
    return mat


def add_phone(track, screen_px):
    """A phone lying on the desk: a dark body, an even black bezel, and the picture on rounded glass whose
    corners follow the body's. Side buttons, so it reads as a phone from any angle. Returns a function from a
    point of the screen's picture (track pixels) to the world; past the picture's edge, the desk around it."""
    w = SCREEN_W
    h = w * screen_px[1] / screen_px[0]
    body = rounded_slab("Phone", w + 2 * BEZEL, h + 2 * BEZEL, BODY_R, BODY_Z, BODY_Z + BODY_T)
    body.data.materials.append(plain("Phone Body", "#141517", 0.32))
    edge = plain("Phone Buttons", "#3A3C40", 0.3)
    parts = [body]
    for name, side, y, length in (("Power", 1, 0.9, 0.95), ("Volume Up", -1, 1.35, 0.6), ("Volume Down", -1, 0.55, 0.6)):
        button = rounded_slab(name, 0.05, length, 0.024, BODY_Z + 0.035, BODY_Z + BODY_T - 0.035, segments=4)
        button.data.materials.append(edge)
        button["offset"] = (side * (w / 2 + BEZEL + 0.012), y)
        parts.append(button)
    z = BODY_Z + BODY_T + 0.003
    outline = rounded_outline(w, h, BODY_R - BEZEL, 16)
    mesh = bpy.data.meshes.new("Phone Screen")
    mesh.from_pydata([(x, y, z) for x, y in outline], [], [list(range(len(outline)))])
    uv = mesh.uv_layers.new(name="UVMap")
    for loop_index in mesh.polygons[0].loop_indices:
        x, y, _ = mesh.vertices[mesh.loops[loop_index].vertex_index].co
        uv.data[loop_index].uv = (x / w + 0.5, y / h + 0.5)
    mesh.materials.append(track_material(track))
    screen = bpy.data.objects.new("Phone Screen", mesh)
    bpy.context.scene.collection.objects.link(screen)
    _set(screen, visible_shadow=False)
    turn = Matrix.Rotation(PHONE_TURN, 4, "Z")
    for obj in (*parts, screen):
        obj.rotation_euler = (0.0, 0.0, PHONE_TURN)
        dx, dy = obj.get("offset", (0.0, 0.0))
        obj.location = PHONE_AT + turn @ Vector((dx, dy, 0.0))

    def at(px, py):
        return PHONE_AT + turn @ Vector(((px / screen_px[0] - 0.5) * w, (0.5 - py / screen_px[1]) * h, z))
    return at


def add_props():
    """A child's things beside the phone: wooden blocks in the game's own colours to the left, stacked two
    high, and a fat crayon to the lower right."""
    blocks = [("#6C5CE7", (3.7, 2.6), 14.0, 0.0), ("#FFC107", (5.1, 1.4), -9.0, 0.0), ("#138A7C", (3.9, 0.6), 4.0, 0.0),
              ("#C24E70", (3.9, 1.7), 22.0, 1.0)]
    for i, (colour, (x, y), turn, level) in enumerate(blocks):
        size = 1.15
        block = rounded_slab(f"Block {i}", size, size, 0.12, level * size, level * size + size, segments=4)
        block.data.materials.append(plain(f"Block Paint {i}", colour, 0.55, 0.25))
        block.location = Vector((x, y, 0.0))
        block.rotation_euler = (0.0, 0.0, math.radians(turn))
    bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=0.2, depth=3.2, location=(0, 0, 0))
    crayon = bpy.context.active_object
    crayon.name = "Crayon"
    crayon.data.materials.append(plain("Crayon Wax", "#E0533D", 0.5))
    bpy.ops.mesh.primitive_cone_add(vertices=12, radius1=0.2, radius2=0.05, depth=0.5, location=(0, 0, 1.85))
    tip = bpy.context.active_object
    tip.name = "Crayon Tip"
    tip.data.materials.append(plain("Crayon Wax", "#E0533D", 0.5))
    tip.parent = crayon
    crayon.rotation_euler = (math.radians(90.0), 0.0, math.radians(62.0))
    crayon.location = Vector((12.6, -3.6, 0.2))


def fit(cam, points, view, rect):
    """Place the camera so that the points fill the rect of the upright frame (shares from the bottom-left).
    Blender's lens shift is a share of the frame's LONGER side, so a sideways shift is scaled by width / height."""
    from bpy_extras.object_utils import world_to_camera_view
    scene = bpy.context.scene
    centre = sum(points, Vector()) / len(points)
    x0, y0, x1, y1 = rect
    rx, ry = scene.render.resolution_x, scene.render.resolution_y
    longer = max(rx, ry)
    shift = [0.0, 0.0]

    def spans(distance):
        place(cam, centre, view, distance, shift)
        bpy.context.view_layer.update()
        pts = [world_to_camera_view(scene, cam, p) for p in points]
        xs, ys = [p[0] for p in pts], [p[1] for p in pts]
        return min(xs), max(xs), min(ys), max(ys)

    far = 500.0
    for _ in range(6):
        near, far = 0.5, 500.0
        for _ in range(42):
            mid = (near + far) / 2
            a, b, c, d = spans(mid)
            if b - a <= x1 - x0 and d - c <= y1 - y0:
                far = mid
            else:
                near = mid
        a, b, c, d = spans(far)
        shift[0] += ((a + b) / 2 - (x0 + x1) / 2) * rx / longer
        shift[1] += ((c + d) / 2 - (y0 + y1) / 2) * ry / longer
    return centre, far, tuple(shift)


def build(times, track, preview=False):
    scene = reset_and_render_settings(preview)
    world_light()
    add_desk()
    add_lights()
    add_props()
    at = add_phone(track, times["screen_px"])
    data = bpy.data.cameras.new("Camera")
    data.lens, data.sensor_fit = LENS, "AUTO"
    cam = bpy.data.objects.new("Camera", data)
    scene.collection.objects.link(cam)
    scene.camera = cam
    cam.data.dof.use_dof = True
    cam.data.dof.aperture_fstop = 4.0 if preview else 2.8

    # The camera's places: each a box of the screen's picture (pixels; past the picture is the desk) and a
    # view (elevation, azimuth), at a time. Between two, it eases from one to the next: never still.
    shots = []
    for t, box, view in times["shots"]:
        x0, y0, x1, y1 = box
        points = [at(x, y) for x in (x0, x1) for y in (y0, y1)]
        centre, distance, shift = fit(cam, points, tuple(view), ON_PHONE)
        shots.append((t, centre, tuple(view), distance, shift))
    first, last = 1, frame_at(times["total"])
    scene.frame_start, scene.frame_end = first, last

    def lerp(a, b, u):
        return a + (b - a) * u

    for f in range(first, last + 1):
        t = (f - 1) / FPS
        k = max([0] + [i for i, s in enumerate(shots) if s[0] <= t])
        a, b = shots[k], shots[min(k + 1, len(shots) - 1)]
        u = smoother((t - a[0]) / max(0.001, b[0] - a[0])) if b is not a else 0.0
        centre = a[1].lerp(b[1], u)
        view = (lerp(a[2][0], b[2][0], u), lerp(a[2][1], b[2][1], u))
        distance = math.exp(lerp(math.log(a[3]), math.log(b[3]), u))
        shift = (lerp(a[4][0], b[4][0], u), lerp(a[4][1], b[4][1], u))
        place(cam, centre, view, distance, shift)
        cam.data.dof.focus_distance = distance
        cam.keyframe_insert("location", frame=f)
        cam.keyframe_insert("rotation_euler", frame=f)
        cam.data.keyframe_insert("shift_x", frame=f)
        cam.data.keyframe_insert("shift_y", frame=f)
        cam.data.dof.keyframe_insert("focus_distance", frame=f)
    return scene


def render(scene, out, stills, frames):
    out.mkdir(parents=True, exist_ok=True)
    if stills:
        for t in stills:
            scene.frame_set(frame_at(t))
            scene.render.filepath = str(out / f"still_{t:06.2f}.jpg")
            bpy.ops.render.render(write_still=True)
        return
    if frames:
        scene.frame_start, scene.frame_end = frames
    scene.render.use_overwrite = False      # a batch run again keeps the frames it already wrote
    scene.render.filepath = str(out / "f")
    bpy.ops.render.render(animation=True)


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    ap = argparse.ArgumentParser(prog="insta_scene.py")
    ap.add_argument("--times", required=True)
    ap.add_argument("--track", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--preview", action="store_true")
    ap.add_argument("--stills")
    ap.add_argument("--frames")
    args = ap.parse_args(argv)
    times = json.loads(Path(args.times).read_text(encoding="utf-8"))
    scene = build(times, args.track, args.preview)
    render(scene, Path(args.out), [float(s) for s in args.stills.split(",")] if args.stills else None,
           [int(v) for v in args.frames.split("-")] if args.frames else None)
    print(f"insta scene: done -> {args.out}")
