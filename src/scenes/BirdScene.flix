// BirdScene — Flappy Bird の鳥シーン構築・フラップ・回転制御
//
// 鳥は RigidBody2D（gravity_scale=1.0）で重力を受け、フラップで上昇する。
// 回転は物理エンジンの angularVelocity で制御し、フラップ後のクランプは
// 物理積分の後に呼び出す clampRotation で行う。
// 衝突検知用の Area2D 子ノードを持つ。
//
//   RigidBody2DWithState(body, Bird(BirdData))
//     ├── AnimSprite2DWithState(sprite, NoTag)
//     └── Area2DWithState(area, BirdArea)

mod BirdScene {
    use NodeBuilder.{position, rotation, show, hide}

    // ========================================================================
    // 型定義
    // ========================================================================

    /// 鳥の状態データ（フレーム間で変化する純粋データ）
    /// state: 鳥の状態マシン
    /// speed: 横方向の移動速度（px/秒）
    /// flapRequested: フラップリクエスト（次の physicsProcess で適用される）
    /// flapPressed: 前フレームでフラップ入力があったか（連続入力防止用）
    pub type alias BirdData = {state = BirdState, speed = Float64, flapRequested = Bool, flapPressed = Bool}

    // ========================================================================
    // 定数 — ノード名・パス
    // ========================================================================

    /// 鳥のルートノード名
    def name(): String = "bird"

    /// 鳥のルートノードパス
    pub def birdPath(): NodePath = name() :: Nil

    /// スプライト子ノード名
    def spriteName(): String = "sprite"

    /// スプライト子ノードパス
    pub def spritePath(): NodePath = name() :: spriteName() :: Nil

    /// 衝突検知用 Area2D 子ノード名
    def areaName(): String = "area"

    /// 衝突検知用 Area2D 子ノードパス
    pub def areaPath(): NodePath = name() :: areaName() :: Nil

    // ========================================================================
    // 定数 — 物理パラメータ（2x スケール）
    // ========================================================================

    /// 横方向の移動速度（px/秒）。参考実装の 50 を 2 倍した値
    def birdSpeed(): Float64 = 100.0

    /// フラップ時の上方向初速度（px/秒）。参考実装の -150 を 2 倍した値
    def flapVelocityY(): Float64 = -300.0

    /// フラップ時の角速度（rad/秒）。反時計回り（上を向く）
    def flapAngularVelocity(): Float64 = -3.0

    /// 落下時の角速度下限（rad/秒）。時計回り（下を向く）
    def fallAngularVelocity(): Float64 = 1.5

    /// 上方向の回転上限（-30° = -π/6 rad）
    def minRotationDeg(): Float64 = -30.0

    /// -30° をラジアンに変換した値
    def minRotation(): Float64 = minRotationDeg() * Vec2.pi() / 180.0

    /// 重力倍率
    /// 参考実装: Godot 3.x デフォルト重力 98 × gravity_scale 5.0 = 490 px/s²
    /// 2x スケール: 490 × 2 = 980 px/s²
    /// エンジン重力 980 × gravity_scale 1.0 = 980 px/s²
    def birdGravityScale(): Float64 = 1.0

    // ========================================================================
    // 定数 — 衝突形状・アニメーション
    // ========================================================================

    /// 鳥の衝突形状（CircleShape2D, 半径 13px = 参考実装 6.5 の 2 倍）
    def birdCollisionShape(): CollisionShape2D =
        CollisionShape2D.CircleShape2D({radius = 13.0})

    /// アニメーション名
    def flapAnimName(): String = "flap"

