"""The Instagram reel's set, in Blender 5.2 (EEVEE): the game's own studio, not a borrowed desk.

The owner, 26 Nov 2026, of the first two cuts (a phone on a wooden desk, as his Glym promos were): "the
vocabulary app's details I had given was not for you to replicate (the wooden background) but to be
inspired and make better than that". So the set is the game's own world:

  - a deep violet studio in the game's colours: a glowing backdrop, a dark glossy floor that mirrors the
    phone, and soft lights in the four colours of the game's groups, far behind and out of focus;
  - the phone stands upright in the light, the real game playing on it (insta_game_test.dart's frames);
  - the opening: the sixteen real pictures of the first set float as cards in front of the phone, then
    fly into it and land where the game shows them, as the screen wakes;
  - the close: the phone slides away and his web grows in 3D behind it, knot by knot, each knot one of
    his own pictures, joined by threads of light in the colours of their branches: the "threads of
    light" of the owner's TARGET_UI.md, and the very web the game drew for him in the film.

One camera, never still. Words go over the frames afterwards (insta_make.py). The scene is built from
nothing on every run; no .blend is kept.

    blender -b --factory-startup -P tools/insta/insta_scene.py -- \\
        --times tools/insta/out/times.json --track tools/insta/out/track --out DIR [--stills 2,12] [--frames 1-120] [--preview]
"""
import argparse
import json
import math
import random
import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Matrix, Vector

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE))
import insta_web  # noqa: E402  his web's layout, shared with insta_make.py (its sounds)
FPS, W, H = 30, 1080, 1920
LENS = 70
ON_PHONE = (0.08, 0.08, 0.92, 0.70)      # where the subject sits in the upright frame, under the words
ON_WEB = (0.03, 0.10, 0.97, 0.72)
SCREEN_W = 3.1
BEZEL, BODY_R, BODY_T = 0.13, 0.5, 0.26
PHONE_C = Vector((0.0, 0.0, 0.0))
PHONE_TURN = math.radians(-7.0)
FLOOR_Z = -3.75
WEB_Y = 4.0                              # the web's plane, behind the phone
BRANCH = ["#6C5CE7", "#138A7C", "#E39A1D", "#D2557E", "#3F8FE0", "#7DBA3A"]
INK = "#2D3436"


# ------------------------------------------------------------------ helpers

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


def material(name, colour="#FFFFFF", roughness=0.5, emission=None, strength=0.0, metallic=0.0, specular=0.4):
    mat = bpy.data.materials.new(name)
    if mat.node_tree is None:
        mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = linear(colour)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Specular IOR Level"].default_value = specular
    if emission:
        bsdf.inputs["Emission Color"].default_value = linear(emission)
        bsdf.inputs["Emission Strength"].default_value = strength
    return mat


def picture_material(name, path):
    """A picture of the game's on white, as on its tiles: the image over white by its alpha. Lit softly
    from within, so it reads as the game's own bright picture whatever the light."""
    mat = bpy.data.materials.new(name)
    if mat.node_tree is None:
        mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    bsdf = nodes["Principled BSDF"]
    tex = nodes.new("ShaderNodeTexImage")
    tex.image = bpy.data.images.load(str(path), check_existing=True)
    tex.interpolation = "Cubic"
    mix = nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    mix.inputs["A"].default_value = (1.0, 1.0, 1.0, 1.0)
    links.new(tex.outputs["Alpha"], mix.inputs["Factor"])
    links.new(tex.outputs["Color"], mix.inputs["B"])
    links.new(mix.outputs["Result"], bsdf.inputs["Base Color"])
    links.new(mix.outputs["Result"], bsdf.inputs["Emission Color"])
    bsdf.inputs["Emission Strength"].default_value = 0.6
    bsdf.inputs["Roughness"].default_value = 0.45
    return mat


def rounded_outline(w, h, r, segments=12):
    pts = []
    for cx, cy, start in ((w / 2 - r, h / 2 - r, 0), (-w / 2 + r, h / 2 - r, 90), (-w / 2 + r, -h / 2 + r, 180),
                          (w / 2 - r, -h / 2 + r, 270)):
        for i in range(segments + 1):
            a = math.radians(start + 90 * i / segments)
            pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts


