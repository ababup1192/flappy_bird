---
name: engine-guide
description: "ゲームエンジン（Scene[s], EngineNode[s], GameEngine）のコードを書く前に参照するお作法ガイド。NodeTag設計、trait実装、衝突応答、動的スポーンを含む"
user-invocable: false
---

# ゲームエンジン お作法ガイド

## ファイル構成と責務

| ファイル | 責務 |
|---|---|
| `src/Main.flix` | EngineConfig + LwjglLayer 起動のみ |
| `src/scenes/Game.flix` | NodeTag enum, trait instance, mod Game（buildState・gameLoop） |
| `src/scenes/XxxScene.flix` | 個別シーンの構築・更新（scene-pattern 参照） |
| `src/engine/**` | エンジン層（通常は変更不要） |

## Main.flix — エントリポイント専用

ゲームロジックは一切書かない。EngineConfig の定義と起動だけ:

```flix
def main(): Unit \ IO =
    if (GameEngine.ensureMainThread()) ()
    else {
        let config: GameEngine.EngineConfig = {
            screenWidth = Game.screenWi(),
            screenHeight = Game.screenHi(),
            title = "My Game",
            textureManifest = {name = "hero", path = "textures/hero.png", hasAlpha = true} :: Nil,
            fontManifest = {name = "default", path = "textures/font.ttf", fontSize = 60.0} :: Nil,
            soundManifest = {name = "bgm", path = "sounds/bgm.ogg", looping = true} :: Nil,
            clearColor = {r = 0.0f32, g = 0.0f32, b = 0.0f32}
        };
        Math.Random.runWithIO(_ ->
            run { Game.start(GameEngine.Game.getFontAtlas("default")) }
            with LwjglLayer.withLwjgl(config)
        )
    }
```

## Game.flix — 構成順序

トップレベルに enum / type alias / instance、末尾に mod Game:

```
// 1. GamePhase enum
// 2. NodeTag enum
// 3. GameState type alias
// 4. Node[NodeTag] instance
// 5. AreaHandler[NodeTag] instance
// 6. ScreenNotifyHandler[NodeTag] instance（必要な場合）
// 7. TimerEvent.TimerHandler[NodeTag] instance（必要な場合）
// 8. mod Game { buildState, gameLoop, フェーズ遷移, ヘルパー }
```

### GameState type alias

scene とゲーム全体の状態を 1 レコードにまとめる:
基本は、SceneとGamePhaseだけ、内部状態は、次のNodeTagのenumに含める

```flix
pub type alias GameState = { scene = Scene[NodeTag], phase = GamePhase }
```


### NodeTag enum

NodeTagは、イベントのフックとして使われるSceneのノードに関連した識別情報を持つための列挙型。
さらにゲームの状態を識別情報とセットで持つバリアントも含める。
そうすることで、集約度が高くなり、Sceneのノードとゲームの状態を一元管理できる。
バリアントの命名規則として、xxSprite, xxArea, xxTimerのように、Node名を接頭辞にすることで、役割が明確になる。

```flix
type alias Score = Int32 // 状態はプリミティブ型の場合は、意味づけのための type alias で別名をつける

pub enum NodeTag {
    case xxxSprite(xxxData)                       // Sprite2D + データ
    case XxxArea                                  // 衝突判定を行うためのタグ状態は持たない
    case ScoreTimer(Score)                        // タイマー + スコア
    case NoTag                                    // イベントフックなし
}
```


## Game.flix と XxxScene の協業

### Node instance — XxxScene への委譲

`EngineNode × NodeTag` の二重 match で分岐し、XxxScene の関数に委譲する:
なるべく、各Sceneで ready, process, pyhisicProcess を定義することで、GameLoopはシンプルに保つ。
Game.flixに処理はなるべく書かない。

```flix
instance Node[NodeTag] {
    redef ready(node, path, scene) = match node {
        // 純粋スタイル: エンジン型 + データを渡し、戻り値を再ラップ
        case EngineNode.AnimSprite2DWithState(sprite, NodeTag.XxxState(n, data)) =>
            let (s, d) = XxxScene.ready(sprite, data);
            (EngineNode.AnimSprite2DWithState(s, NodeTag.XxxState({ sprite = s | n }, d)), scene)
        case _ => (node, scene)
    }

    redef process(delta, node, _path, scene) = match node {
        case EngineNode.AnimSprite2DWithState(sprite, NodeTag.XxxState(n, data)) =>
            let moved = XxxScene.process(delta, sprite, data);
            (EngineNode.AnimSprite2DWithState(moved, NodeTag.XxxState({ sprite = moved | n }, data)), scene)
        case _ => (node, scene)
    }

    physicProcess(delta, node, _path, scene) = match node {
        case EngineNode.AnimSprite2DWithState(sprite, NodeTag.XxxState(n, data)) =>
            let moved = XxxScene.physicsProcess(delta, sprite, data);
            (EngineNode.AnimSprite2DWithState(moved, NodeTag.XxxState({ sprite = moved | n }, data)), scene)
        case _ => (node, scene)
    }
}
```

