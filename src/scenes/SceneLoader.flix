// SceneLoader — JSON ファイルからシーンツリーを構築する
//
// JSON のルートオブジェクトを Scene のルートに addNode として追加し、
// その children を addChildAt で再帰的に追加する。
// すべてのノードには NodeTag.NoTag が付与される（Phase 1）。
// 状態を持つ NodeTag（Bird, ScoreLabel など）が必要な場合は、
// 呼び出し側で読み込み後に Scene.setState で差し替えること。
//
// 対応ノード型: CanvasLayer / Sprite2D / TextureButton

mod SceneLoader {
    use Json.JsonElement.{JsonObject, JsonArray}
    use Json.JsonError.JsonError
    use Json.Path.Path.Root

    // ========================================================================
    // 公開 API
    // ========================================================================

    /// JSON ファイルを読み込み、scene にノードツリーを追加して返す。
    /// JSON のルートノードは addNode（シーンのルート）として追加され、
    /// その children は addChildAt で再帰的に追加される。
    /// 失敗（読み込み失敗・JSON パースエラー・未対応ノード型・必須キー欠落）時は
    /// bug! でクラッシュする
    pub def loadScene(path: String, scene: Scene[NodeTag]): Scene[NodeTag] \ Fs.FileRead =
        let content = run { Fs.ReadFile.read(path) } with Fs.ReadFile.runWithFileRead;
        let result = forM (
            text     <- content |> Result.mapErr(e -> "failed to read: ${e}");
            json     <- Json.Parse.parse(text) |> Option.toOk("JSON parse failed");
            outScene <- addJsonAt(Nil, json, scene)
                |> Result.mapErr(match JsonError(p, expected) ->
                    "at ${p}: expected ${expected}")
        ) yield outScene;
        match result {
            case Ok(s)    => s
            case Err(msg) => bug!("SceneLoader: ${path}: ${msg}")
        }

    // ========================================================================
    // JSON → Scene 変換
    // ========================================================================

