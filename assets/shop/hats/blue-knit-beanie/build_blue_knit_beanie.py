import bpy
import math
import random
from mathutils import Vector


OUT_DIR = r"E:\roblox\BubblePopWorld\assets\shop\hats\blue-knit-beanie"
random.seed(2408)


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for datablocks in (bpy.data.meshes, bpy.data.curves, bpy.data.materials, bpy.data.cameras, bpy.data.lights):
        pass


def material(name, base, roughness=0.55, metallic=0.0):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*base, 1.0)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*base, 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    return mat


BLUE = material("Premium cobalt-blue wool", (0.006, 0.105, 0.62), 0.76)
BLUE_DARK = material("Deep blue stitches", (0.006, 0.055, 0.30), 0.82)
WHITE = material("Soft ivory pompom", (0.94, 0.92, 0.85), 0.96)
WHITE_SHADOW = material("Pompom strand shadow", (0.66, 0.65, 0.61), 1.0)


def smooth(obj, level=2):
    if obj.type == "MESH":
        for p in obj.data.polygons:
            p.use_smooth = True
        if level:
            mod = obj.modifiers.new("Subdivision polish", "SUBSURF")
            mod.levels = level
            mod.render_levels = level


def uv_sphere(name, loc, scale, mat, segments=64, rings=32):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=rings, location=loc)
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(mat)
    smooth(obj, 1)
    return obj


def curve_tube(name, points, radius, mat, resolution=2):
    crv = bpy.data.curves.new(name, "CURVE")
    crv.dimensions = "3D"
    crv.resolution_u = resolution
    crv.bevel_depth = radius
    crv.bevel_resolution = 3
    spline = crv.splines.new("BEZIER")
    spline.bezier_points.add(len(points) - 1)
    for bp, co in zip(spline.bezier_points, points):
        bp.co = co
        bp.handle_left_type = "AUTO"
        bp.handle_right_type = "AUTO"
    obj = bpy.data.objects.new(name, crv)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(mat)
    return obj


def add_hat_body():
    # Rounded underlying silhouette, extending slightly into the cuff.
    body_center_z = 1.22
    body_radius_xy = 1.18
    body_radius_z = 1.30
    body = uv_sphere("Knitted beanie body", (0, 0, body_center_z), (body_radius_xy, 1.12, body_radius_z), BLUE, 72, 40)

    # Hide the lower half with a premium, thick folded cuff.
    bpy.ops.mesh.primitive_cylinder_add(vertices=96, radius=1.34, depth=0.70, location=(0, 0, 0.54))
    cuff = bpy.context.object
    cuff.name = "Thick folded cuff"
    cuff.scale = (1.03, 0.98, 1.0)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    cuff.data.materials.append(BLUE)
    bevel = cuff.modifiers.new("Soft cuff edges", "BEVEL")
    bevel.width = 0.14
    bevel.segments = 5
    smooth(cuff, 1)

    # Crown cable-knit ribs. Each braid is two intertwined raised yarn cords.
    ribs = 18
    for i in range(ribs):
        theta = 2 * math.pi * i / ribs
        for strand in (-1, 1):
            pts = []
            steps = 34
            for j in range(steps):
                t = j / (steps - 1)
                z = 0.82 + 1.62 * t
                normalized_z = (z - body_center_z) / body_radius_z
                profile = math.sqrt(max(0.035, 1.0 - normalized_z * normalized_z))
                radius = body_radius_xy * profile + 0.075
                twist = strand * 0.045 * math.sin(t * math.pi * 9.0)
                a = theta + twist
                pts.append((radius * math.cos(a), radius * math.sin(a), z))
            curve_tube(f"Crown braid {i:02d}-{strand:+d}", pts, 0.068, BLUE)

    # Dark recessed stitches accentuate the knit pattern without painted lines.
    for i in range(ribs):
        theta = 2 * math.pi * (i + 0.5) / ribs
        pts = []
        for j in range(25):
            t = j / 24
            z = 0.83 + 1.56 * t
            normalized_z = (z - body_center_z) / body_radius_z
            radius = body_radius_xy * math.sqrt(max(0.04, 1.0 - normalized_z * normalized_z)) + 0.045
            pts.append((radius * math.cos(theta), radius * math.sin(theta), z))
        curve_tube(f"Crown recessed stitch {i:02d}", pts, 0.018, BLUE_DARK)

    # Cuff vertical knit loops and top/bottom seam piping.
    for i in range(38):
        theta = 2 * math.pi * i / 38
        tangent = Vector((-math.sin(theta), math.cos(theta), 0))
        radial = Vector((math.cos(theta), math.sin(theta), 0))
        center = radial * 1.392
        pts = []
        for j in range(14):
            t = j / 13
            z = 0.25 + 0.62 * t
            wave = 0.032 * math.sin(t * math.pi * 4)
            p = center + tangent * wave
            pts.append((p.x, p.y, z))
        curve_tube(f"Cuff knit loop {i:02d}", pts, 0.035, BLUE)

    for z in (0.24, 0.86):
        pts = []
        for j in range(65):
            a = 2 * math.pi * j / 64
            pts.append((1.31 * math.cos(a), 1.31 * math.sin(a), z))
        curve_tube(f"Cuff seam {z:.2f}", pts, 0.035, BLUE_DARK)