### AreaHandler — 衝突応答

引数は NodeTag の値（EngineNode ではない）。scene を XxxScene の関数で変換:

```flix
instance AreaHandler[NodeTag] {
    pub def onAreaEntered(_selfPath, selfState, _otherPath, otherState, scene) =
        match (selfState, otherState) {
            case (NodeTag.XxxArea, NodeTag.YyyData(_)) =>
                scene |> XxxScene.mapXxx((node, data) ->
                    ({ sprite = CanvasItem.hide(node#sprite) | node },
                     { hit = true | data }))
            case _ => scene
        }
}
```

### TimerHandler — タイマーイベント

NodeTag バリアントで分岐。XxxScene の構築・操作関数を呼ぶ:

```flix
instance TimerEvent.TimerHandler[NodeTag] {
    redef onTimeout(timerPath, state, scene) = match state {
        case NodeTag.SpawnTimer(counter) =>
            let newScene = Game.spawnFromPath(counter, scene);
            Scene.setState(timerPath, NodeTag.SpawnTimer(counter + 1), newScene)
        case _ => scene
    }
}
```

### ScreenNotifyHandler — 画面外通知

```flix
instance ScreenNotifyHandler[NodeTag] {
    redef onScreenExited(path, state, scene) = match state {
        case NodeTag.YyyData(_) => Scene.removeAt(path, scene)
        case _ => scene
    }
}
```

## mod Game — buildState と gameLoop

### buildState

`Scene.empty()` に各 XxxScene.addXxx をパイプで繋ぎ、GameState を返す:

```flix
pub def buildState(fontAtlas: FontAtlas): GameState =
    { scene = Scene.empty()
          |> XxxScene.addXxx
          |> YyyScene.addYyy
          |> Scene.addNode("timer", EngineNode.TimerWithState(timer, NodeTag.SpawnTimer(0))),
      phase = GamePhase.Menu, score = 0 }
```

### エンジン更新パイプライン

GameEngine の関数を `>>` で連結:

```flix
def engineUpdate(dt: Float64, scene: Scene[NodeTag]): Scene[NodeTag] \ {...} =
    (GameEngine.process(dt, false)
    >> GameEngine.physicsProcess(dt, false, PhysicsStep.defaultGravity())
    >> GameEngine.emitCollision
    >> GameEngine.emitScreenNotify(screenWidth = screenWi(), screenHeight = screenHi())
    >> GameEngine.emitTimers)(scene)
```

### gameLoop

フェーズごとに match で処理を切り替え、末尾再帰:

```flix
def gameLoop(fontAtlas: FontAtlas, state: GameState): Unit \ {...} =
    if (GameEngine.Game.shouldClose()) ()
    else {
        let dt = GameEngine.Game.getDeltaTime();
        let nextState = match state#phase {
            case GamePhase.Playing =>
                let updatedScene = engineUpdate(dt, state#scene);
                { scene = updatedScene | state }
            case GamePhase.GameOver => ...
        };
        GameEngine.render(nextState#scene);
        gameLoop(fontAtlas, nextState)
    }
```

### フェーズ遷移

`GameState -> GameState` の関数として定義。XxxScene の操作関数をパイプで繋ぐ:

```flix
pub def newGame(state: GameState): GameState \ GameEngine.Audio =
    AudioStreamPlayer.play(bgmKey());
    let scene = state#scene
        |> Scene.removeGroup(YyyScene.yyyGroup())
        |> XxxScene.start(startPos)
        |> HudScene.showMessage("Get Ready");
    { scene = scene, phase = GamePhase.Playing, score = 0 }
```

## 注意事項

- NodeTag にエンジン型（Area2D, Sprite2D 等）をラップしない
- Main.flix にゲームロジックを書かない
- 動的スポーンの名前はカウンタ等でユニークにする
- 同一フレームで追加したノードの process は次フレームから
- Scene スタイルの ready では `Scene.getEngineNode` で取り直す（foldNodes の上書き防止）