def rounded_slab(name, w, h, r, z0, z1, segments=12):
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


def flat_face(name, outline, z, uv_of):
    """A flat face in an object's own XY plane at height z, from an outline, with its UVs."""
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata([(x, y, z) for x, y in outline], [], [list(range(len(outline)))])
    uv = mesh.uv_layers.new(name="UVMap")
    for loop_index in mesh.polygons[0].loop_indices:
        x, y, _ = mesh.vertices[mesh.loops[loop_index].vertex_index].co
        uv.data[loop_index].uv = uv_of(x, y)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def label(name, text, size, colour, strength=0.0):
    font_file = next((HERE / "out/fonts").glob("Quicksand_700_*.ttf"), None)
    curve = bpy.data.curves.new(name, "FONT")
    curve.body = text
    curve.size = size
    curve.align_x, curve.align_y = "CENTER", "CENTER"
    if font_file:
        curve.font = bpy.data.fonts.load(str(font_file), check_existing=True)
    obj = bpy.data.objects.new(name, curve)
    bpy.context.scene.collection.objects.link(obj)
    obj.data.materials.append(material(name + " Ink", colour, 0.6, emission=colour if strength else None, strength=strength))
    return obj


def smoother(u):
    u = min(1.0, max(0.0, u))
    return u * u * u * (u * (6 * u - 15) + 10)


def ease_out_back(u, s=1.6):
    u = min(1.0, max(0.0, u)) - 1
    return 1 + u * u * ((s + 1) * u + s)


def frame_at(t):
    return round(t * FPS) + 1


def direction(elevation, azimuth):
    el, az = math.radians(elevation), math.radians(azimuth)
    return Vector((math.sin(az) * math.cos(el), -math.cos(az) * math.cos(el), math.sin(el)))


def place(cam, centre, view, distance, shift):
    cam.location = Vector(centre) + direction(*view) * distance
    look_at(cam, centre)
    cam.data.shift_x, cam.data.shift_y = shift


# ------------------------------------------------------------------ the studio

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
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    _set(scene.eevee, taa_render_samples=16 if preview else 64, use_raytracing=True, use_shadows=True,
         shadow_ray_count=3, shadow_step_count=12, use_fast_gi=True, fast_gi_method="GLOBAL_ILLUMINATION")
    _set(scene.eevee.ray_tracing_options, resolution_scale="1", trace_max_roughness=0.5)
    return scene


def world():
    w = bpy.data.worlds.new("Studio")
    bpy.context.scene.world = w
    w.use_nodes = True
    nodes = w.node_tree.nodes
    back = nodes["Background"]
    back.inputs["Color"].default_value = linear("#1A1240")
    back.inputs["Strength"].default_value = 0.35


