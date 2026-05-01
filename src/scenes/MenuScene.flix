// MenuScene — メニュー画面の構築・削除
//
// CanvasLayer (layer=2) の子としてタイトルロゴと操作説明画像を配置する。
//
//   CanvasLayerWithState(menu, NoTag)  [layer=2]
//     ├── Sprite2DWithState(title_logo, NoTag)       // label_flappy_bird (y=140)
//     └── Sprite2DWithState(instructions_img, NoTag)  // instructions (y=340)

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

    // ========================================================================
    // 定数 — パス
    // ========================================================================

    /// タイトルロゴのノードパス
    pub def titleLogoPath(): NodePath = layerName() :: titleLogoName() :: Nil

    /// 操作説明画像のノードパス
    pub def instructionsPath(): NodePath = layerName() :: instructionsName() :: Nil

    // ========================================================================
    // 定数 — 位置・スケール
    // ========================================================================

    /// タイトルロゴの位置（画面中央上部）
    def titleLogoPos(): Vec2.Vec2 = {x = 144.0, y = 140.0}

    /// 操作説明画像の位置（画面中央）
    def instructionsPos(): Vec2.Vec2 = {x = 144.0, y = 340.0}

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
        scene
            |> Scene.addNode(layerName(),
                EngineNode.CanvasLayerWithState(layer, NodeTag.NoTag))
            |> Scene.addChild(layerName(), titleLogoName(),
                EngineNode.Sprite2DWithState(titleLogo, NodeTag.NoTag))
            |> Scene.addChild(layerName(), instructionsName(),
                EngineNode.Sprite2DWithState(instructions, NodeTag.NoTag))

    /// メニュー UI をシーンから削除する
    pub def removeMenuUI(scene: Scene[NodeTag]): Scene[NodeTag] =
        Scene.removeAt(layerName() :: Nil, scene)
}
