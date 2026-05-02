// BirdScene — Flappy Bird の鳥シーン構築・フラップ・回転制御
//
// 鳥は RigidBody2D（gravity_scale=1.0）で重力を受け、フラップで上昇する。
// 回転は物理エンジンの angularVelocity で制御し、physicsProcess の Flapping 分岐で
// -30° クランプと落下時 angVel = 1.5 を適用する（bird.gd FlappingState.update 準拠）。
// 衝突検知用の Area2D 子ノードを持つ。
//
//   RigidBody2DWithState(body, Bird(BirdData))
//     ├── AnimSprite2DWithState(sprite, NoTag)
//     └── Area2DWithState(area, BirdArea)

// ========================================================================
// 鳥の状態マシン
// ========================================================================

/// 鳥の状態遷移: Flying → Flapping → Hit → Grounded
/// Flying:   メニュー画面（重力なし）
/// Flapping: プレイ中（重力あり、フラップ操作可）
/// Hit:      パイプ衝突（移動停止、回転のみ）
/// Grounded: 地面着地（完全停止）
pub enum BirdState with Eq, ToString {
    case Flying
    case Flapping
    case Hit
    case Grounded
}

/// 鳥に届く入力イベント（bird.gd の `event` 引数相当）
/// キーボード押下とマウスボタン押下を統一的に扱う
pub enum BirdInputEvent with Eq, ToString {
    case KeyPressed(GameEngine.Key)
    case MouseButtonPressed(GameEngine.MouseButton)
}

/// 鳥の状態変化イベント（bird.gd の `state_changed` シグナル相当）
/// handleHit / handleGrounded 内で新状態と現在の Scene を emit し、ハンドラ側で
/// カメラシェイク等の副作用を行ってから新しい Scene を返す。
pub eff BirdStateChanged {
    def emit(newState: BirdState, scene: Scene[NodeTag]): Scene[NodeTag]
}

mod BirdScene {
    use NodeBuilder.{position, rotation, show, hide}

    // ========================================================================
    // 型定義
    // ========================================================================

    /// 鳥の状態データ（フレーム間で変化する純粋データ）
    /// state: 鳥の状態マシン
    /// speed: 横方向の移動速度（px/秒）
    pub type alias BirdData = {state = BirdState, speed = Float64}

    // ========================================================================
    // 定数 — ノード名・パス
    // ========================================================================

    /// 鳥のルートノード名
    pub def name(): String = "bird"

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

    /// 画面上端の Y 座標（鳥がこれより上に行かないようにクランプする）
    /// 本家 Flappy Bird 準拠: 上端で鳥が張り付き、上向き速度はゼロにする
    def ceilingY(): Float64 = 0.0

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
        let birdData: BirdData = {state = BirdState.Flapping, speed = birdSpeed()};
        scene
            |> Scene.addNode(name(),
                EngineNode.RigidBody2DWithState(body, NodeTag.Bird(birdData)))
            |> Scene.addChild(name(), spriteName(),
                EngineNode.AnimSprite2DWithState(sprite, NodeTag.NoTag))
            |> Scene.addChild(name(), areaName(),
                EngineNode.Area2DWithState(area, NodeTag.BirdArea))

    /// メニュー画面用の鳥をシーンに追加する
    /// Flying 状態・重力なし・速度ゼロで配置。ボビングアニメーションのみ行う
    pub def addBirdForMenu(scene: Scene[NodeTag]): Scene[NodeTag] =
        let body = RigidBody2D.make(startPosition(), birdCollisionShape())
            |> RigidBody2D.setGravityScale(0.0)
            |> RigidBody2D.setLinearVelocity(Vec2.zero());
        let sprite = AnimatedSprite2D.make(
            birdAnimations(),
            initialAnimation = flapAnimName(),
            fps = 10.0,
            Vec2.zero(),
            {x = 2.0, y = 2.0});
        let area = Area2D.make(Vec2.zero(), birdCollisionShape());
        let birdData: BirdData = {state = BirdState.Flying, speed = 0.0};
        scene
            |> Scene.addNode(name(),
                EngineNode.RigidBody2DWithState(body, NodeTag.Bird(birdData)))
            |> Scene.addChild(name(), spriteName(),
                EngineNode.AnimSprite2DWithState(sprite, NodeTag.NoTag))
            |> Scene.addChild(name(), areaName(),
                EngineNode.Area2DWithState(area, NodeTag.BirdArea))

 
    // ========================================================================
    // physicsProcess コールバック（bird.gd _physics_process 相当）
    // ========================================================================