def backdrop():
    """A glowing violet wall far behind, lighter in its middle; a dark glossy floor that mirrors the phone."""
    mesh = bpy.data.meshes.new("Backdrop")
    s, z0, z1 = 140.0, FLOOR_Z - 1, 110.0
    mesh.from_pydata([(-s, 60, z0), (s, 60, z0), (s, 60, z1), (-s, 60, z1)], [], [(0, 1, 2, 3)])
    mesh.uv_layers.new(name="UVMap")
    wall = bpy.data.objects.new("Backdrop", mesh)
    bpy.context.scene.collection.objects.link(wall)
    mat = bpy.data.materials.new("Backdrop Glow")
    if mat.node_tree is None:
        mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    for n in list(nodes):
        if n.type != "OUTPUT_MATERIAL":
            nodes.remove(n)
    coord = nodes.new("ShaderNodeTexCoord")
    mapping = nodes.new("ShaderNodeMapping")
    mapping.inputs["Location"].default_value = (-0.5, -0.25, 0.0)
    mapping.inputs["Scale"].default_value = (1.7, 2.3, 1.0)
    grad = nodes.new("ShaderNodeTexGradient")
    grad.gradient_type = "QUADRATIC_SPHERE"
    ramp = nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].color = linear("#120C33")
    ramp.color_ramp.elements[1].color = linear("#6B54E8")
    ramp.color_ramp.elements[1].position = 0.85
    emit = nodes.new("ShaderNodeEmission")
    emit.inputs["Strength"].default_value = 1.0
    links.new(coord.outputs["Generated"], mapping.inputs["Vector"])
    links.new(mapping.outputs["Vector"], grad.inputs["Vector"])
    links.new(grad.outputs["Fac"], ramp.inputs["Fac"])
    links.new(ramp.outputs["Color"], emit.inputs["Color"])
    links.new(emit.outputs["Emission"], nodes["Material Output"].inputs["Surface"])
    wall.data.materials.append(mat)

    floor_mesh = bpy.data.meshes.new("Floor")
    f = 200.0
    floor_mesh.from_pydata([(-f, -f, FLOOR_Z), (f, -f, FLOOR_Z), (f, 60, FLOOR_Z), (-f, 60, FLOOR_Z)], [], [(0, 1, 2, 3)])
    floor = bpy.data.objects.new("Floor", floor_mesh)
    bpy.context.scene.collection.objects.link(floor)
    floor.data.materials.append(material("Floor Gloss", "#1C1540", 0.34, specular=0.45))


def bokeh(seed=7):
    """Soft lights in the four colours of the game's groups, far behind: out of focus, they are round glows."""
    rng = random.Random(seed)
    mats = [material(f"Glow {c}", c, 0.5, emission=c, strength=5.0) for c in ("#8E7CFF", "#FFC94A", "#2CC4AE", "#FF7AA8")]
    for i in range(36):
        bpy.ops.mesh.primitive_uv_sphere_add(segments=16, ring_count=8, radius=rng.uniform(0.1, 0.24),
                                             location=(rng.uniform(-30, 30), rng.uniform(22, 50), rng.uniform(4.0, 30)))
        orb = bpy.context.active_object
        orb.name = f"Orb {i}"
        orb.data.materials.append(mats[i % len(mats)])
        _set(orb, visible_shadow=False)


def lights():
    def area(name, location, size, energy, colour, target):
        data = bpy.data.lights.new(name, "AREA")
        data.shape, data.size, data.energy, data.color = "DISK", size, energy, colour
        obj = bpy.data.objects.new(name, data)
        obj.location = location
        bpy.context.scene.collection.objects.link(obj)
        look_at(obj, target)
        return obj
    area("Key", (-9.0, -13.0, 9.0), 9.0, 2600.0, (1.0, 0.93, 0.86), PHONE_C)
    # the fill and the two rims light the phone's edges, and are not seen mirrored in the floor
    for light in (area("Fill", (11.0, -9.0, 2.0), 10.0, 900.0, (0.82, 0.88, 1.0), PHONE_C),
                  area("Rim Violet", (-5.0, 7.0, 6.0), 5.0, 1800.0, (0.62, 0.45, 1.0), PHONE_C),
                  area("Rim Amber", (6.0, 6.0, -1.0), 5.0, 1100.0, (1.0, 0.72, 0.35), PHONE_C)):
        _set(light.data, specular_factor=0.0)


# ------------------------------------------------------------------ the phone, standing

