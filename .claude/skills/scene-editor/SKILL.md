---
name: scene-editor
description: xxScene.flixを新規で作るとき・編集するとき、新しいゲームロジックを組む時に考えるべき設計パターン
user-invocable: false
---

# XxxScene 設計パターン

シーンの構築と更新に関する共通パターン。

## モジュール構造

```
mod XxxScene {
    // (A) 型定義   — SpriteData, AreaData
    // (B) 定数     — name / path / texture, speed, position
    // (C) 構築     — add: Scene → Scene
    // (D) ロジック — ready / process / start / input / move
    // (E) ボイラプレート mapXxxSprite / mapXxxArea / mapXxx（合成）
}
```

## (A) 型定義

### NodeTagのデータ設計

NodeTagで使うデータは、Sceneごとに使用されるデータ型を定義する。

```Game.flix
enum NodeTag {
    case Player(PlayerScene.Data)
    case PlayerArea(PlayerScene.AreaData)
    case CoinLabel(HUDScene.Coin)
}
```

プリミティブラッパーパターンは、データの意味を明確にし、可読性を高めるために有効:

```HUDScene.flix
pub type alias Coin = Int32
```

ノードツリー構造に合わせて、親ノードと子ノードのデータを分ける:
ルートノードのデータ型の場合は、`Data`として、プレフィックスを省略する

```PlayerScene.flix
// CharacterBody2D(Player)
//  └── Area2D (PlayerArea)

pub type alias Data = { velocity = Vec2.Vec2, hp = Int32 }
pub type alias AreaData = { hit = Bool }
```
## (B) 定数

Nodeの名前やパス, テクスチャ名は、定数で一元管理する。ハードコードは禁止。

```PlayerScene.flix
def name(): String = "xxx"
def xxxPath(): NodePath = name() :: Nil
def areaName(): String = "area"
def areaPath(): NodePath = name() :: areaName() :: Nil   // 非公開
def xxxTexture = "xxx.png"
def xxxBgm = "xxx_bgm.ogg"
```

パラメータ、物理パラメータなども定数で管理する:

```PlayerScene.flix
def speed(): Float64 = 100.0
def velocityY(): Float64 = -300.0
```

## (C) 構築 — add

ノードツリーを構築して、Sceneに追加する。
このときに、NodeTagと(A)で定義したデータ型(初期値)を紐づける。
さらに細かい単位で、Sceneに追加したい場合は、addXxx のような関数を追加する。

```flix
pub def add(scene: Scene[NodeTag]): Scene[NodeTag] =
    let sprite = AnimatedSprite2D.make(animations, initialAnimation = "idle",
        fps = 5.0, startPos, scale)
        |> CanvasItem.hide;
    let area = Area2D.make(Vec2.zero(), collisionShape);
    let xxxData = { velocity = Vec2.zero(), hp = 100 };
    scene
        |> Scene.addNode(name(),
            EngineNode.AnimSprite2DWithState(sprite,
                NodeTag.XxxSprite(xxxData)))           // 親: データを保持
        |> Scene.addChild(name(), areaName(),
            EngineNode.Area2DWithState(area,
                NodeTag.XxxArea))                       // 子: 識別タグ
```

動的スポーン（名前が実行時に決まる）の場合:

```flix
pub def spawnXxx(name: String, position: Vec2.Vec2,
                 scene: Scene[NodeTag]): Scene[NodeTag] =
    scene
        |> Scene.addNode(name,
            EngineNode.RigidBody2DWithState(body, NodeTag.XxxData(id)))
        |> Scene.addToGroup(name :: Nil, xxxGroup())    // グループで一括削除用
        |> Scene.addChild(name, childName(),
            EngineNode.AnimSprite2DWithState(sprite, NodeTag.NoTag))
```

構築 API:
- `Scene.addNode(name, engineNode)` — ルートに追加
- `Scene.addChild(parent, child, engineNode)` — 子を追加
- `Scene.addToGroup(path, group)` — グループに登録

## (D) ロジック

### ready / process / physicsProcess

ゲームエンジンでは、以下のライフサイクルが存在する。
各Sceneでは、ライフサイクルに応じたロジックを定義し、Game.flixは、各Sceneのライフサイクルロジックを呼び出し、委譲する。

- ready

**純粋スタイル** — エンジン型 + データを受け取り、更新して返す。Node instance 側でラップ/アンラップ:

```flix
// XxxScene 側
pub def ready(sprite: AnimatedSprite2D, data: XxxData
             ): (AnimatedSprite2D, XxxData) \ GameEngine.Game =
    (sprite, { screenSize = GameEngine.Game.getViewportRect()#size | data })

pub def process(dt: Float64, sprite: AnimatedSprite2D,
                data: XxxData): AnimatedSprite2D =
    Node2D.setPosition(
        Vec2.add(Node2D.getPosition(sprite), Vec2.mul(data#velocity, dt)),
        sprite)

// Node[NodeTag] instance 側（エンジン型は EngineNode の中だけ — 同期コード不要）
redef ready(node, _path, scene) = match node {
    case EngineNode.AnimSprite2DWithState(sprite, NodeTag.XxxSprite(data)) =>
        let (s, d) = XxxScene.ready(sprite, data);
        (EngineNode.AnimSprite2DWithState(s, NodeTag.XxxSprite(d)), scene)
    case _ => (node, scene)
}
```

**Scene スタイル** — path + scene を受け取り、内部で mapXxx を使う。複数ノードを触る場合に適する:

