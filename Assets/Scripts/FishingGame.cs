using System.Collections;
using UnityEngine;
using UnityEngine.UI;
using UnityEngine.EventSystems;

public class FishingGame : MonoBehaviour
{
    private Camera playerCamera;
    private Transform player;
    private Text statusText;
    private Text statsText;
    private Text fishText;
    private Text tensionText;
    private Material groundMaterial, waterMaterial, woodMaterial, leafMaterial, rockMaterial;
    private int state; // 0 idle, 1 waiting, 2 bite, 3 hooked
    private float biteTimer;
    private float fightProgress;
    private float tension;
    private int fishCount;
    private int silver = 120;
    private int level = 1;
    private float lookSensitivity = 0.12f;
    private Vector2 previousTouch;
    private int lookFinger = -1;

    private void Start()
    {
        Application.targetFrameRate = 60;
        Screen.sleepTimeout = SleepTimeout.NeverSleep;
        CreateMaterials();
        BuildWorld();
        BuildUI();
        SetStatus("Добро пожаловать на рыбалку! Нажмите «Забросить».");
        RefreshStats();
    }

    private void CreateMaterials()
    {
        groundMaterial = MakeMaterial(new Color(0.28f, 0.34f, 0.20f));
        waterMaterial = MakeMaterial(new Color(0.04f, 0.30f, 0.43f), 0.15f, 0.8f);
        woodMaterial = MakeMaterial(new Color(0.30f, 0.18f, 0.09f));
        leafMaterial = MakeMaterial(new Color(0.13f, 0.29f, 0.12f));
        rockMaterial = MakeMaterial(new Color(0.30f, 0.32f, 0.31f));
    }

    private Material MakeMaterial(Color color, float metallic = 0f, float smoothness = 0.25f)
    {
        Shader shader = Shader.Find("Standard");
        if (shader == null) shader = Shader.Find("Universal Render Pipeline/Lit");
        Material material = new Material(shader);
        material.color = color;
        if (material.HasProperty("_Metallic")) material.SetFloat("_Metallic", metallic);
        if (material.HasProperty("_Glossiness")) material.SetFloat("_Glossiness", smoothness);
        return material;
    }

    private GameObject MakePrimitive(PrimitiveType type, string objectName, Vector3 position, Vector3 scale, Material material)
    {
        GameObject item = GameObject.CreatePrimitive(type);
        item.name = objectName;
        item.transform.position = position;
        item.transform.localScale = scale;
        if (material != null) item.GetComponent<Renderer>().sharedMaterial = material;
        return item;
    }

