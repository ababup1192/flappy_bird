// MenuScene — メニュー画面の構築・削除
//
// CanvasLayer (layer=2) の子としてタイトルロゴ・操作説明画像・Play ボタンを配置する。
//
//   CanvasLayerWithState(menu, NoTag)  [layer=2]
//     ├── Sprite2DWithState(title_logo, NoTag)                  // label_flappy_bird (y=140)
//     ├── Sprite2DWithState(instructions_img, NoTag)            // instructions (y=340)
//     └── TextureButtonWithState(play_button, PlayButton(...))  // button_play_normal (y=440)

mod MenuScene {

    // ========================================================================
    // 定数 — ノード名
    // ========================================================================

    /// メニューレイヤーのノード名
    def layerName(): String = "menu"

    /// タイトルロゴのノード名
    def titleLogoName(): String = "title_logo"

    /// 操作説明画像のノード名
    def instructionsName(): String = "instructions_img"

    /// Play ボタンのノード名
    def playButtonName(): String = "play_button"

    // ========================================================================
    // 定数 — パス
    // ========================================================================

    pub def titleLogoPath(): NodePath = layerName() :: titleLogoName() :: Nil
    pub def instructionsPath(): NodePath = layerName() :: instructionsName() :: Nil
    pub def playButtonPath(): NodePath = layerName() :: playButtonName() :: Nil

    // ========================================================================
    // 定数 — 位置・サイズ・スケール
    // ========================================================================

    def titleLogoPos(): Vec2.Vec2 = {x = 144.0, y = 140.0}
    def instructionsPos(): Vec2.Vec2 = {x = 144.0, y = 340.0}

    /// Play ボタンの位置（中心座標）
    def playButtonPos(): Vec2.Vec2 = {x = 144.0, y = 440.0}

    /// Play ボタンサイズ（button_play_normal 52x29 px × 2x スケール = 104x58）
    def playButtonSize(): Vec2.Vec2 = {x = 104.0, y = 58.0}

    /// 共通の 2x スケール
    def scale2x(): Vec2.Vec2 = {x = 2.0, y = 2.0}

    // ========================================================================
    // シーン構築
    // ========================================================================

    /// メニュー UI をシーンに追加する
    pub def addMenuUI(scene: Scene[NodeTag]): Scene[NodeTag] =
        let layer = CanvasLayer.make(2);
        let titleLogo = Sprite2D.make("label_flappy_bird", titleLogoPos(), scale2x());
        let instructions = Sprite2D.make("instructions", instructionsPos(), scale2x());
        let playButton = TextureButton.make("button_play_normal", playButtonSize())
            |> TextureButton.setTexturePressed("button_play_pressed")
            |> TextureButton.setCentered(true)
            |> Node2D.setPosition(playButtonPos())
            |> Node2D.setScale(scale2x());
        scene
            |> Scene.addNode(layerName(),
                EngineNode.CanvasLayerWithState(layer, NodeTag.NoTag))
            |> Scene.addChild(layerName(), titleLogoName(),
                EngineNode.Sprite2DWithState(titleLogo, NodeTag.NoTag))
            |> Scene.addChild(layerName(), instructionsName(),
                EngineNode.Sprite2DWithState(instructions, NodeTag.NoTag))
            |> Scene.addChild(layerName(), playButtonName(),
                EngineNode.TextureButtonWithState(playButton, NodeTag.PlayButton({pressed = false})))

    /// メニュー UI をシーンから削除する
    pub def removeMenuUI(scene: Scene[NodeTag]): Scene[NodeTag] =
        Scene.removeAt(layerName() :: Nil, scene)

    // ========================================================================
    // Play ボタン汎用ヘルパー（GameOverScene からも使う）
    // BirdScene.mapBirdBody / getBirdData と同形。NodeTag.PlayButton を持つ
    // 任意の TextureButton ノードに対して動作する
    // ========================================================================

    /// PlayButton ノードの TextureButton と PlayButtonData を変換する
    pub def mapPlayButton(path: NodePath,
                          f: (TextureButton, PlayButtonData) -> (TextureButton, PlayButtonData),
                          scene: Scene[NodeTag]): Scene[NodeTag] =
        Scene.mapEngineNode(path, engineNode -> match engineNode {
            case EngineNode.TextureButtonWithState(btn, NodeTag.PlayButton(data)) =>
                let (newBtn, newData) = f(btn, data);
                EngineNode.TextureButtonWithState(newBtn, NodeTag.PlayButton(newData))
            case other => other
        }, scene)

    /// Scene から PlayButtonData を取り出す
    /// PlayButton ノードが存在しないシーンでは未押下扱いを返す
    pub def getPlayButtonData(path: NodePath, scene: Scene[NodeTag]): PlayButtonData =
        match Scene.getState(path, scene) {
            case Some(NodeTag.PlayButton(data)) => data
            case _ => {pressed = false}
        }

    // ========================================================================
    // メニューの Play ボタン押下管理（ButtonHandler が NodeTag.PlayButton.pressed=true をセット）
    // ========================================================================

    pub def isPlayButtonPressed(scene: Scene[NodeTag]): Bool =
        getPlayButtonData(playButtonPath(), scene)#pressed

    pub def clearPlayButton(scene: Scene[NodeTag]): Scene[NodeTag] =
        mapPlayButton(playButtonPath(), (btn, _) -> (btn, {pressed = false}), scene)

    /// Play ボタンの押下フラグを取得し、同時にクリアする
    /// (押下されていた場合は true, クリア後 Scene を返す)
    pub def consumePlayButtonPressed(scene: Scene[NodeTag]): (Bool, Scene[NodeTag]) =
        let pressed = isPlayButtonPressed(scene);
        if (pressed) (true, clearPlayButton(scene)) else (false, scene)
}