class Phone:
    """An upright phone facing the camera (-Y), turned a little; the game's film on its screen."""

    def __init__(self, track, screen_px):
        self.sw, self.sh = screen_px
        self.w = SCREEN_W
        self.h = SCREEN_W * self.sh / self.sw
        self.turn = Matrix.Rotation(PHONE_TURN, 4, "Z")
        w, h = self.w, self.h
        self.parts = []
        body = rounded_slab("Phone", w + 2 * BEZEL, h + 2 * BEZEL, BODY_R, 0.0, BODY_T)
        body.data.materials.append(material("Phone Body", "#101114", 0.28, metallic=0.4))
        frame = rounded_slab("Phone Frame", w + 2 * BEZEL + 0.05, h + 2 * BEZEL + 0.05, BODY_R + 0.025, 0.05, BODY_T - 0.05)
        frame.data.materials.append(material("Phone Edge", "#B9B2D6", 0.22, metallic=0.9))
        self.parts += [body, frame]
        for name, side, y, length in (("Power", 1, 0.9, 0.95), ("Volume Up", -1, 1.35, 0.6), ("Volume Down", -1, 0.55, 0.6)):
            b = rounded_slab(name, 0.05, length, 0.024, 0.08, BODY_T - 0.08, segments=4)
            b.data.materials.append(material(name + " Metal", "#B9B2D6", 0.25, metallic=0.9))
            b["offset"] = (side * (w / 2 + BEZEL + 0.035), y)
            self.parts.append(b)
        for obj in self.parts:
            dx, dy = obj.get("offset", (0.0, 0.0))
            obj.rotation_euler = (math.radians(90.0), 0.0, PHONE_TURN)
            obj.location = PHONE_C + self.turn @ Vector((dx, 0.0, dy))
        outline = rounded_outline(w, h, BODY_R - BEZEL, 14)
        mesh = bpy.data.meshes.new("Phone Screen")
        mesh.from_pydata([(x, -BODY_T - 0.004, z) for x, z in outline], [], [list(range(len(outline)))])
        uv = mesh.uv_layers.new(name="UVMap")
        for loop_index in mesh.polygons[0].loop_indices:
            x, _, z = mesh.vertices[mesh.loops[loop_index].vertex_index].co
            uv.data[loop_index].uv = (x / w + 0.5, z / h + 0.5)
        self.screen_mat = self._track_material(track)
        mesh.materials.append(self.screen_mat)
        screen = bpy.data.objects.new("Phone Screen", mesh)
        bpy.context.scene.collection.objects.link(screen)
        _set(screen, visible_shadow=False)
        screen.rotation_euler = (0.0, 0.0, PHONE_TURN)
        screen.location = PHONE_C
        self.screen = screen
        self.forward = self.turn @ Vector((0.0, -1.0, 0.0))

    def _track_material(self, track):
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
        bsdf.inputs["Roughness"].default_value = 0.08     # glass: the lights show a little in it
        bsdf.inputs["Specular IOR Level"].default_value = 0.4
        return mat

    def at(self, px, py, lift=0.0):
        """A point of the screen's picture (track pixels) in the world; past its edge, the air around it."""
        local = Vector(((px / self.sw - 0.5) * self.w, -BODY_T - 0.004 - lift, (0.5 - py / self.sh) * self.h))
        return PHONE_C + self.turn @ local

    def units(self, px):
        return px * self.w / self.sw

    def screen_strength(self, keys):
        """The screen's brightness at times: dim while the pictures are still in the air."""
        socket = self.screen_mat.node_tree.nodes["Principled BSDF"].inputs["Emission Strength"]
        for t, v in keys:
            socket.default_value = v
            socket.keyframe_insert("default_value", frame=frame_at(t))

    def slide_away(self, t0, t1):
        """Down and away, so his web behind it is seen whole."""
        for obj in self.parts + [self.screen]:
            obj.keyframe_insert("location", frame=frame_at(t0))
            obj.location = obj.location + Vector((0.0, -1.5, -9.5))
            obj.keyframe_insert("location", frame=frame_at(t1))


# ------------------------------------------------------------------ the opening: the sixteen pictures

