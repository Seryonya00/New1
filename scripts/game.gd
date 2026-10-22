extends Node3D

const SHAPE_BOX := 0
const SHAPE_SPHERE := 1
const SHAPE_CYLINDER := 2
const FISH_DATA := [
    {"name": "Карась", "min_weight": 0.15, "max_weight": 1.8, "bite": 0.72, "price": 8, "xp": 12},
    {"name": "Плотва", "min_weight": 0.08, "max_weight": 0.9, "bite": 0.86, "price": 6, "xp": 9},
    {"name": "Окунь", "min_weight": 0.1, "max_weight": 1.4, "bite": 0.48, "price": 11, "xp": 15},
    {"name": "Лещ", "min_weight": 0.3, "max_weight": 4.5, "bite": 0.35, "price": 14, "xp": 22}
]

var silver := 120
var xp := 0
var level := 1
var keepnet: Array[Dictionary] = []
var keepnet_capacity := 20
var line_tension := 0.0
var fishing_state := "idle"
var cast_timer := 0.0
var bite_timer := 0.0
var fight_timer := 0.0
var cast_power := 0.72
var player_speed := 4.0
var look_sensitivity := 0.003
var is_running := false
var status_text := "Выберите место и забросьте снасть."
var selected_bait := "Червь"
var bobber: MeshInstance3D
var rod_tip: Node3D
var player: CharacterBody3D
var camera: Camera3D
var hud: CanvasLayer
var status_label: Label
var fish_label: Label
var tension_bar: ProgressBar
var cast_button: Button
var bite_button: Button
var reel_button: Button
var menu_panel: PanelContainer
var movement_vector := Vector2.ZERO
var touch_look_id := -1
var last_touch := Vector2.ZERO
var world_time := 0.28

func _ready() -> void:
    _build_world()
    _build_player()
    _build_hud()
    _refresh_hud()

func _process(delta: float) -> void:
    world_time = fmod(world_time + delta * 0.0006, 1.0)
    if fishing_state == "casting":
        cast_timer -= delta
        if cast_timer <= 0.0:
            fishing_state = "waiting"
            bite_timer = randf_range(4.0, 11.0)
            status_text = "Оснастка на воде. Ждём поклёвку…"
    elif fishing_state == "waiting":
        bite_timer -= delta
        if bite_timer <= 0.0:
            fishing_state = "bite"
            status_text = "ПОКЛЁВКА! Нажмите «Подсечка»."
            _pulse_bobber()
    elif fishing_state == "hooked":
        fight_timer -= delta
        line_tension = clampf(line_tension + randf_range(-0.12, 0.16), 0.0, 1.0)
        if line_tension > 0.88 and randf() < 0.025:
            fishing_state = "idle"
            status_text = "Леска оборвалась! Проверьте прочность снасти."
            line_tension = 0.0
        elif fight_timer <= 0.0:
            _land_fish()
    _update_player(delta)
    if is_instance_valid(tension_bar):
        tension_bar.value = line_tension * 100.0
    _refresh_hud()

