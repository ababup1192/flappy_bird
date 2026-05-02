// CameraScene — カメラ追従とカメラシェイクの構築・更新
//
// Camera2D は指定ノードの x 座標を追従し、衝突時に短時間ランダム揺れ（シェイク）を発生させる。
// 追従対象のノード名とシェイク残量を CameraData にまとめ、Camera2DWithState の状態として保持する。
//
//   Camera2DWithState(camera, Camera(CameraData))

mod CameraScene {

    // ========================================================================
    // 型定義
    // ========================================================================

    /// カメラシェイクの残り時間と強度
    /// shakeRemaining: 残り秒数（0 以下になるとシェイク終了）
    /// shakeIntensity: 揺れ幅（ピクセル）。毎フレーム 0.9 倍で減衰する
    pub type alias ShakeData = {shakeRemaining = Float64, shakeIntensity = Float64}

    /// カメラ状態
    /// target: 追従対象ノードの名前（addCamera 時に固定）
    /// shake:  シェイクの進行状態
    pub type alias CameraData = {target = String, shake = ShakeData}

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

    /// カメラを追加する（FixedTopLeft、追従対象の初期位置に配置）
    /// target: 追従対象ノードの名前。以降 process はこの名前で位置を解決する
    pub def addCamera(target: String, scene: Scene[NodeTag]): Scene[NodeTag] =
        let targetPos = Scene.globalPosition(target, scene);
        let camera = Camera2D.makeWithOffset(
                {x = targetPos#x, y = 0.0},
                {x = offsetX(), y = 0.0})
            |> Camera2D.setAnchorMode(Camera2DAnchorMode.FixedTopLeft);
        scene |> Scene.addNode(cameraName(),
            EngineNode.Camera2DWithState(camera,
                NodeTag.Camera({target = target,
                                shake = {shakeRemaining = 0.0, shakeIntensity = 0.0}})))

    // ========================================================================
    // シェイク発火
    // ========================================================================

    /// カメラシェイクをトリガーする（target は据え置きで shake のみ更新）
    /// intensity: 揺れ幅（ピクセル）/ duration: 持続秒数
    pub def triggerShake(intensity: Float64, duration: Float64,
                         scene: Scene[NodeTag]): Scene[NodeTag] =
        match Scene.getState(cameraName() :: Nil, scene) {
            case Some(NodeTag.Camera(data)) =>
                Scene.setState(cameraName() :: Nil,
                    NodeTag.Camera({shake = {shakeRemaining = duration,
                                             shakeIntensity = intensity} | data}),
                    scene)
            case _ => scene
        }

    // ========================================================================
    // ロジック（process）
    // ========================================================================

    /// 追従対象の位置に合わせて 1 フレーム分カメラを更新する
    /// シェイク中は基準オフセットにランダム成分を加え、残り時間と強度を減衰させる
    /// シェイク非アクティブ時は基準オフセットに戻す（次フレームの揺れ残りを防ぐ）
    pub def process(delta: Float64, node: EngineNode[NodeTag],
                    scene: Scene[NodeTag]): (EngineNode[NodeTag], Scene[NodeTag]) \ Math.Random =
        match node {
            case EngineNode.Camera2DWithState(camera, NodeTag.Camera(data)) =>
                let targetPos = Scene.globalPosition(data#target, scene);
                let (offset, nextShake) = stepShake(data#shake, delta);
                let newCamera = camera
                    |> Node2D.setPosition({x = targetPos#x, y = 0.0})
                    |> Camera2D.setOffset(offset);
                (EngineNode.Camera2DWithState(newCamera,
                    NodeTag.Camera({shake = nextShake | data})), scene)
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