def opening(phone, tiles, land_from, land_to):
    """The sixteen real pictures of the first set, as cards in the air in front of the phone, a little
    larger and turned this way and that; then each flies into the phone and lands on its own tile, in
    turn, and goes as it lands: the screen, waking, shows it there."""
    rng = random.Random(3)
    order = sorted(range(len(tiles)), key=lambda i: (tiles[i]["rect"][1], tiles[i]["rect"][0]))
    span = max(0.01, land_to - land_from - 0.55)
    centre_px = (phone.sw / 2, sum(t["rect"][1] + t["rect"][3] for t in tiles) / (2 * len(tiles)))
    for k, i in enumerate(order):
        t = tiles[i]
        x0, y0, x1, y1 = t["rect"]
        tw, th = phone.units(x1 - x0), phone.units(y1 - y0)
        card = rounded_slab(f"Card {t['id']}", tw, th, 0.09 * tw, 0.0, 0.05)
        card.data.materials.append(material(f"Card {t['id']}", "#FFFFFF", 0.45, emission="#FFFFFF", strength=0.08))
        side = min(0.74 * tw, 0.66 * th)
        pic_y = th / 2 - 0.07 * th - side / 2
        pic = flat_face(f"Card {t['id']} Picture", rounded_outline(side, side, 0.06 * side, 6), 0.052,
                        lambda x, y, s=side, py=0.0: (x / s + 0.5, y / s + 0.5))
        pic.location = (0.0, pic_y, 0.0)
        pic.parent = card
        path = ROOT / f"Assets/pictures/{t['id']}.webp"
        pic.data.materials.append(picture_material(f"Pic {t['id']}", path) if path.exists() else material("Blank"))
        words = label(f"Card {t['id']} Name", t["label"], 0.105 * tw, INK)
        words.location = (0.0, -th / 2 + 0.13 * th, 0.053)
        words.parent = card
        # where it lands: on its tile; where it floats: further out toward the camera, the grid spread wider
        cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
        landed = phone.at(cx, cy, lift=0.05)
        spread = phone.at(centre_px[0] + (cx - centre_px[0]) * 1.32, centre_px[1] + (cy - centre_px[1]) * 1.22, lift=4.2)
        tilt = Vector((math.radians(rng.uniform(-16, 16)), math.radians(rng.uniform(-22, 22)), math.radians(rng.uniform(-14, 14))))
        bob = rng.uniform(0, math.tau)
        start = land_from + span * k / max(1, len(order) - 1)
        end = start + 0.55
        base_rot = Vector((math.radians(90.0), 0.0, PHONE_TURN))
        for f in range(1, frame_at(end) + 1):
            tt = (f - 1) / FPS
            if tt < start:
                drift = Vector((0.05 * math.sin(bob + tt * 1.7), 0.0, 0.07 * math.sin(bob * 1.3 + tt * 2.1)))
                card.location = spread + phone.turn @ drift
                wobble = 0.12 * math.sin(bob + tt * 1.4)
                card.rotation_euler = base_rot + tilt * (1.0 + wobble)
            else:
                u = smoother((tt - start) / (end - start))
                arc = Vector((0.0, 0.0, 0.6 * math.sin(math.pi * u)))
                card.location = spread.lerp(landed, u) + arc
                card.rotation_euler = base_rot + tilt * (1 - u)
            card.keyframe_insert("location", frame=f)
            card.keyframe_insert("rotation_euler", frame=f)
        for obj in (card, pic, words):
            obj.hide_render = False
            obj.keyframe_insert("hide_render", frame=1)
            obj.hide_render = True
            obj.keyframe_insert("hide_render", frame=frame_at(end) + 1)
    # the curves of hide_render must step, not ease
    for action in bpy.data.actions:
        for curve in _fcurves(action):
            if curve.data_path == "hide_render":
                for key in curve.keyframe_points:
                    key.interpolation = "CONSTANT"


def _fcurves(action):
    """Blender 5's layered actions keep their curves in channel bags; older ones on the action."""
    if hasattr(action, "fcurves") and action.fcurves:
        return list(action.fcurves)
    out = []
    for layer in getattr(action, "layers", []):
        for strip in layer.strips:
            for bag in getattr(strip, "channelbags", []):
                out += list(bag.fcurves)
    return out


# ------------------------------------------------------------------ the close: his web, in 3D