func _build_world() -> void:
    var env := WorldEnvironment.new()
    var environment := Environment.new()
    environment.background_mode = Environment.BG_SKY
    var sky := Sky.new()
    var sky_mat := ProceduralSkyMaterial.new()
    sky_mat.sky_top_color = Color(0.13, 0.31, 0.45)
    sky_mat.sky_horizon_color = Color(0.72, 0.78, 0.72)
    sky_mat.ground_bottom_color = Color(0.12, 0.17, 0.12)
    sky_mat.ground_horizon_color = Color(0.34, 0.4, 0.29)
    sky.sky_material = sky_mat
    environment.sky = sky
    environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    environment.ambient_light_color = Color(0.62, 0.68, 0.73)
    environment.ambient_light_energy = 0.8
    environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
    env.environment = environment
    add_child(env)

    var sun := DirectionalLight3D.new()
    sun.rotation_degrees = Vector3(-48, -32, 0)
    sun.light_energy = 1.15
    add_child(sun)

    _add_box("Берег", Vector3(0, -0.35, 1.0), Vector3(46, 0.7, 28), Color(0.31, 0.28, 0.19))
    _add_box("Вода", Vector3(0, -0.18, -13.0), Vector3(70, 0.12, 18), Color(0.10, 0.34, 0.43, 0.88), true)
    _add_box("Дальний берег", Vector3(0, -0.1, -24.0), Vector3(80, 0.5, 5), Color(0.23, 0.3, 0.18))
    _add_box("Пирс", Vector3(0, 0.05, -5.0), Vector3(3.4, 0.22, 7.0), Color(0.30, 0.19, 0.10))
    for i in range(11):
        var reed := _make_primitive(SHAPE_CYLINDER, Vector3(0.06, 1.0, 0.06), Color(0.30, 0.38, 0.12))
        reed.position = Vector3(-10.0 + i * 1.9, 0.55, -3.0 - randf() * 1.3)
        reed.rotation_degrees.z = randf_range(-9, 9)
        add_child(reed)
    for i in range(18):
        var bush := _make_primitive(SHAPE_SPHERE, Vector3.ONE * randf_range(0.6, 1.2), Color(0.12, 0.27 + randf() * 0.12, 0.11))
        bush.position = Vector3(randf_range(-22, 22), 0.3, randf_range(3, 13))
        add_child(bush)
    for i in range(7):
        var trunk := _make_primitive(SHAPE_CYLINDER, Vector3(0.22, 2.0, 0.22), Color(0.27, 0.17, 0.09))
        trunk.position = Vector3(-19 + i * 6.0, 1.0, 12 + randf_range(-1.5, 1.5))
        add_child(trunk)
        var crown := _make_primitive(SHAPE_SPHERE, Vector3(1.35, 1.6, 1.35), Color(0.11, 0.25, 0.12))
        crown.position = trunk.position + Vector3(0, 1.8, 0)
        add_child(crown)

func _build_player() -> void:
    player = CharacterBody3D.new()
    player.name = "Player"
    player.position = Vector3(0, 0.05, 5.0)
    add_child(player)
    var collision := CollisionShape3D.new()
    var shape := CapsuleShape3D.new()
    shape.height = 1.7
    shape.radius = 0.32
    collision.shape = shape
    collision.position.y = 0.85
    player.add_child(collision)
    camera = Camera3D.new()
    camera.position = Vector3(0, 1.55, 0)
    camera.current = true
    player.add_child(camera)
    rod_tip = Node3D.new()
    rod_tip.position = Vector3(0.42, 1.25, -0.2)
    camera.add_child(rod_tip)
    var rod := _make_primitive(SHAPE_CYLINDER, Vector3(0.025, 2.1, 0.025), Color(0.16, 0.11, 0.07))
    rod.position = Vector3(0.0, 0.75, -0.15)
    rod.rotation_degrees.z = -16
    rod_tip.add_child(rod)
    bobber = _make_primitive(SHAPE_SPHERE, Vector3(0.14, 0.14, 0.14), Color(0.95, 0.23, 0.08))
    bobber.position = Vector3(0, -0.5, -4)
    add_child(bobber)

