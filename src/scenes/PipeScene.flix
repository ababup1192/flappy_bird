// PipeScene — パイプ障害物の構築・リサイクル
//
// パイプは StaticBody2D + 子 Sprite2D で構成される。
// 上下ペアでギャップを作り、鳥が通過する障害物となる。
// 画面左端を超えたパイプはリサイクルして右端に再配置する。
//
//   StaticBody2DWithState(body, Pipe)
//     └── Sprite2DWithState(sprite, NoTag)

mod PipeScene {

    // ========================================================================
    // 定数
    // ========================================================================

    /// パイプグループ名（一括操作用）
    pub def pipeGroup(): String = "pipes"

    /// ギャップ中心 Y 座標の最小値
    def gapYMin(): Float64 = 110.0

    /// ギャップ中心 Y 座標の最大値
    def gapYMax(): Float64 = 290.0

    /// ギャップ中心からパイプ中心までの距離
    def spriteOffset(): Float64 = 202.0

    /// パイプの衝突形状（矩形 52×320 = 参考実装 26×160 の 2 倍）
    def pipeCollisionShape(): CollisionShape2D =
        CollisionShape2D.RectShape2D({width = 52.0, height = 320.0})

    /// パイプペア間の水平距離
    def pipeSpacingX(): Float64 = 182.0

    /// 初期パイプペア数
    def initialPipeCount(): Int32 = 3

    /// 最初のパイプの X 座標（鳥の初期 X 144 + 画面幅 288）
    def firstPipeX(): Float64 = 432.0

    /// パイプの半幅（画面外判定に使用）
    pub def pipeHalfWidth(): Float64 = 26.0

    /// トップパイプのテクスチャ名
    def topTexture(): String = "pipe_green_top"

    /// ボトムパイプのテクスチャ名
    def bottomTexture(): String = "pipe_green_bottom"

    // ========================================================================
    // シーン構築
    // ========================================================================

    /// パイプ 1 本をシーンに追加する
    /// name: ノード名（ユニーク）
    /// x: パイプ中心の X 座標
    /// y: パイプ中心の Y 座標
    /// texture: テクスチャ名
    def spawnPipe(name: String, x: Float64, y: Float64, texture: String,
                  scene: Scene[NodeTag]): Scene[NodeTag] =
        let body = StaticBody2D.make({x = x, y = y}, pipeCollisionShape());
        let sprite = Sprite2D.make(texture, Vec2.zero(), {x = 2.0, y = 2.0});
        scene
            |> Scene.addNode(name,
                EngineNode.StaticBody2DWithState(body, NodeTag.Pipe))
            |> Scene.addToGroup(name :: Nil, pipeGroup())
            |> Scene.addChild(name, "sprite",
                EngineNode.Sprite2DWithState(sprite, NodeTag.NoTag))

    /// パイプペアを指定位置に決定的に追加する（テスト用公開）
    /// counter: ペア番号（ユニーク名生成用）
    /// x: ペアの X 座標
    /// gapY: ギャップ中心の Y 座標
    pub def spawnPipePairAt(counter: Int32, x: Float64, gapY: Float64,
                            scene: Scene[NodeTag]): Scene[NodeTag] =
        scene
            |> spawnPipe("pipe_${counter}_top", x, gapY - spriteOffset(), topTexture())
            |> spawnPipe("pipe_${counter}_bottom", x, gapY + spriteOffset(), bottomTexture())

    /// パイプペアをランダムな gapY で追加する
    /// counter: ペア番号
    /// x: ペアの X 座標
    def spawnPipePair(counter: Int32, x: Float64,
                      scene: Scene[NodeTag]): Scene[NodeTag] \ Math.Random =
        let gapY = gapYMin() + (gapYMax() - gapYMin()) * Math.Random.randomFloat64();
        spawnPipePairAt(counter, x, gapY, scene)

    /// 初期パイプ（3 ペア）を配置する
    /// 戻り値: (更新されたシーン, 次のペア番号, 次のペア X 座標)
    pub def addPipes(scene: Scene[NodeTag]): (Scene[NodeTag], Int32, Float64) \ Math.Random =
        List.range(0, initialPipeCount())
            |> List.foldLeft((acc, _i) ->
                let (accScene, counter, nextX) = acc;
                let newScene = spawnPipePair(counter, nextX, accScene);
                (newScene, counter + 1, nextX + pipeSpacingX())
            , (scene, 0, firstPipeX()))

    // ========================================================================
    // パイプリサイクル
    // ========================================================================

    /// 画面外のパイプを削除し、右端に再スポーンする
    /// viewportLeftX: カメラが映す左端の X 座標
    /// pipeCounter: 次のペア番号（ユニーク名生成用）
    /// nextPipeX: 次のペアの X 座標
    /// 戻り値: (更新されたシーン, 更新されたペア番号, 更新された次のペア X)
    pub def recyclePipes(viewportLeftX: Float64,
                         pipeCounter: Int32, nextPipeX: Float64,
                         scene: Scene[NodeTag]): (Scene[NodeTag], Int32, Float64) \ Math.Random =
        let paths = Scene.getNodesInGroup(pipeGroup(), scene);
        let offScreenPaths = List.filter(path ->
            let pos = Scene.globalPositionAt(path, scene);
            pos#x + pipeHalfWidth() < viewportLeftX
        , paths);
        // 画面外パイプを全て削除
        let cleanedScene = List.foldLeft((accScene, path) ->
            Scene.removeAt(path, accScene)
        , scene, offScreenPaths);
        // 削除数 / 2 = ペア数を再スポーン
        let pairsToSpawn = List.length(offScreenPaths) / 2;
        List.range(0, pairsToSpawn)
            |> List.foldLeft((acc, _i) ->
                let (accScene, counter, nextX) = acc;
                let newScene = spawnPipePair(counter, nextX, accScene);
                (newScene, counter + 1, nextX + pipeSpacingX())
            , (cleanedScene, pipeCounter, nextPipeX))
}
