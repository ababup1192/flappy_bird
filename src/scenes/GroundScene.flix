// GroundScene — 地面タイルの構築・リサイクル
//
// 地面は StaticBody2D + 子 Sprite2D で構成される。
// 画面幅をカバーするよう複数タイル配置し、カメラの左端を超えたタイルは
// 右端に再配置する無限スクロール方式。
//
//   StaticBody2DWithState(body, Ground)
//     └── Sprite2DWithState(sprite, NoTag)

mod GroundScene {

    // ========================================================================
    // 定数
    // ========================================================================

    /// 地面グループ名（一括操作用）
    pub def groundGroup(): String = "grounds"

    /// 地面タイルの幅（px）。参考実装 168 の 2 倍
    pub def groundWidth(): Float64 = 336.0

    /// 地面タイルの高さ（px）。参考実装 56 の 2 倍
    def groundHeight(): Float64 = 112.0

    /// 地面の中心 Y 座標。画面下端(512) から高さの半分を引いた値
    pub def groundCenterY(): Float64 = 512.0 - groundHeight() / 2.0

    /// 地面の上端 Y 座標（鳥の位置クランプに使用）
    pub def groundTopY(): Float64 = 512.0 - groundHeight()

    /// 地面テクスチャ名
    def groundTexture(): String = "ground"

    /// 地面の衝突形状（タイル全体をカバーする矩形）
    def groundCollisionShape(): CollisionShape2D =
        CollisionShape2D.RectShape2D({width = groundWidth(), height = groundHeight()})

    /// 地面の Z-index（パイプや鳥より前面に描画）
    def groundZIndex(): Int32 = 10

    // ========================================================================
    // シーン構築
    // ========================================================================

    /// 地面タイル 1 枚をシーンに追加する
    /// name: ノード名（ユニーク）
    /// xCenter: タイル中心の X 座標
    pub def spawnGround(name: String, xCenter: Float64,
                        scene: Scene[NodeTag]): Scene[NodeTag] =
        let body = StaticBody2D.make(
            {x = xCenter, y = groundCenterY()},
            groundCollisionShape());
        let sprite = Sprite2D.make(groundTexture(), Vec2.zero(), {x = 2.0, y = 2.0})
            |> CanvasItem.setZIndex(groundZIndex());
        scene
            |> Scene.addNode(name,
                EngineNode.StaticBody2DWithState(body, NodeTag.Ground))
            |> Scene.addToGroup(name :: Nil, groundGroup())
            |> Scene.addChild(name, "sprite",
                EngineNode.Sprite2DWithState(sprite, NodeTag.NoTag))

    /// 初期地面タイルを配置する（2 枚で画面幅 + スクロールバッファをカバー）
    /// 戻り値: (更新されたシーン, 次のタイル番号, 次のタイル中心 X)
    pub def addGrounds(scene: Scene[NodeTag]): (Scene[NodeTag], Int32, Float64) =
        let halfWidth = groundWidth() / 2.0;
        let x0 = halfWidth;
        let x1 = x0 + groundWidth();
        let updatedScene = scene
            |> spawnGround("ground_0", x0)
            |> spawnGround("ground_1", x1);
        (updatedScene, 2, x1 + groundWidth())

    // ========================================================================
    // 地面リサイクル
    // ========================================================================

    /// カメラ左端を超えた地面タイルを右端に再配置する
    /// viewportLeftX: カメラが映す左端の X 座標
    /// groundCounter: 次のタイル番号（ユニーク名生成用）
    /// nextGroundX: 次のタイルの中心 X 座標
    /// 戻り値: (更新されたシーン, 更新されたタイル番号, 更新された次のタイル X)
    pub def recycleGrounds(viewportLeftX: Float64,
                           groundCounter: Int32, nextGroundX: Float64,
                           scene: Scene[NodeTag]): (Scene[NodeTag], Int32, Float64) =
        let halfWidth = groundWidth() / 2.0;
        let paths = Scene.getNodesInGroup(groundGroup(), scene);
        let offScreenPaths = List.filter(path ->
            let pos = Scene.globalPositionAt(path, scene);
            pos#x + halfWidth < viewportLeftX
        , paths);
        List.foldLeft((acc, path) ->
            let (accScene, counter, nextX) = acc;
            let newName = "ground_${counter}";
            let newScene = accScene
                |> Scene.removeAt(path)
                |> spawnGround(newName, nextX);
            (newScene, counter + 1, nextX + groundWidth())
        , (scene, groundCounter, nextGroundX), offScreenPaths)
}