func _build_hud() -> void:
    hud = CanvasLayer.new()
    add_child(hud)
    var root := Control.new()
    root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    hud.add_child(root)

    var top := PanelContainer.new()
    top.position = Vector2(16, 14)
    top.custom_minimum_size = Vector2(340, 86)
    root.add_child(top)
    var top_v := VBoxContainer.new()
    top.add_child(top_v)
    var title := Label.new()
    title.text = "FISHING LEGEND"
    title.add_theme_font_size_override("font_size", 22)
    top_v.add_child(title)
    fish_label = Label.new()
    top_v.add_child(fish_label)

    var status_panel := PanelContainer.new()
    status_panel.anchor_left = 0.5
    status_panel.anchor_right = 0.5
    status_panel.offset_left = -240
    status_panel.offset_right = 240
    status_panel.offset_top = 16
    status_panel.offset_bottom = 70
    root.add_child(status_panel)
    status_label = Label.new()
    status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    status_panel.add_child(status_label)

    var controls := HBoxContainer.new()
    controls.anchor_left = 0.5
    controls.anchor_right = 0.5
    controls.anchor_top = 1.0
    controls.anchor_bottom = 1.0
    controls.offset_left = -250
    controls.offset_right = 250
    controls.offset_top = -94
    controls.offset_bottom = -18
    controls.add_theme_constant_override("separation", 12)
    root.add_child(controls)
    cast_button = _make_button("ЗАБРОС", controls, _cast)
    bite_button = _make_button("ПОДСЕЧКА", controls, _strike)
    reel_button = _make_button("ВЫВАЖИВАТЬ", controls, _reel)
    var shop := _make_button("САДОК / ПРОДАТЬ", root, _sell_catch)
    shop.anchor_left = 1.0
    shop.anchor_right = 1.0
    shop.anchor_top = 1.0
    shop.anchor_bottom = 1.0
    shop.offset_left = -205
    shop.offset_right = -16
    shop.offset_top = -174
    shop.offset_bottom = -120
    var menu := _make_button("МЕНЮ", root, _toggle_menu)
    menu.anchor_left = 1.0
    menu.anchor_right = 1.0
    menu.offset_left = -130
    menu.offset_right = -16
    menu.offset_top = 18
    menu.offset_bottom = 66
    tension_bar = ProgressBar.new()
    tension_bar.min_value = 0
    tension_bar.max_value = 100
    tension_bar.value = 0
    tension_bar.position = Vector2(16, 112)
    tension_bar.size = Vector2(250, 22)
    root.add_child(tension_bar)

    menu_panel = PanelContainer.new()
    menu_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
    menu_panel.custom_minimum_size = Vector2(310, 250)
    menu_panel.visible = false
    root.add_child(menu_panel)
    var menu_v := VBoxContainer.new()
    menu_panel.add_child(menu_v)
    var menu_title := Label.new()
    menu_title.text = "МЕНЮ РЫБОЛОВА"
    menu_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    menu_v.add_child(menu_title)
    _make_button("Продолжить", menu_v, _toggle_menu)
    _make_button("Информация", menu_v, func(): status_text = "Прототип Fishing Legend — ранняя версия.")
    _make_button("Наживка: сменить", menu_v, _cycle_bait)
    _make_button("Закрыть игру", menu_v, func(): get_tree().quit())

    var move_hint := Label.new()
    move_hint.text = "WASD — движение • свайп — обзор"
    move_hint.position = Vector2(20, 570)
    move_hint.add_theme_font_size_override("font_size", 14)
    root.add_child(move_hint)

func _make_button(text_value: String, parent: Node, callback: Callable) -> Button:
    var button := Button.new()
    button.text = text_value
    button.custom_minimum_size = Vector2(140, 62)
    button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    button.add_theme_font_size_override("font_size", 17)
    button.pressed.connect(callback)
    parent.add_child(button)
    return button

func _make_primitive(primitive: int, dimensions: Vector3, color: Color) -> MeshInstance3D:
    var node := MeshInstance3D.new()
    if primitive == SHAPE_SPHERE:
        var sphere := SphereMesh.new()
        sphere.radius = 0.5
        sphere.height = 1.0
        node.mesh = sphere
    elif primitive == SHAPE_CYLINDER:
        var cylinder := CylinderMesh.new()
        cylinder.top_radius = 0.5
        cylinder.bottom_radius = 0.5
        cylinder.height = 1.0
        node.mesh = cylinder
    else:
        node.mesh = BoxMesh.new()
    node.scale = dimensions
    var mat := StandardMaterial3D.new()
    mat.albedo_color = color
    mat.roughness = 0.82
    if color.a < 1.0:
        mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    node.material_override = mat
    return node

func _add_box(node_name: String, pos: Vector3, dimensions: Vector3, color: Color, no_shadow := false) -> void:
    var node := _make_primitive(SHAPE_BOX, dimensions, color)
    node.name = node_name
    node.position = pos
    if no_shadow:
        node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    add_child(node)