def web(times):
    nodes = times["web"]
    if not nodes:
        return None
    angle, depth, branch = insta_web.layout(nodes)
    deepest = max(depth.values()) or 1
    ring = 9.8 / deepest
    # high enough that its lowest ring stands clear of the floor, which mirrors it
    centre = Vector((PHONE_C.x, WEB_Y, FLOOR_Z + ring * deepest + 2.2))

    def where(i):
        r = ring * depth[i]
        # the plane faces the camera: x across, z up; angle 0 at the top, going clockwise
        return centre + Vector((r * math.cos(angle[i] - math.pi / 2 + math.pi), 0.0, -r * math.sin(angle[i] - math.pi / 2 + math.pi)))

    appear = insta_web.appear_times(nodes, times["web_from"], times["web_to"])
    knots = {}
    for n in nodes:
        i = n["id"]
        colour = "#FFC94A" if i == "seed" else BRANCH[branch[i] % len(BRANCH)]
        r = 0.95 if i == "seed" else max(0.46, 0.84 - 0.1 * (depth[i] - 1))
        bpy.ops.mesh.primitive_cylinder_add(vertices=48, radius=r, depth=0.12, location=where(i), rotation=(math.radians(90), 0, 0))
        disc = bpy.context.active_object
        disc.name = f"Knot {i}"
        disc.data.materials.append(material(f"Knot {i}", "#FFFFFF", 0.4, emission="#FFFFFF", strength=0.15))
        bpy.ops.mesh.primitive_torus_add(major_radius=r * 1.06, minor_radius=r * 0.1, major_segments=48, minor_segments=10,
                                         location=(0, 0, 0))
        rim = bpy.context.active_object
        rim.name = f"Knot {i} Rim"
        rim.data.materials.append(material(f"Rim {i}", colour, 0.3, emission=colour, strength=4.0))
        rim.parent = disc
        rim.location = (0, 0, 0)
        if i == "seed":
            bpy.ops.mesh.primitive_uv_sphere_add(radius=r * 0.55, location=(0, 0, 0))
            star = bpy.context.active_object
            star.name = "Seed Glow"
            star.data.materials.append(material("Seed Glow", "#FFC94A", 0.3, emission="#FFC94A", strength=8.0))
            star.parent = disc
            star.location = (0, 0.0, -0.1)
        elif n.get("picture"):
            path = ROOT / n["picture"]
            circle = [(r * 0.86 * math.cos(math.tau * k / 40), r * 0.86 * math.sin(math.tau * k / 40)) for k in range(40)]
            face = flat_face(f"Knot {i} Picture", circle, 0.0, lambda x, y, rr=r * 0.86: (x / (2 * rr) + 0.5, y / (2 * rr) + 0.5))
            face.data.materials.append(picture_material(f"Knot Pic {i}", path) if path.exists() else material("Blank"))
            face.parent = disc
            face.location = (0, 0, 0.065)
        if i == "seed" or depth.get(i) == 1:
            words = label(f"Knot {i} Name", n["label"], 0.34 if i != "seed" else 0.4, "#FFFFFF", strength=2.0)
            words.parent = disc
            words.rotation_euler = (0, 0, 0)
            words.location = (0, -r - 0.42, 0.08)
        knots[i] = disc
        # it comes in: from nothing, a little past its size, then settles
        a = appear[i]
        for f in range(frame_at(a - 0.05), frame_at(a + 0.45) + 1):
            u = ((f - 1) / FPS - a) / 0.4
            s = max(0.0001, ease_out_back(u) if u > 0 else 0.0001)
            disc.scale = (s, s, s)
            disc.keyframe_insert("scale", frame=f)
        disc.scale = (0.0001, 0.0001, 0.0001)
        disc.keyframe_insert("scale", frame=1)
    # threads of light: from each knot to the set it was found in, curving with the ring, in its branch's colour
    for n in nodes:
        i, p = n["id"], n["parent"]
        if not p or p not in knots:
            continue
        colour = BRANCH[branch[i] % len(BRANCH)]
        a, b = where(p), where(i)
        bend = centre + (b - centre).normalized() * ((a - centre).length + (b - centre).length) / 2 if p != "seed" else (a + b) / 2
        curve = bpy.data.curves.new(f"Thread {i}", "CURVE")
        curve.dimensions = "3D"
        curve.bevel_depth = 0.045
        curve.bevel_resolution = 3
        spline = curve.splines.new("BEZIER")
        spline.bezier_points.add(1)
        p0, p1 = spline.bezier_points
        p0.co, p1.co = a, b
        p0.handle_left = p0.co
        p0.handle_right = a.lerp(bend, 0.66)
        p1.handle_left = b.lerp(bend, 0.66)
        p1.handle_right = p1.co
        thread = bpy.data.objects.new(f"Thread {i}", curve)
        bpy.context.scene.collection.objects.link(thread)
        thread.data.materials.append(material(f"Thread {i}", colour, 0.3, emission=colour, strength=3.2))
        _set(thread, visible_shadow=False)
        start = appear[i] - 0.32
        curve.bevel_factor_end = 0.0
        curve.keyframe_insert("bevel_factor_end", frame=1)
        curve.keyframe_insert("bevel_factor_end", frame=frame_at(start))
        curve.bevel_factor_end = 1.0
        curve.keyframe_insert("bevel_factor_end", frame=frame_at(start + 0.32))
        if n.get("also"):   # a place where circles cross: a fainter thread to the other circle it lies in
            for other in n["also"]:
                if other in knots:
                    faint = bpy.data.curves.new(f"Also {i} {other}", "CURVE")
                    faint.dimensions, faint.bevel_depth = "3D", 0.02
                    sp = faint.splines.new("POLY")
                    sp.points.add(1)
                    sp.points[0].co = (*where(other), 1.0)
                    sp.points[1].co = (*where(i), 1.0)
                    fo = bpy.data.objects.new(f"Also {i} {other}", faint)
                    bpy.context.scene.collection.objects.link(fo)
                    fo.data.materials.append(material(f"Also {i}", "#FFE29A", 0.3, emission="#FFE29A", strength=1.6))
                    faint.bevel_factor_end = 0.0
                    faint.keyframe_insert("bevel_factor_end", frame=frame_at(times["web_to"]))
                    faint.bevel_factor_end = 1.0
                    faint.keyframe_insert("bevel_factor_end", frame=frame_at(times["web_to"] + 0.6))
    return centre, ring * deepest