    private void BuildWorld()
    {
        RenderSettings.ambientLight = new Color(0.55f, 0.59f, 0.62f);
        RenderSettings.fog = true;
        RenderSettings.fogColor = new Color(0.58f, 0.68f, 0.72f);
        RenderSettings.fogMode = FogMode.Linear;
        RenderSettings.fogStartDistance = 45f;
        RenderSettings.fogEndDistance = 170f;

        GameObject sun = new GameObject("Sunlight");
        Light sunLight = sun.AddComponent<Light>();
        sunLight.type = LightType.Directional;
        sunLight.intensity = 1.15f;
        sun.transform.rotation = Quaternion.Euler(48f, -32f, 0f);

        MakePrimitive(PrimitiveType.Plane, "Grassy Shore", new Vector3(0f, -0.16f, -40f), new Vector3(10f, 1f, 10f), groundMaterial);
        MakePrimitive(PrimitiveType.Plane, "Lake Water", new Vector3(0f, -0.08f, 60f), new Vector3(12f, 1f, 12f), waterMaterial);

        // A simple timber pier built from separate planks.
        for (int i = 0; i < 13; i++)
            MakePrimitive(PrimitiveType.Cube, "Pier Plank", new Vector3(0f, 0.12f, 2f + i * 1.05f), new Vector3(3.2f, 0.22f, 1f), woodMaterial);
        for (int z = 2; z <= 14; z += 3)
        {
            MakePrimitive(PrimitiveType.Cylinder, "Pier Support", new Vector3(-1.35f, -0.45f, z), new Vector3(0.16f, 1.2f, 0.16f), woodMaterial);
            MakePrimitive(PrimitiveType.Cylinder, "Pier Support", new Vector3(1.35f, -0.45f, z), new Vector3(0.16f, 1.2f, 0.16f), woodMaterial);
        }

        Vector3[] treePositions = {
            new Vector3(-9, 0, -17), new Vector3(-15, 0, -34), new Vector3(10, 0, -21),
            new Vector3(17, 0, -40), new Vector3(-22, 0, -57), new Vector3(25, 0, -25),
            new Vector3(7, 0, -61), new Vector3(-5, 0, -48)
        };
        for (int i = 0; i < treePositions.Length; i++) CreateTree(treePositions[i], 0.85f + (i % 3) * 0.2f);

        for (int i = 0; i < 24; i++)
        {
            float x = Mathf.Sin(i * 2.1f) * Random.Range(5f, 22f);
            float z = Random.Range(-75f, -3f);
            GameObject rock = MakePrimitive(PrimitiveType.Sphere, "Shore Rock", new Vector3(x, -0.05f, z), new Vector3(Random.Range(0.3f, 1.1f), Random.Range(0.2f, 0.6f), Random.Range(0.3f, 0.9f)), rockMaterial);
            rock.transform.rotation = Quaternion.Euler(Random.Range(0, 25), Random.Range(0, 180), Random.Range(0, 20));
        }

        GameObject playerObject = new GameObject("First Person Player");
        player = playerObject.transform;
        player.position = new Vector3(0f, 1.7f, -4f);
        playerCamera = playerObject.AddComponent<Camera>();
        playerCamera.fieldOfView = 72f;
        playerCamera.nearClipPlane = 0.05f;
        playerObject.AddComponent<AudioListener>();

        // A subtle fishing rod silhouette in the lower-right foreground.
        GameObject rod = MakePrimitive(PrimitiveType.Cylinder, "Fishing Rod", new Vector3(0.34f, 1.2f, -3.35f), new Vector3(0.035f, 1.45f, 0.035f), woodMaterial);
        rod.transform.rotation = Quaternion.Euler(18f, 0f, -17f);
        rod.transform.SetParent(player, true);

        GameObject skyLight = new GameObject("Fill Light");
        Light fill = skyLight.AddComponent<Light>();
        fill.type = LightType.Directional;
        fill.intensity = 0.25f;
        skyLight.transform.rotation = Quaternion.Euler(25f, 140f, 0f);
    }

    private void CreateTree(Vector3 position, float size)
    {
        MakePrimitive(PrimitiveType.Cylinder, "Tree Trunk", position + Vector3.up * (1.6f * size), new Vector3(0.38f * size, 1.6f * size, 0.38f * size), woodMaterial);
        GameObject crown = MakePrimitive(PrimitiveType.Sphere, "Tree Crown", position + Vector3.up * (4f * size), new Vector3(2.5f * size, 3f * size, 2.5f * size), leafMaterial);
        crown.transform.position += new Vector3(0f, 0.2f, 0f);
    }

