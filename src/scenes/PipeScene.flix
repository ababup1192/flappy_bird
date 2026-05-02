// PipeScene — パイプ障害物の構築・リサイクル
//
// パイプは StaticBody2D + 子 Sprite2D で構成される。
// 上下ペアでギャップを作り、鳥が通過する障害物となる。
// 画面左端を超えたパイプはリサイクルして右端に再配置する。
// スコアが低いうちは上下パイプの隙間を広くし、難易度を段階的に上げる。
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

    /// ギャップ中心からパイプ中心までの距離（通常難易度: score >= 10）
    /// 縦ギャップ = 2 × (202 - 160) = 84px
    def normalSpriteOffset(): Float64 = 202.0

    /// ギャップ中心からパイプ中心までの距離（初心者向け: score = 0）
    /// 縦ギャップ = 2 × (250 - 160) = 180px
    def easySpriteOffset(): Float64 = 250.0

    /// パイプの衝突形状（矩形 52×320 = 参考実装 26×160 の 2 倍）
    def pipeCollisionShape(): CollisionShape2D =
        CollisionShape2D.RectShape2D({width = 52.0, height = 320.0})

    /// パイプペア間の水平距離
    def pipeSpacingX(): Float64 = 182.0

    /// 難易度が通常に到達するスコア閾値
    def difficultyMaxScore(): Int32 = 10

    /// スコアに応じた上下パイプ間のギャップ用オフセットを返す
    /// score 0 → 250（初心者向けの広いギャップ 180px）
    /// score 10 以上 → 202（通常難易度のギャップ 84px）
    /// score 1〜9 → 線形補間で徐々に狭くなる
    pub def gapSpriteOffset(score: Int32): Float64 =
        if (score >= difficultyMaxScore()) normalSpriteOffset()
        else {
            let t = Int32.toFloat64(score) / Int32.toFloat64(difficultyMaxScore());
            easySpriteOffset() + (normalSpriteOffset() - easySpriteOffset()) * t
        }

    /// 初期パイプペア数
    def initialPipeCount(): Int32 = 3

    /// 最初のパイプの X 座標（鳥の初期 X 144 + 画面幅 288 × 1.5）
    /// 鳥が操作に慣れる猶予を持たせるために画面 1.5 枚分先に配置
    def firstPipeX(): Float64 = 576.0

    /// パイプの半幅（画面外判定に使用）
    pub def pipeHalfWidth(): Float64 = 26.0

    /// トップパイプのテクスチャ名
    def topTexture(): String = "pipe_green_top"

    /// ボトムパイプのテクスチャ名
    def bottomTexture(): String = "pipe_green_bottom"

    /// パイプの衝突形状の半高（320 / 2）
    def pipeHalfHeight(): Float64 = 160.0

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
        // physicsCollisionEnabled=false: pipe は RigidBody2D を物理的に押し戻さない。
        // 衝突は Bird の Area2D で検出して onBirdHitPipe で処理する（bird.gd add_collision_exception_with 相当）。
        let body = StaticBody2D.make({x = x, y = y}, pipeCollisionShape())
            |> StaticBody2D.setPhysicsCollisionEnabled(false);
        let sprite = Sprite2D.make(texture, Vec2.zero(), {x = 2.0, y = 2.0});
        scene
            |> Scene.addNode(name,
                EngineNode.StaticBody2DWithState(body, NodeTag.Pipe))
            |> Scene.addToGroup(name :: Nil, pipeGroup())
            |> Scene.addChild(name, "sprite",
                EngineNode.Sprite2DWithState(sprite, NodeTag.NoTag))

    /// コイン（採点用 Area2D）をギャップ中央に追加する
    /// ギャップ全体をカバーする薄い矩形センサーで、確実に通過を検知する
    /// monitoring = false: コイン自身は重なりを検知しない（検知される側のみ）
    def spawnCoin(counter: Int32, x: Float64, gapY: Float64, gapHeight: Float64,
                  scene: Scene[NodeTag]): Scene[NodeTag] =
        let coinName = "pipe_${counter}_coin";
        let coinShape = CollisionShape2D.RectShape2D({width = 4.0, height = gapHeight});
        let area = Area2D.make({x = x, y = gapY}, coinShape)
            |> Area2D.setMonitoring(false);
        scene
            |> Scene.addNode(coinName,
                EngineNode.Area2DWithState(area, NodeTag.Coin))
            |> Scene.addToGroup(coinName :: Nil, pipeGroup())

    /// パイプペアを指定位置に決定的に追加する（テスト用公開）
    /// 通常難易度のオフセット（normalSpriteOffset）を使用する
    /// counter: ペア番号（ユニーク名生成用）
    /// x: ペアの X 座標
    /// gapY: ギャップ中心の Y 座標
    pub def spawnPipePairAt(counter: Int32, x: Float64, gapY: Float64,
                            scene: Scene[NodeTag]): Scene[NodeTag] =
        let gapHeight = 2.0 * (normalSpriteOffset() - pipeHalfHeight());
        scene
            |> spawnPipe("pipe_${counter}_top", x, gapY - normalSpriteOffset(), topTexture())
            |> spawnPipe("pipe_${counter}_bottom", x, gapY + normalSpriteOffset(), bottomTexture())
            |> spawnCoin(counter, x, gapY, gapHeight)

    /// パイプペアをランダムな gapY で追加する
    /// スコアに応じた縦ギャップで配置する
    /// counter: ペア番号
    /// x: ペアの X 座標
    /// score: 現在のスコア（ギャップ幅の決定に使用）
    def spawnPipePair(counter: Int32, x: Float64, score: Int32,
                      scene: Scene[NodeTag]): Scene[NodeTag] \ Math.Random =
        let gapY = gapYMin() + (gapYMax() - gapYMin()) * Math.Random.randomFloat64();
        let offset = gapSpriteOffset(score);
        let gapHeight = 2.0 * (offset - pipeHalfHeight());
        scene
            |> spawnPipe("pipe_${counter}_top", x, gapY - offset, topTexture())
            |> spawnPipe("pipe_${counter}_bottom", x, gapY + offset, bottomTexture())
            |> spawnCoin(counter, x, gapY, gapHeight)

    /// 初期パイプ（3 ペア）を配置する
    /// score=0 の初心者向けギャップで配置する
    /// 戻り値: (更新されたシーン, 次のペア番号, 次のペア X 座標)
    pub def addPipes(scene: Scene[NodeTag]): (Scene[NodeTag], Int32, Float64) \ Math.Random =
        let spacing = pipeSpacingX();
        List.range(0, initialPipeCount())
            |> List.foldLeft((acc, _i) ->
                let (accScene, counter, nextX) = acc;
                let newScene = spawnPipePair(counter, nextX, 0, accScene);
                (newScene, counter + 1, nextX + spacing)
            , (scene, 0, firstPipeX()))

    // ========================================================================
    // パイプリサイクル
    // ========================================================================

    /// 画面外のパイプを削除し、右端に再スポーンする
    /// viewportLeftX: カメラが映す左端の X 座標
    /// pipeCounter: 次のペア番号（ユニーク名生成用）
    /// nextPipeX: 次のペアの X 座標
    /// score: 現在のスコア（縦ギャップの決定に使用）
    /// 戻り値: (更新されたシーン, 更新されたペア番号, 更新された次のペア X)
    pub def recyclePipes(viewportLeftX: Float64,
                         pipeCounter: Int32, nextPipeX: Float64,
                         score: Int32,
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
        // 削除数 / 3 = ペア数を再スポーン（top + bottom + coin = 3 ノード/ペア）
        let spacing = pipeSpacingX();
        let pairsToSpawn = List.length(offScreenPaths) / 3;
        List.range(0, pairsToSpawn)
            |> List.foldLeft((acc, _i) ->
                let (accScene, counter, nextX) = acc;
                let newScene = spawnPipePair(counter, nextX, score, accScene);
                (newScene, counter + 1, nextX + spacing)
            , (cleanedScene, pipeCounter, nextPipeX))
}