    /// FlyingState.update(delta) — bird.gd: 何もしない（メニュー画面で重力ゼロ静止）
    def flyingUpdate(body: RigidBody2D): RigidBody2D = body

    /// FlappingState.update(delta) — bird.gd: 回転 -30° クランプ + 落下時 angVel = 1.5
    /// + 本家準拠の Y クランプ（Godot 版にはない独自追加）
    def flappingUpdate(body: RigidBody2D): RigidBody2D =
        let rot = Node2D.getRotation(body);
        let vel = RigidBody2D.getLinearVelocity(body);
        let pos = Node2D.getPosition(body);
        // bird.gd FlappingState.update と同順:
        //   1. rot < -30°  → rot=-30°, angVel=0
        //   2. vel.y > 0   → angVel=1.5  (上書き)
        let (rot1, angVel1) =
            if (rot < minRotation()) (minRotation(), 0.0)
            else (rot, RigidBody2D.getAngularVelocity(body));
        let angVel2 = if (vel#y > 0.0) fallAngularVelocity() else angVel1;
        // Y クランプ: 上端を超えたら位置を上端に戻し、上向き速度をゼロにする
        let (newPos, newVel) =
            if (pos#y < ceilingY())
                ({x = pos#x, y = ceilingY()}, {x = vel#x, y = Float64.max(vel#y, 0.0)})
            else (pos, vel);
        body
            |> Node2D.setPosition(newPos)
            |> Node2D.setRotation(rot1)
            |> RigidBody2D.setLinearVelocity(newVel)
            |> RigidBody2D.setAngularVelocity(angVel2)

    /// HitState.update(delta) — bird.gd: 何もしない（パイプ衝突後は回転加速のみ、物理積分に委任）
    def hitUpdate(body: RigidBody2D): RigidBody2D = body

    /// GroundedState.update(delta) — bird.gd: 何もしない（着地後は完全停止）
    def groundedUpdate(body: RigidBody2D): RigidBody2D = body

    /// bird.gd `flap()` 相当: y velocity を flapVelocityY、angular velocity を flapAngularVelocity に上書き
    /// x velocity は現在値を保持する（input / ready 両方ともこの挙動でよい）
    def flap(body: RigidBody2D): RigidBody2D =
        let vel = RigidBody2D.getLinearVelocity(body);
        body
            |> RigidBody2D.setLinearVelocity({x = vel#x, y = flapVelocityY()})
            |> RigidBody2D.setAngularVelocity(flapAngularVelocity())

    /// physicsProcess コールバック: bird.gd の `_physics_process(delta) → state.update(delta)` の Flix 移植
    /// 状態ごとに上記の per-state update 関数にディスパッチ
    /// Node[NodeTag] の Aef ({ Math.Random }) に合わせてエフェクトを宣言する
    pub def physicsProcess(_delta: Float64, node: EngineNode[NodeTag],
                           _path: NodePath, scene: Scene[NodeTag]
                          ): (EngineNode[NodeTag], Scene[NodeTag]) =
        match node {
            case EngineNode.RigidBody2DWithState(body, NodeTag.Bird(birdData)) =>
                let newBody = match birdData#state {
                    case BirdState.Flying => flyingUpdate(body)
                    case BirdState.Flapping => flappingUpdate(body)
                    case BirdState.Hit => hitUpdate(body)
                    case BirdState.Grounded => groundedUpdate(body)
                };
                (EngineNode.RigidBody2DWithState(newBody, NodeTag.Bird(birdData)), scene)
            case _ => (node, scene)
        }

    /// ready コールバック: bird.gd `FlappingState._init → flap()` 相当
    /// addBird で配置された Flapping 状態の鳥に初期 flap を適用する
    /// (addBirdForMenu の Flying 状態では何もしない)
    pub def ready(node: EngineNode[NodeTag], _path: NodePath,
                  scene: Scene[NodeTag]): (EngineNode[NodeTag], Scene[NodeTag]) =
        match node {
            case EngineNode.RigidBody2DWithState(body, NodeTag.Bird(birdData)) =>
                if (birdData#state == BirdState.Flapping) {
                    (EngineNode.RigidBody2DWithState(flap(body), NodeTag.Bird(birdData)), scene)
                } else {
                    (node, scene)
                }
            case _ => (node, scene)
        }

    /// input ディスパッチャ — bird.gd `_input(event) → state.input(event)` 相当
    /// Flapping 状態のみ flap 動作を実行し、他の状態は Godot に倣い no-op。
    /// メニュー / GameOver の遷移は Play ボタンクリック（MenuScene / GameOverScene）が担当する。
    pub def input(event: BirdInputEvent, scene: Scene[NodeTag]): Scene[NodeTag] \ GameEngine.Audio =
        let isFlapAction = match event {
            case BirdInputEvent.KeyPressed(GameEngine.Key.Space) => true
            case BirdInputEvent.MouseButtonPressed(GameEngine.MouseButton.Left) => true
            case _ => false
        };
        match getBirdData(scene)#state {
            case BirdState.Flapping =>
                if (isFlapAction) {
                    GameEngine.Audio.playAudio("sfx_wing");
                    scene |> mapBirdBody((body, birdData) -> (flap(body), birdData))
                } else scene
            case _ => scene
        }

    // ========================================================================
    // 状態遷移
    // ========================================================================

    /// 鳥を Hit 状態に遷移させる（bird.gd `HitState._init` 相当）
    /// 横移動停止、回転加速、衝突相手を collisionException に登録（sfx_hit + sfx_die）
    /// otherBodyPath: 衝突相手の StaticBody2D path。以降の物理衝突解決でこのペアは skip される。
    pub def handleHit(otherBodyPath: NodePath, scene: Scene[NodeTag]): Scene[NodeTag] \ {GameEngine.Audio, BirdStateChanged} =
        GameEngine.Audio.playAudio("sfx_hit");
        GameEngine.Audio.playAudio("sfx_die");
        let updatedScene = scene |> mapBirdBody((body, birdData) ->
            (body
                |> RigidBody2D.setLinearVelocity(Vec2.zero())
                |> RigidBody2D.setAngularVelocity(2.0)
                |> RigidBody2D.addCollisionException(otherBodyPath),
             {state = BirdState.Hit | birdData}));
        BirdStateChanged.emit(BirdState.Hit, updatedScene)

    /// 鳥を Grounded 状態に遷移させる（bird.gd `GroundedState._init` 相当）
    /// 停止（速度ゼロ、重力無効）。直前状態が Hit 以外なら sfx_hit を再生
    pub def handleGrounded(scene: Scene[NodeTag]): Scene[NodeTag] \ {GameEngine.Audio, BirdStateChanged} =
        if (getBirdData(scene)#state != BirdState.Hit)
            GameEngine.Audio.playAudio("sfx_hit")
        else ();
        let updatedScene = scene |> mapBirdBody((body, birdData) ->
            (body
                |> RigidBody2D.setLinearVelocity(Vec2.zero())
                |> RigidBody2D.setAngularVelocity(0.0)
                |> RigidBody2D.setGravityScale(0.0),
             {state = BirdState.Grounded | birdData}));
        BirdStateChanged.emit(BirdState.Grounded, updatedScene)

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

    /// 鳥の RigidBody2D が otherPath を collisionExceptions に登録しているか
    /// Hit 状態で別パイプに着地したかを判定するために使う
    pub def bodyHasCollisionException(otherPath: NodePath, scene: Scene[NodeTag]): Bool =
        match Scene.getEngineNode(birdPath(), scene) {
            case Some(EngineNode.RigidBody2DWithState(body, _)) =>
                RigidBody2D.hasCollisionException(otherPath, body)
            case _ => false
        }
}