    private void BuildUI()
    {
        GameObject canvasObject = new GameObject("Fishing HUD");
        Canvas canvas = canvasObject.AddComponent<Canvas>();
        canvas.renderMode = RenderMode.ScreenSpaceOverlay;
        canvasObject.AddComponent<CanvasScaler>().uiScaleMode = CanvasScaler.ScaleMode.ScaleWithScreenSize;
        canvasObject.GetComponent<CanvasScaler>().referenceResolution = new Vector2(1920, 1080);
        canvasObject.GetComponent<CanvasScaler>().matchWidthOrHeight = 0.5f;
        canvasObject.AddComponent<GraphicRaycaster>();

        GameObject eventObject = new GameObject("EventSystem");
        eventObject.AddComponent<EventSystem>();
        eventObject.AddComponent<StandaloneInputModule>();

        statusText = CreateText(canvas.transform, "Status", "Подготовка...", new Vector2(0.5f, 0.93f), new Vector2(1200, 90), 30, TextAnchor.MiddleCenter);
        statsText = CreateText(canvas.transform, "Stats", "", new Vector2(0.14f, 0.94f), new Vector2(470, 70), 24, TextAnchor.MiddleLeft);
        fishText = CreateText(canvas.transform, "Fish Count", "Садок: 0", new Vector2(0.86f, 0.94f), new Vector2(400, 70), 24, TextAnchor.MiddleRight);
        tensionText = CreateText(canvas.transform, "Line Tension", "", new Vector2(0.5f, 0.15f), new Vector2(600, 60), 26, TextAnchor.MiddleCenter);

        CreateButton(canvas.transform, "Забросить", new Vector2(0.86f, 0.13f), new Vector2(250, 100), Cast);
        CreateButton(canvas.transform, "Подсечь", new Vector2(0.86f, 0.25f), new Vector2(250, 90), Hook);
        CreateButton(canvas.transform, "Подматывать", new Vector2(0.86f, 0.36f), new Vector2(250, 90), Reel);
        CreateButton(canvas.transform, "Продать улов", new Vector2(0.14f, 0.13f), new Vector2(270, 90), SellFish);
        CreateButton(canvas.transform, "↑", new Vector2(0.11f, 0.34f), new Vector2(100, 90), () => MoveStep(Vector3.forward));
        CreateButton(canvas.transform, "←", new Vector2(0.055f, 0.24f), new Vector2(90, 80), () => MoveStep(Vector3.left));
        CreateButton(canvas.transform, "→", new Vector2(0.165f, 0.24f), new Vector2(90, 80), () => MoveStep(Vector3.right));
        CreateButton(canvas.transform, "↓", new Vector2(0.11f, 0.14f), new Vector2(100, 80), () => MoveStep(Vector3.back));
    }

    private Text CreateText(Transform parent, string objectName, string value, Vector2 anchor, Vector2 size, int fontSize, TextAnchor alignment)
    {
        GameObject textObject = new GameObject(objectName);
        textObject.transform.SetParent(parent, false);
        RectTransform rect = textObject.AddComponent<RectTransform>();
        rect.anchorMin = anchor;
        rect.anchorMax = anchor;
        rect.anchoredPosition = Vector2.zero;
        rect.sizeDelta = size;
        Text text = textObject.AddComponent<Text>();
        text.font = Resources.GetBuiltinResource<Font>("Arial.ttf");
        text.text = value;
        text.fontSize = fontSize;
        text.alignment = alignment;
        text.color = Color.white;
        text.horizontalOverflow = HorizontalWrapMode.Wrap;
        text.verticalOverflow = VerticalWrapMode.Overflow;
        text.fontStyle = FontStyle.Bold;
        textObject.AddComponent<Shadow>().effectDistance = new Vector2(2f, -2f);
        return text;
    }

    private void CreateButton(Transform parent, string label, Vector2 anchor, Vector2 size, UnityEngine.Events.UnityAction action)
    {
        GameObject buttonObject = new GameObject(label + " Button");
        buttonObject.transform.SetParent(parent, false);
        RectTransform rect = buttonObject.AddComponent<RectTransform>();
        rect.anchorMin = anchor;
        rect.anchorMax = anchor;
        rect.anchoredPosition = Vector2.zero;
        rect.sizeDelta = size;
        Image image = buttonObject.AddComponent<Image>();
        image.color = new Color(0.035f, 0.13f, 0.17f, 0.88f);
        Button button = buttonObject.AddComponent<Button>();
        button.targetGraphic = image;
        button.onClick.AddListener(action);
        Text buttonText = CreateText(buttonObject.transform, "Label", label, new Vector2(0.5f, 0.5f), size - new Vector2(12, 8), 25, TextAnchor.MiddleCenter);
        buttonText.raycastTarget = false;
    }

    private void Update()
    {
        UpdateLook();
        if (state == 1)
        {
            biteTimer -= Time.deltaTime;
            if (biteTimer <= 0f)
            {
                state = 2;
                SetStatus("ПОКЛЁВКА! Нажмите «Подсечь».");
            }
        }
        else if (state == 3)
        {
            tension = 0.35f + Mathf.Abs(Mathf.Sin(Time.time * 1.7f)) * 0.55f;
            if (tension > 0.84f && Random.value < 0.015f)
            {
                state = 0;
                tensionText.text = "";
                SetStatus("Леска не выдержала! Попробуйте ещё раз.");
            }
            else
            {
                tensionText.text = "Натяжение лески: " + Mathf.RoundToInt(tension * 100f) + "%";
            }
        }
    }