def add_pompom():
    center = Vector((0, 0, 2.72))
    core = uv_sphere("Pompom soft core", center, (0.46, 0.46, 0.43), WHITE, 48, 24)
    # Displace the core for an irregular soft silhouette.
    tex = bpy.data.textures.new("Fine wool irregularity", type="CLOUDS")
    tex.noise_scale = 0.11
    disp = core.modifiers.new("Soft wool breakup", "DISPLACE")
    disp.texture = tex
    disp.strength = 0.075
    disp.texture_coords = "GLOBAL"

    # Hundreds of tapered-looking wool tufts around the core.
    golden = math.pi * (3 - math.sqrt(5))
    for i in range(280):
        y = 1 - (i / 279) * 2
        r = math.sqrt(max(0, 1 - y * y))
        a = golden * i
        direction = Vector((math.cos(a) * r, math.sin(a) * r, y))
        tangent = direction.cross(Vector((0, 0, 1)))
        if tangent.length < 0.1:
            tangent = Vector((1, 0, 0))
        tangent.normalize()
        length = random.uniform(0.10, 0.24)
        start = center + direction * random.uniform(0.36, 0.43)
        mid = start + direction * length * 0.56 + tangent * random.uniform(-0.035, 0.035)
        end = start + direction * length + tangent * random.uniform(-0.055, 0.055)
        mat = WHITE if i % 7 else WHITE_SHADOW
        curve_tube(f"Pompom fiber {i:03d}", [start, mid, end], random.uniform(0.008, 0.014), mat, 1)


def add_display():
    navy = material("Display navy", (0.003, 0.018, 0.055), 0.36, 0.05)
    cyan = material("Electric cyan trim", (0.0, 0.55, 1.0), 0.22, 0.25)
    bpy.ops.mesh.primitive_cylinder_add(vertices=96, radius=1.78, depth=0.16, location=(0, 0, 0.02))
    base = bpy.context.object
    base.name = "Premium display pedestal"
    base.data.materials.append(navy)
    smooth(base, 1)
    bpy.ops.mesh.primitive_torus_add(major_radius=1.60, minor_radius=0.035, major_segments=96, minor_segments=12, location=(0, 0, 0.11))
    trim = bpy.context.object
    trim.name = "Cyan pedestal trim"
    trim.data.materials.append(cyan)


def add_lighting_and_camera():
    world = bpy.context.scene.world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.001, 0.006, 0.025, 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.20

    def area(name, loc, energy, color, size):
        bpy.ops.object.light_add(type="AREA", location=loc)
        light = bpy.context.object
        light.name = name
        light.data.energy = energy
        light.data.color = color
        light.data.shape = "DISK"
        light.data.size = size
        light.rotation_euler = (math.radians(20), 0, math.atan2(-loc[0], loc[1]))
        direction = Vector((0, 0, 1.35)) - light.location
        light.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()

    area("Large soft key", (-3.8, -4.2, 5.5), 1050, (0.60, 0.80, 1.0), 4.0)
    area("Cool rim", (3.8, 1.2, 4.1), 900, (0.08, 0.45, 1.0), 3.0)
    area("Warm pompom fill", (0.4, -1.5, 5.5), 480, (1.0, 0.86, 0.65), 2.0)

    bpy.ops.object.camera_add(location=(4.15, -6.75, 3.35))
    cam = bpy.context.object
    cam.name = "Product render camera"
    target = Vector((0, 0, 1.42))
    cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
    cam.data.lens = 58
    bpy.context.scene.camera = cam


def setup_render():
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 1024
    scene.render.resolution_y = 1024
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.filepath = OUT_DIR + r"\Blue-Knit-Beanie-Blender-Final.png"
    scene.render.film_transparent = False
    scene.render.image_settings.color_mode = "RGBA"
    scene.view_settings.look = "AgX - Medium High Contrast"
    scene.render.resolution_percentage = 100


clear_scene()
add_hat_body()
add_pompom()
add_display()
add_lighting_and_camera()
setup_render()

bpy.ops.wm.save_as_mainfile(filepath=OUT_DIR + r"\Blue-Knit-Beanie-Final.blend")

# Export a clean Roblox-ready mesh asset without the pedestal, lights, or camera.
bpy.ops.object.select_all(action="DESELECT")
for obj in bpy.context.scene.objects:
    if obj.type in {"MESH", "CURVE"} and "pedestal" not in obj.name.lower() and "trim" not in obj.name.lower():
        obj.select_set(True)
bpy.ops.wm.obj_export(filepath=OUT_DIR + r"\Blue-Knit-Beanie-Roblox.obj", export_selected_objects=True, export_materials=True)

bpy.context.scene.render.filepath = OUT_DIR + r"\Blue-Knit-Beanie-Blender-Final.png"
bpy.ops.render.render(write_still=True)
