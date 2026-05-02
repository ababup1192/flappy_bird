// CameraScene — カメラ追従とカメラシェイクの構築・更新
//
// Camera2D は鳥の x 座標を追従し、衝突時に短時間ランダム揺れ（シェイク）を発生させる。
// シェイクの残り時間と強度は Camera2DWithState の状態として CameraShake(ShakeData) で保持する。
//
//   Camera2DWithState(camera, CameraShake(ShakeData))

mod CameraScene {

    // ========================================================================
    // 型定義
    // ========================================================================

    /// カメラシェイクの残り時間と強度
    /// shakeRemaining: 残り秒数（0 以下になるとシェイク終了）
    /// shakeIntensity: 揺れ幅（ピクセル）。毎フレーム 0.9 倍で減衰する
    pub type alias ShakeData = {shakeRemaining = Float64, shakeIntensity = Float64}

    // ========================================================================
    // 定数
    // ========================================================================

    /// カメラノード名
    def cameraName(): String = "camera"

    /// カメラオフセット X（参考実装 -36 の 2 倍）
    pub def offsetX(): Float64 = -72.0

    /// カメラシェイクの強度（ピクセル）
    pub def shakeIntensity(): Float64 = 3.0

    /// カメラシェイクの持続時間（秒）
    pub def shakeDuration(): Float64 = 0.18

    /// シェイクの減衰率（毎フレーム適用）
    def shakeDecay(): Float64 = 0.9

    // ========================================================================
    // シーン構築
    // ========================================================================

    /// カメラを追加する（FixedTopLeft、鳥の初期位置に配置）
    pub def addCamera(scene: Scene[NodeTag]): Scene[NodeTag] =
        let birdPos = Scene.globalPosition("bird", scene);
        let camera = Camera2D.makeWithOffset(
                {x = birdPos#x, y = 0.0},
                {x = offsetX(), y = 0.0})
            |> Camera2D.setAnchorMode(Camera2DAnchorMode.FixedTopLeft);
        scene |> Scene.addNode(cameraName(),
            EngineNode.Camera2DWithState(camera,
                NodeTag.CameraShake({shakeRemaining = 0.0, shakeIntensity = 0.0})))

    // ========================================================================
    // シェイク発火
    // ========================================================================

    /// カメラシェイクをトリガーする
    /// intensity: 揺れ幅（ピクセル）/ duration: 持続秒数
    pub def triggerShake(intensity: Float64, duration: Float64,
                         scene: Scene[NodeTag]): Scene[NodeTag] =
        Scene.setState(cameraName() :: Nil,
            NodeTag.CameraShake({shakeRemaining = duration, shakeIntensity = intensity}), scene)

    // ========================================================================
    // ロジック（process）
    // ========================================================================

    /// 鳥追従 + シェイク 1 フレーム分の更新
    /// シェイク中は基準オフセットにランダム成分を加え、残り時間と強度を減衰させる
    /// シェイク非アクティブ時は基準オフセットに戻す（次フレームの揺れ残りを防ぐ）
    pub def process(delta: Float64, node: EngineNode[NodeTag],
                    scene: Scene[NodeTag]): (EngineNode[NodeTag], Scene[NodeTag]) \ Math.Random =
        match node {
            case EngineNode.Camera2DWithState(camera, NodeTag.CameraShake(shakeData)) =>
                let birdPos = Scene.globalPosition(BirdScene.name(), scene);
                let (offset, nextShake) = stepShake(shakeData, delta);
                let newCamera = camera
                    |> Node2D.setPosition({x = birdPos#x, y = 0.0})
                    |> Camera2D.setOffset(offset);
                (EngineNode.Camera2DWithState(newCamera, NodeTag.CameraShake(nextShake)), scene)
            case _ => (node, scene)
        }

    /// シェイクの 1 フレーム進行を計算する
    /// 残り時間 > 0 → ランダムオフセット + 減衰した次状態 / それ以外 → 基準オフセット + 状態据え置き
    def stepShake(shakeData: ShakeData, delta: Float64):
            ({x = Float64, y = Float64}, ShakeData) \ Math.Random =
        let baseOffset = {x = offsetX(), y = 0.0};
        if (shakeData#shakeRemaining > 0.0) {
            let ox = (Math.Random.randomFloat64() - 0.5) * 2.0 * shakeData#shakeIntensity;
            let oy = (Math.Random.randomFloat64() - 0.5) * 2.0 * shakeData#shakeIntensity;
            ({x = baseOffset#x + ox, y = baseOffset#y + oy},
             {shakeRemaining = shakeData#shakeRemaining - delta,
              shakeIntensity = shakeData#shakeIntensity * shakeDecay()})
        } else (baseOffset, shakeData)
}