    private void UpdateLook()
    {
        if (player == null) return;
        if (Input.GetMouseButton(1))
        {
            player.Rotate(0f, Input.GetAxis("Mouse X") * 2.2f, 0f);
            playerCamera.transform.localRotation = Quaternion.Euler(
                Mathf.Clamp(playerCamera.transform.localEulerAngles.x - Input.GetAxis("Mouse Y") * 2.2f, -70f, 70f), 0f, 0f);
        }

        for (int i = 0; i < Input.touchCount; i++)
        {
            Touch touch = Input.GetTouch(i);
            if (EventSystem.current != null && EventSystem.current.IsPointerOverGameObject(touch.fingerId)) continue;
            if (touch.position.x < Screen.width * 0.38f) continue;
            if (touch.phase == TouchPhase.Began)
            {
                lookFinger = touch.fingerId;
                previousTouch = touch.position;
            }
            else if (touch.fingerId == lookFinger && (touch.phase == TouchPhase.Moved || touch.phase == TouchPhase.Stationary))
            {
                Vector2 delta = touch.position - previousTouch;
                player.Rotate(0f, delta.x * lookSensitivity, 0f);
                Vector3 angles = playerCamera.transform.localEulerAngles;
                float pitch = angles.x > 180f ? angles.x - 360f : angles.x;
                pitch = Mathf.Clamp(pitch - delta.y * lookSensitivity, -70f, 70f);
                playerCamera.transform.localRotation = Quaternion.Euler(pitch, 0f, 0f);
                previousTouch = touch.position;
            }
            else if (touch.fingerId == lookFinger && (touch.phase == TouchPhase.Ended || touch.phase == TouchPhase.Canceled))
            {
                lookFinger = -1;
            }
        }
    }

    private void MoveStep(Vector3 localDirection)
    {
        Vector3 direction = player.TransformDirection(localDirection);
        direction.y = 0f;
        player.position += direction.normalized * 0.8f;
        player.position = new Vector3(Mathf.Clamp(player.position.x, -35f, 35f), 1.7f, Mathf.Clamp(player.position.z, -80f, 0.5f));
    }

    private void Cast()
    {
        if (state != 0)
        {
            SetStatus("Сначала завершите текущую рыбалку.");
            return;
        }
        state = 1;
        biteTimer = Random.Range(4f, 10f);
        tensionText.text = "";
        SetStatus("Заброс выполнен. Ждём поклёвку...");
    }

    private void Hook()
    {
        if (state == 2)
        {
            state = 3;
            fightProgress = 0f;
            SetStatus("Есть рыба! Подматывайте и следите за натяжением.");
        }
        else
        {
            SetStatus("Подсекать нужно в момент поклёвки.");
        }
    }

    private void Reel()
    {
        if (state != 3)
        {
            SetStatus("Сейчас нечего подматывать.");
            return;
        }
        fightProgress += Random.Range(0.18f, 0.32f);
        if (fightProgress >= 1f)
        {
            state = 0;
            fishCount++;
            int gainedXp = Random.Range(8, 20);
            level += (fishCount % 5 == 0) ? 1 : 0;
            tensionText.text = "";
            SetStatus("Улов! Вы поймали " + RandomFish() + ". +" + gainedXp + " опыта.");
            RefreshStats();
        }
        else
        {
            SetStatus("Рыба сопротивляется. Продолжайте подматывать!");
        }
    }

    private string RandomFish()
    {
        string[] names = { "карася", "плотву", "окуня", "леща", "карпа" };
        return names[Random.Range(0, names.Length)];
    }

    private void SellFish()
    {
        if (fishCount <= 0)
        {
            SetStatus("Садок пока пуст.");
            return;
        }
        int earned = fishCount * Random.Range(12, 28);
        silver += earned;
        SetStatus("Улов продан за " + earned + " серебра.");
        fishCount = 0;
        RefreshStats();
    }

    private void SetStatus(string value)
    {
        if (statusText != null) statusText.text = value;
    }

    private void RefreshStats()
    {
        if (statsText != null) statsText.text = "Уровень " + level + "   |   Серебро: " + silver;
        if (fishText != null) fishText.text = "Садок: " + fishCount;
    }
}