    /// 指定された parentPath の子として JSON ノードを追加し、再帰的に children も追加する。
    /// parentPath が空のときはシーンのルートに addNode する
    def addJsonAt(parentPath: NodePath, json: Json.JsonElement,
                  scene: Scene[NodeTag]): Result[Json.JsonError, Scene[NodeTag]] =
        match json {
            case JsonObject(map) =>
                forM (
                    nodeType   <- (Json.getAtKey(Root, "type", map): Result[Json.JsonError, String]);
                    name       <- (Json.getAtKey(Root, "name", map): Result[Json.JsonError, String]);
                    engineNode <- buildByType(nodeType, map);
                    outScene   <- addChildren(
                                      parentPath ::: name :: Nil,
                                      map,
                                      addAt(parentPath, name, engineNode, scene))
                ) yield outScene
            case _ => Err(JsonError(Root, Set#{"JsonObject"}))
        }

    /// parentPath が空ならルート、そうでなければ子として追加する
    def addAt(parentPath: NodePath, name: String, engineNode: EngineNode[NodeTag],
              scene: Scene[NodeTag]): Scene[NodeTag] =
        match parentPath {
            case Nil => Scene.addNode(name, engineNode, scene)
            case _   => Scene.addChildAt(parentPath, name, engineNode, scene)
        }

    /// "children" 配列を順に走査して各要素を addJsonAt で追加する。
    /// children キーがなければ scene をそのまま返す
    def addChildren(parentPath: NodePath, map: Map[String, Json.JsonElement],
                    scene: Scene[NodeTag]): Result[Json.JsonError, Scene[NodeTag]] =
        match Map.get("children", map) {
            case None                 => Ok(scene)
            case Some(JsonArray(arr)) =>
                List.foldLeft(
                    (acc, child) -> Result.flatMap(s -> addJsonAt(parentPath, child, s), acc),
                    Ok(scene),
                    Vector.toList(arr))
            case Some(_)              => Err(JsonError(Root, Set#{"JsonArray"}))
        }

    // ========================================================================
    // ノード型ディスパッチ
    // ========================================================================

    /// "type" フィールドの値に応じて対応するノードビルダーを呼び出す
    def buildByType(nodeType: String,
                    map: Map[String, Json.JsonElement]): Result[Json.JsonError, EngineNode[NodeTag]] =
        match nodeType {
            case "CanvasLayer"   => buildCanvasLayer(map)
            case "Sprite2D"      => buildSprite2D(map)
            case "TextureButton" => buildTextureButton(map)
            case unknown         =>
                Err(JsonError(Root, Set#{"known node type (got: ${unknown})"}))
        }

    // ========================================================================
    // ヘルパー
    // ========================================================================

    /// JSON 配列 [x, y] を Vec2.Vec2 に変換する
    def parseVec2(key: String,
                  map: Map[String, Json.JsonElement]): Result[Json.JsonError, Vec2.Vec2] =
        forM (
            pair <- (Json.getAtKey(Root, key, map): Result[Json.JsonError, (Float64, Float64)])
        ) yield {
            let (x, y) = pair;
            {x = x, y = y}
        }

    // ========================================================================
    // ノード型ビルダー
    // ========================================================================

    /// CanvasLayer ノードを構築する。"layer" は描画レイヤー番号
    def buildCanvasLayer(map: Map[String, Json.JsonElement]): Result[Json.JsonError, EngineNode[NodeTag]] =
        forM (
            drawLayer <- (Json.getAtKey(Root, "layer", map): Result[Json.JsonError, Int32])
        ) yield EngineNode.CanvasLayerWithState(CanvasLayer.make(drawLayer), NodeTag.NoTag)

    /// Sprite2D ノードを構築する。"texture" / "pos" / "scale" が必須
    def buildSprite2D(map: Map[String, Json.JsonElement]): Result[Json.JsonError, EngineNode[NodeTag]] =
        forM (
            pos     <- parseVec2("pos", map);
            scale   <- parseVec2("scale", map);
            texture <- (Json.getAtKey(Root, "texture", map): Result[Json.JsonError, String])
        ) yield EngineNode.Sprite2DWithState(Sprite2D.make(texture, pos, scale), NodeTag.NoTag)

    /// TextureButton ノードを構築する。
    /// 必須: "textureNormal" / "pos" / "scale" / "size"
    /// 任意: "texturePressed" / "centered"（centered のデフォルトは TextureButton.make の既定値）
    def buildTextureButton(map: Map[String, Json.JsonElement]): Result[Json.JsonError, EngineNode[NodeTag]] =
        forM (
            pos               <- parseVec2("pos", map);
            scale             <- parseVec2("scale", map);
            size              <- parseVec2("size", map);
            textureNormal     <- (Json.getAtKey(Root, "textureNormal", map): Result[Json.JsonError, String]);
            texturePressedOpt <- (Json.getAtKeyOpt(Root, "texturePressed", map): Result[Json.JsonError, Option[String]]);
            centeredOpt       <- (Json.getAtKeyOpt(Root, "centered", map): Result[Json.JsonError, Option[Bool]])
        ) yield {
            let button = TextureButton.make(textureNormal, size)
                |> Node2D.setPosition(pos)
                |> Node2D.setScale(scale)
                |> applyTexturePressed(texturePressedOpt)
                |> applyCentered(centeredOpt);
            EngineNode.TextureButtonWithState(button, NodeTag.NoTag)
        }

    /// 任意の texturePressed を TextureButton に適用する（None ならそのまま返す）
    def applyTexturePressed(opt: Option[String], button: TextureButton): TextureButton =
        match opt {
            case Some(tex) => TextureButton.setTexturePressed(tex, button)
            case None      => button
        }

    /// 任意の centered を TextureButton に適用する（None ならそのまま返す）
    def applyCentered(opt: Option[Bool], button: TextureButton): TextureButton =
        match opt {
            case Some(c) => TextureButton.setCentered(c, button)
            case None    => button
        }
}