func _update_player(delta: float) -> void:
    if player == null:
        return
    var input := Vector2.ZERO
    if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
        input.y -= 1
    if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
        input.y += 1
    if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
        input.x -= 1
    if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
        input.x += 1
    input += movement_vector
    input = input.limit_length(1.0)
    var speed := player_speed * (1.6 if is_running else 1.0)
    var direction := (player.transform.basis * Vector3(input.x, 0, input.y)).normalized()
    player.velocity.x = direction.x * speed
    player.velocity.z = direction.z * speed
    if not player.is_on_floor():
        player.velocity.y -= 9.8 * delta
    else:
        player.velocity.y = 0.0
    player.move_and_slide()

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
        player.rotate_y(-event.relative.x * look_sensitivity)
        camera.rotate_x(-event.relative.y * look_sensitivity)
        camera.rotation.x = clampf(camera.rotation.x, -1.2, 1.2)
    elif event is InputEventScreenTouch:
        if event.pressed:
            touch_look_id = event.index
            last_touch = event.position
        elif event.index == touch_look_id:
            touch_look_id = -1
    elif event is InputEventScreenDrag and event.index == touch_look_id:
        var drag := event.position - last_touch
        if event.position.x > get_viewport().get_visible_rect().size.x * 0.35:
            player.rotate_y(-drag.x * look_sensitivity)
            camera.rotate_x(-drag.y * look_sensitivity)
            camera.rotation.x = clampf(camera.rotation.x, -1.2, 1.2)
        last_touch = event.position

func _cast() -> void:
    if fishing_state != "idle":
        status_text = "Сначала завершите текущую рыбалку."
        return
    fishing_state = "casting"
    cast_timer = 1.2
    bobber.visible = true
    bobber.position = player.global_position + -player.global_transform.basis.z * (5.0 + cast_power * 10.0) + Vector3(0, -0.15, 0)
    status_text = "Заброс…"
    rod_tip.rotation.x = -0.4

func _strike() -> void:
    if fishing_state == "bite":
        fishing_state = "hooked"
        fight_timer = randf_range(4.0, 9.0)
        line_tension = 0.42
        status_text = "Есть рыба! Следите за натяжением лески."
    else:
        status_text = "Подсекать нужно в момент поклёвки."

func _reel() -> void:
    if fishing_state == "hooked":
        line_tension = clampf(line_tension + 0.06, 0.0, 1.0)
        fight_timer -= 1.2
        if line_tension > 0.78:
            line_tension = maxf(0.0, line_tension - 0.16)
            status_text = "Ослабьте тормоз катушки — леска натянута!"
        else:
            status_text = "Подматываем леску…"
    elif fishing_state == "waiting":
        status_text = "Пока нет поклёвки. Следите за поплавком."
    else:
        status_text = "Сначала забросьте снасть."

func _land_fish() -> void:
    var fish: Dictionary = FISH_DATA.pick_random()
    var weight := randf_range(float(fish.min_weight), float(fish.max_weight))
    var catch_data := {"name": fish.name, "weight": snappedf(weight, 0.01), "price": int(round(weight * float(fish.price))), "xp": fish.xp}
    if keepnet.size() < keepnet_capacity:
        keepnet.append(catch_data)
        xp += int(fish.xp)
        while xp >= level * 100:
            xp -= level * 100
            level += 1
        status_text = "Поймана рыба: %s — %.2f кг!" % [fish.name, weight]
    else:
        status_text = "Садок заполнен! Продайте улов."
    fishing_state = "idle"
    line_tension = 0.0
    bobber.visible = false

func _sell_catch() -> void:
    if keepnet.is_empty():
        status_text = "Садок пуст. Поймайте рыбу!"
        return
    var total := 0
    for fish in keepnet:
        total += int(fish.price)
    silver += total
    status_text = "Улов продан за %d серебра." % total
    keepnet.clear()

func _cycle_bait() -> void:
    var baits := ["Червь", "Опарыш", "Кукуруза", "Тесто"]
    selected_bait = baits[(baits.find(selected_bait) + 1) % baits.size()]
    status_text = "Наживка выбрана: " + selected_bait

func _toggle_menu() -> void:
    menu_panel.visible = not menu_panel.visible

func _pulse_bobber() -> void:
    if is_instance_valid(bobber):
        bobber.scale = Vector3.ONE * 1.35

func _refresh_hud() -> void:
    if is_instance_valid(status_label):
        status_label.text = status_text
    if is_instance_valid(fish_label):
        fish_label.text = "Уровень %d • Опыт %d • Серебро %d • Садок %d/%d • Наживка: %s" % [level, xp, silver, keepnet.size(), keepnet_capacity, selected_bait]
    if is_instance_valid(cast_button):
        cast_button.disabled = fishing_state != "idle"
    if is_instance_valid(bite_button):
        bite_button.disabled = fishing_state != "bite"
    if is_instance_valid(reel_button):
        reel_button.disabled = fishing_state != "hooked"