```flix
// XxxScene 側
pub def ready(path: NodePath, direction: Float64,
              scene: Scene[NodeTag]): Scene[NodeTag] \ Math.Random =
    scene |> mapXxx(path, (body, data) ->
        (RigidBody2D.setLinearVelocity(vel, body), data))

// Node[NodeTag] instance 側
redef ready(node, path, scene) = match node {
    case EngineNode.RigidBody2DWithState(_, NodeTag.XxxData(_)) =>
        let newScene = XxxScene.ready(path, direction, scene);
        // mapXxx が path のノードを更新済みなので、シーンから取り直す
        match Scene.getEngineNode(path, newScene) {
            case Some(en) => (en, newScene)
            case None     => (node, newScene)
        }
    case _ => (node, scene)
}
```

Scene スタイルでは、XxxScene.ready が scene 内のノードを更新するため、
Node instance 側は `Scene.getEngineNode` で取り直す（foldNodes の上書きを防ぐ）。

### その他のロジック

`mapXxxSprite` を使って scene を変換する:

```flix
pub def applyInput(dir: Vec2.Vec2, scene: Scene[NodeTag]): Scene[NodeTag] =
    scene |> mapXxxSprite((sprite, data) ->
        (updateAnimation(dir, sprite),
         { velocity = computeVelocity(dir) | data }))
```

sprite と area の両方を操作する場合は `mapXxx` を使う:

```flix
pub def start(pos: Vec2.Vec2, scene: Scene[NodeTag]): Scene[NodeTag] =
    scene |> mapXxx(
        (sprite, data) ->
            (sprite |> position(pos) |> show, { hit = false | data }),
        Area2D.setMonitoring(true))
```

単一ノードだけ操作する場合は `Scene.mapEngineNode` で十分:

```flix
pub def setText(text: String, scene: Scene[NodeTag]): Scene[NodeTag] =
    scene |> Scene.mapEngineNode(labelPath(),
        EngineNode.mapLabel2D(Label2D.setText(text)))
```

## (E) mapXxxSprite / mapXxxArea / mapXxx

コンポーネントごとに map 関数を用意し、合成で `mapXxx` を作る。

```
mapXxxSprite  ── sprite + XxxData を変換（親ノード操作）
mapXxxArea    ── Area2D を変換（子ノード操作）
mapXxx        ── mapXxxSprite >> mapXxxArea の合成
```

```flix
/// 親ノードの sprite と XxxData を変換する
pub def mapXxxSprite(f: (AnimatedSprite2D, XxxData) -> (AnimatedSprite2D, XxxData),
                     scene: Scene[NodeTag]): Scene[NodeTag] =
    Scene.mapEngineNode(xxxPath(), engineNode -> match engineNode {
        case EngineNode.AnimSprite2DWithState(sprite, NodeTag.XxxSprite(data)) =>
            let (newSprite, newData) = f(sprite, data);
            EngineNode.AnimSprite2DWithState(newSprite, NodeTag.XxxSprite(newData))
        case other => other
    }, scene)

/// 子ノードの Area2D を変換する
pub def mapXxxArea(f: Area2D -> Area2D, scene: Scene[NodeTag]): Scene[NodeTag] =
    Scene.mapEngineNode(areaPath(), EngineNode.mapArea2D(f), scene)

/// sprite・XxxData・Area2D をまとめて変換する（mapXxxSprite と mapXxxArea の合成）
pub def mapXxx(spriteF: (AnimatedSprite2D, XxxData) -> (AnimatedSprite2D, XxxData),
               areaF: Area2D -> Area2D,
               scene: Scene[NodeTag]): Scene[NodeTag] =
    scene |> mapXxxSprite(spriteF) |> mapXxxArea(areaF)

/// Scene から XxxData を取り出す
pub def getXxxData(scene: Scene[NodeTag]): XxxData =
    match Scene.getState(xxxPath(), scene) {
        case Some(NodeTag.XxxSprite(data)) => data
        case _ => bug!("xxx not found")
    }
```

### 設計の要点

1. **エンジン型の正本は EngineNode の中だけ** — `mapXxxSprite` は `Scene.mapEngineNode` 経由で操作するため、
   エンジン型のコピーが複数箇所に存在しない
2. **子ノードのパスを公開しない** — `mapXxxArea` が `areaPath()` をカプセル化する
3. **合成で拡張** — コンポーネントが増えたら `mapXxxNewChild` を追加し、`mapXxx` の合成に1段足すだけ

### 動的パス（実行時に名前が決まるノード）の場合

`path: NodePath` を引数に取る:

```flix
pub def mapXxxBody(path: NodePath,
                   f: (RigidBody2D, XxxData) -> (RigidBody2D, XxxData),
                   scene: Scene[NodeTag]): Scene[NodeTag] =
    Scene.mapEngineNode(path, engineNode -> match engineNode {
        case EngineNode.RigidBody2DWithState(body, NodeTag.XxxData(data)) =>
            let (newBody, newData) = f(body, data);
            EngineNode.RigidBody2DWithState(newBody, NodeTag.XxxData(newData))
        case other => other
    }, scene)
```

## 使い分け早見表

| やりたいこと | 手段 |
|---|---|
| sprite + data を変換 | `mapXxxSprite` |
| 子ノード（Area2D 等）を変換 | `mapXxxArea` |
| sprite + data + 子ノードを一括変換 | `mapXxx`（合成） |
| 単一ノードの見た目変更 | `Scene.mapEngineNode(path, f)` |
| 状態のみ変更 | `Scene.setState(path, newState)` / `Scene.mapState(path, f)` |
| ノード追加 | `Scene.addNode` / `Scene.addChild` |
| ノード削除 | `Scene.removeAt(path)` / `Scene.removeGroup(group)` |
| グループ一括削除 | `Scene.addToGroup` → `Scene.removeGroup` |