# ------------------------------------------------------------------ the camera

def fit(cam, points, view, rect):
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
    world()
    backdrop()
    bokeh()
    lights()
    phone = Phone(track, times["screen_px"])
    opening(phone, times["tiles"], times["land_from"], times["land_to"])
    phone.screen_strength([(0.0, 0.18), (times["land_from"] + 0.4, 0.18), (times["land_to"] + 0.1, 1.0)])
    web_centre, web_r = web(times) or (PHONE_C, 1.0)
    phone.slide_away(times["web_slide"], times["web_slide"] + 1.3)

    data = bpy.data.cameras.new("Camera")
    data.lens, data.sensor_fit = LENS, "AUTO"
    cam = bpy.data.objects.new("Camera", data)
    scene.collection.objects.link(cam)
    scene.camera = cam
    cam.data.dof.use_dof = True
    cam.data.dof.aperture_fstop = 3.2 if not preview else 4.5
    cam.data.clip_end = 400.0

    shots = []
    for t, box, view in times["shots"]:
        if isinstance(box, dict):           # a box of his web's plane, in shares of its radius
            x0, z0, x1, z1 = box["web"]
            pts = [web_centre + Vector((x * web_r, 0.0, z * web_r)) for x in (x0, x1) for z in (z0, z1)]
            rect = ON_WEB
        else:
            x0, y0, x1, y1 = box
            pts = [phone.at(x, y) for x in (x0, x1) for y in (y0, y1)]
            rect = ON_PHONE
        centre, distance, shift = fit(cam, pts, tuple(view), rect)
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
        focus = distance
        if t < times["land_to"]:        # the cards in the air are nearer: focus on them until they land
            v = smoother((t - times["land_from"]) / max(0.01, times["land_to"] - times["land_from"]))
            focus = lerp(distance - 3.6, distance, v)
        cam.data.dof.focus_distance = focus
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
    scene.render.use_overwrite = False
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