    /// 鳥のアニメーション定義（3 フレーム）
    def birdAnimations(): Map[String, List[String]] =
        Map#{
            flapAnimName() => ("bird_orange_0" :: "bird_orange_1" :: "bird_orange_2" :: Nil)
        }

    /// 鳥の初期位置（画面中央付近）
    def startPosition(): Vec2.Vec2 = {x = 144.0, y = 256.0}

    // ========================================================================
    // シーン構築
    // ========================================================================

    /// 鳥のノードをシーンに追加する
    /// RigidBody2D（物理ボディ）+ AnimatedSprite2D（見た目）+ Area2D（衝突検知）
    pub def addBird(scene: Scene[NodeTag]): Scene[NodeTag] =
        let body = RigidBody2D.make(startPosition(), birdCollisionShape())
            |> RigidBody2D.setGravityScale(birdGravityScale())
            |> RigidBody2D.setLinearVelocity({x = birdSpeed(), y = 0.0});
        let sprite = AnimatedSprite2D.make(
            birdAnimations(),
            initialAnimation = flapAnimName(),
            fps = 10.0,
            Vec2.zero(),
            {x = 2.0, y = 2.0});
        let area = Area2D.make(Vec2.zero(), birdCollisionShape());
        let birdData: BirdData = {state = BirdState.Flapping, speed = birdSpeed(), flapRequested = false, flapPressed = false};
        scene
            |> Scene.addNode(name(),
                EngineNode.RigidBody2DWithState(body, NodeTag.Bird(birdData)))
            |> Scene.addChild(name(), spriteName(),
                EngineNode.AnimSprite2DWithState(sprite, NodeTag.NoTag))
            |> Scene.addChild(name(), areaName(),
                EngineNode.Area2DWithState(area, NodeTag.BirdArea))

    // ========================================================================
    // フラップ
    // ========================================================================

    /// フラップを実行する: Y 方向の速度を上方向にセットし、角速度を反時計回りにする
    /// Flapping 状態のときのみ有効
    pub def flap(scene: Scene[NodeTag]): Scene[NodeTag] =
        scene |> mapBirdBody((body, birdData) ->
            match birdData#state {
                case BirdState.Flapping =>
                    let vel = RigidBody2D.getLinearVelocity(body);
                    (body
                        |> RigidBody2D.setLinearVelocity({x = vel#x, y = flapVelocityY()})
                        |> RigidBody2D.setAngularVelocity(flapAngularVelocity()),
                     birdData)
                case _ => (body, birdData)
            })

    // ========================================================================
    // フラップリクエスト（gameLoop → physicsProcess 連携用）
    // ========================================================================

    /// フラップリクエストをセットする（次の physicsProcess で速度に反映される）
    /// Flapping 状態のときのみ有効
    pub def requestFlap(scene: Scene[NodeTag]): Scene[NodeTag] =
        scene |> mapBirdBody((body, birdData) ->
            match birdData#state {
                case BirdState.Flapping => (body, {flapRequested = true | birdData})
                case _ => (body, birdData)
            })

    /// 前フレームのフラップ入力状態を更新する
    pub def setFlapPressed(pressed: Bool, scene: Scene[NodeTag]): Scene[NodeTag] =
        scene |> mapBirdBody((body, birdData) ->
            (body, {flapPressed = pressed | birdData}))

    // ========================================================================
    // physicsProcess コールバック（物理積分の前に呼ばれる）
    // ========================================================================

    /// physicsProcess コールバック: フラップ速度適用と落下時の角速度制御
    /// フラップリクエストがあれば速度を設定し、なければ落下状態に応じて角速度を制御する
    pub def birdPhysicsProcess(body: RigidBody2D, birdData: BirdData): (RigidBody2D, BirdData) =
        match birdData#state {
            case BirdState.Flapping =>
                if (birdData#flapRequested) {
                    let vel = RigidBody2D.getLinearVelocity(body);
                    (body
                        |> RigidBody2D.setLinearVelocity({x = vel#x, y = flapVelocityY()})
                        |> RigidBody2D.setAngularVelocity(flapAngularVelocity()),
                     {flapRequested = false | birdData})
                } else {
                    let vel = RigidBody2D.getLinearVelocity(body);
                    let angVel = if (vel#y > 0.0) fallAngularVelocity()
                                 else RigidBody2D.getAngularVelocity(body);
                    (body |> RigidBody2D.setAngularVelocity(angVel), birdData)
                }
            case _ => (body, {flapRequested = false | birdData})
        }

    // ========================================================================
    // process コールバック（毎フレーム先頭で呼ばれる）
    // ========================================================================

    /// process コールバック: 前フレームの物理積分後の回転角をクランプする
    /// 回転が -30° 未満なら -30° に固定し角速度を 0 にする
    pub def birdProcess(body: RigidBody2D, birdData: BirdData): (RigidBody2D, BirdData) =
        match birdData#state {
            case BirdState.Flapping =>
                let rot = Node2D.getRotation(body);
                if (rot < minRotation())
                    (body
                        |> Node2D.setRotation(minRotation())
                        |> RigidBody2D.setAngularVelocity(0.0),
                     birdData)
                else
                    (body, birdData)
            case _ => (body, birdData)
        }

    // ========================================================================
    // 回転制御（物理積分の後に呼ぶ）
    // ========================================================================

    /// 物理積分後に回転と角速度をクランプする（参考実装準拠）
    /// 1. 回転が -30° 未満なら -30° に固定し角速度を 0 にする
    /// 2. 落下中（linear_velocity.y > 0）なら角速度を 1.5 にする
    pub def clampRotation(scene: Scene[NodeTag]): Scene[NodeTag] =
        scene |> mapBirdBody((body, birdData) ->
            match birdData#state {
                case BirdState.Flapping =>
                    let rot = Node2D.getRotation(body);
                    let vel = RigidBody2D.getLinearVelocity(body);
                    let (clampedRot, angVel1) =
                        if (rot < minRotation())
                            (minRotation(), 0.0)
                        else
                            (rot, RigidBody2D.getAngularVelocity(body));
                    let angVel2 = if (vel#y > 0.0) fallAngularVelocity()
                                  else angVel1;
                    (body
                        |> Node2D.setRotation(clampedRot)
                        |> RigidBody2D.setAngularVelocity(angVel2),
                     birdData)
                case _ => (body, birdData)
            })

    // ========================================================================
    // 状態遷移
    // ========================================================================

    /// 鳥の状態を変更し、状態に応じた物理パラメータを設定する
    /// Grounded: 停止（速度ゼロ、重力無効）
    /// Hit: 横移動停止、回転加速（パイプ衝突後の落下演出）
    pub def setBirdState(newState: BirdState, scene: Scene[NodeTag]): Scene[NodeTag] =
        scene |> mapBirdBody((body, birdData) ->
            let updatedData = {state = newState | birdData};
            match newState {
                case BirdState.Grounded =>
                    (body
                        |> RigidBody2D.setLinearVelocity(Vec2.zero())
                        |> RigidBody2D.setAngularVelocity(0.0)
                        |> RigidBody2D.setGravityScale(0.0),
                     updatedData)
                case BirdState.Hit =>
                    (body
                        |> RigidBody2D.setLinearVelocity(Vec2.zero())
                        |> RigidBody2D.setAngularVelocity(2.0),
                     updatedData)
                case _ =>
                    (body, updatedData)
            })

    // ========================================================================
    // ヘルパー: RigidBody2D と BirdData の変換・取得
    // ========================================================================

    /// 鳥の RigidBody2D と BirdData を変換する
    pub def mapBirdBody(f: (RigidBody2D, BirdData) -> (RigidBody2D, BirdData),
                        scene: Scene[NodeTag]): Scene[NodeTag] =
        Scene.mapEngineNode(birdPath(), engineNode -> match engineNode {
            case EngineNode.RigidBody2DWithState(body, NodeTag.Bird(birdData)) =>
                let (newBody, newData) = f(body, birdData);
                EngineNode.RigidBody2DWithState(newBody, NodeTag.Bird(newData))
            case other => other
        }, scene)

    /// Scene から BirdData を取り出す
    pub def getBirdData(scene: Scene[NodeTag]): BirdData =
        match Scene.getState(birdPath(), scene) {
            case Some(NodeTag.Bird(birdData)) => birdData
            case _ => bug!("bird not found")
        }
}
