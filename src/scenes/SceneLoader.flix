// SceneLoader — JSON ファイルからシーンツリーを構築する
//
// JSON のルートは単一オブジェクト or 配列を受け付ける。
// 配列の場合は各要素を独立したルートノードとして scene に addNode する。
// オブジェクトの場合は単一ルートノードとして addNode し、その children を再帰的に追加する。
//
// 各ノードに付与する NodeTag は JSON の "tag" フィールドで指定する。
// 状態を持つ NodeTag（Bird, ScoreLabel, Camera, GameOverAnim）は JSON で指定できないため、
// 呼び出し側で読み込み後に Scene.setState で差し替えること。
//
// Label2D を含むシーンは loadSceneWithFont を使う（FontAtlas が必要）。
// それ以外は loadScene を使う。
//
// 対応ノード型: CanvasLayer / Sprite2D / TextureButton / StaticBody2D / Label2D
// 対応 tag: Ground / Pipe / PipePart / Coin / BirdArea / NoTag（デフォルト）
// 対応 collision shape: RectShape2D / CircleShape2D

mod SceneLoader {
    use Json.JsonElement.{JsonObject, JsonArray}
    use Json.JsonError.JsonError
    use Json.Path.Path.Root

    // ========================================================================
    // 公開 API
    // ========================================================================

    /// JSON ファイルを読み込み、scene にノードツリーを追加して返す。
    /// JSON のルートが配列なら各要素をルートノードとして addNode、
    /// 単一オブジェクトなら単一ルートノードとして addNode する。
    /// children は addChildAt で再帰的に追加される。
    /// Label2D を含む JSON では loadSceneWithFont を使うこと（FontAtlas が必須）。
    /// 失敗（読み込み失敗・JSON パースエラー・未対応ノード型・必須キー欠落）時は
    /// bug! でクラッシュする
    pub def loadScene(path: String, scene: Scene[NodeTag]): Scene[NodeTag] \ Fs.FileRead =
        loadSceneCore(path, None, scene)

    /// FontAtlas 付きで JSON ファイルを読み込む（Label2D を含むシーン用）。
    /// その他は loadScene と同じ振る舞い
    pub def loadSceneWithFont(path: String, fontAtlas: FontAtlas,
                              scene: Scene[NodeTag]): Scene[NodeTag] \ Fs.FileRead =
        loadSceneCore(path, Some(fontAtlas), scene)

    // ========================================================================
    // 内部実装（fontAtlas を Option で全体に伝播する）
    // ========================================================================

    /// 共通実装。fontAtlas が None の場合 Label2D ビルダーは Err を返す
    def loadSceneCore(path: String, fontAtlas: Option[FontAtlas],
                      scene: Scene[NodeTag]): Scene[NodeTag] \ Fs.FileRead =
        let content = run { Fs.ReadFile.read(path) } with Fs.ReadFile.runWithFileRead;
        let result = forM (
            text     <- content |> Result.mapErr(e -> "failed to read: ${e}");
            // 末尾改行で flix-json の eoi が失敗するため事前に trim する
            json     <- Json.Parse.parse(String.trim(text)) |> Option.toOk("JSON parse failed");
            outScene <- addJsonAtTop(fontAtlas, json, scene)
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

    /// JSON ルートを処理する。配列なら各要素を、オブジェクトなら単一ノードを
    /// シーンのルートに追加する
    def addJsonAtTop(fontAtlas: Option[FontAtlas], json: Json.JsonElement,
                     scene: Scene[NodeTag]): Result[Json.JsonError, Scene[NodeTag]] =
        match json {
            case JsonObject(_)        => addJsonAt(Nil, fontAtlas, json, scene)
            case JsonArray(arr)       =>
                List.foldLeft(
                    (acc, child) -> Result.flatMap(s -> addJsonAt(Nil, fontAtlas, child, s), acc),
                    Ok(scene),
                    Vector.toList(arr))
            case _                    => Err(JsonError(Root, Set#{"JsonObject or JsonArray"}))
        }

    /// 指定された parentPath の子として JSON ノードを追加し、再帰的に children も追加する。
    /// parentPath が空のときはシーンのルートに addNode する
    def addJsonAt(parentPath: NodePath, fontAtlas: Option[FontAtlas],
                  json: Json.JsonElement,
                  scene: Scene[NodeTag]): Result[Json.JsonError, Scene[NodeTag]] =
        match json {
            case JsonObject(map) =>
                forM (
                    nodeType   <- (Json.getAtKey(Root, "type", map): Result[Json.JsonError, String]);
                    name       <- (Json.getAtKey(Root, "name", map): Result[Json.JsonError, String]);
                    engineNode <- buildByType(nodeType, fontAtlas, map);
                    groups     <- parseGroups(map);
                    outScene   <- {
                        let nodePath = parentPath ::: name :: Nil;
                        let added = addAt(parentPath, name, engineNode, scene)
                            |> applyGroups(nodePath, groups);
                        addChildren(nodePath, fontAtlas, map, added)
                    }
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
    def addChildren(parentPath: NodePath, fontAtlas: Option[FontAtlas],
                    map: Map[String, Json.JsonElement],
                    scene: Scene[NodeTag]): Result[Json.JsonError, Scene[NodeTag]] =
        match Map.get("children", map) {
            case None                 => Ok(scene)
            case Some(JsonArray(arr)) =>
                List.foldLeft(
                    (acc, child) -> Result.flatMap(s -> addJsonAt(parentPath, fontAtlas, child, s), acc),
                    Ok(scene),
                    Vector.toList(arr))
            case Some(_)              => Err(JsonError(Root, Set#{"JsonArray"}))
        }

    /// ノードに groups を適用する（リストが空なら scene そのまま）
    def applyGroups(path: NodePath, groups: List[String],
                    scene: Scene[NodeTag]): Scene[NodeTag] =
        List.foldLeft((acc, group) -> Scene.addToGroup(path, group, acc), scene, groups)

    // ========================================================================
    // ノード型ディスパッチ
    // ========================================================================

    /// "type" フィールドの値に応じて対応するノードビルダーを呼び出す
    def buildByType(nodeType: String, fontAtlas: Option[FontAtlas],
                    map: Map[String, Json.JsonElement]): Result[Json.JsonError, EngineNode[NodeTag]] =
        match nodeType {
            case "CanvasLayer"   => buildCanvasLayer(map)
            case "Sprite2D"      => buildSprite2D(map)
            case "TextureButton" => buildTextureButton(map)
            case "StaticBody2D"  => buildStaticBody2D(map)
            case "Label2D"       => buildLabel2D(fontAtlas, map)
            case unknown         =>
                Err(JsonError(Root, Set#{"known node type (got: ${unknown})"}))
        }

    // ========================================================================
    // 共通フィールドの解析（tag / groups / shape / vec2）
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

    /// 任意の "tag" フィールドを NodeTag に変換する。
    /// キーがなければ NodeTag.NoTag を返す。
    /// 状態を持つ NodeTag（Bird, ScoreLabel, Camera, GameOverAnim）は JSON で指定できない
    def parseTag(map: Map[String, Json.JsonElement]): Result[Json.JsonError, NodeTag] =
        forM (
            tagOpt <- (Json.getAtKeyOpt(Root, "tag", map): Result[Json.JsonError, Option[String]]);
            tag    <- nodeTagFromString(tagOpt)
        ) yield tag

    /// "tag" 文字列を NodeTag に変換する。未対応の値は Err を返す
    def nodeTagFromString(opt: Option[String]): Result[Json.JsonError, NodeTag] =
        match opt {
            case None              => Ok(NodeTag.NoTag)
            case Some("NoTag")     => Ok(NodeTag.NoTag)
            case Some("Ground")    => Ok(NodeTag.Ground)
            case Some("Pipe")      => Ok(NodeTag.Pipe)
            case Some("PipePart")  => Ok(NodeTag.PipePart)
            case Some("Coin")      => Ok(NodeTag.Coin)
            case Some("BirdArea")  => Ok(NodeTag.BirdArea)
            case Some(unknown)     =>
                Err(JsonError(Root, Set#{"known tag (got: ${unknown})"}))
        }

    /// 任意の "groups" フィールドを List[String] に変換する。キーがなければ空リスト
    def parseGroups(map: Map[String, Json.JsonElement]): Result[Json.JsonError, List[String]] =
        forM (
            opt <- (Json.getAtKeyOpt(Root, "groups", map): Result[Json.JsonError, Option[List[String]]])
        ) yield Option.getWithDefault(Nil, opt)

    /// "shape" オブジェクトから CollisionShape2D を構築する。
    /// "kind" で形状を識別し、形状ごとの追加フィールドを読み取る
    def parseShape(map: Map[String, Json.JsonElement]): Result[Json.JsonError, CollisionShape2D] =
        forM (
            shapeMap <- (Json.getAtKey(Root, "shape", map): Result[Json.JsonError, Map[String, Json.JsonElement]]);
            kind     <- (Json.getAtKey(Root, "kind", shapeMap): Result[Json.JsonError, String]);
            shape    <- buildShape(kind, shapeMap)
        ) yield shape

    /// shape の "kind" に応じて対応する CollisionShape2D ビルダーを呼び出す
    def buildShape(kind: String,
                   map: Map[String, Json.JsonElement]): Result[Json.JsonError, CollisionShape2D] =
        match kind {
            case "RectShape2D" =>
                forM (
                    width  <- (Json.getAtKey(Root, "width", map): Result[Json.JsonError, Float64]);
                    height <- (Json.getAtKey(Root, "height", map): Result[Json.JsonError, Float64])
                ) yield CollisionShape2D.RectShape2D({width = width, height = height})
            case "CircleShape2D" =>
                forM (
                    radius <- (Json.getAtKey(Root, "radius", map): Result[Json.JsonError, Float64])
                ) yield CollisionShape2D.CircleShape2D({radius = radius})
            case unknown =>
                Err(JsonError(Root, Set#{"known shape kind (got: ${unknown})"}))
        }

    // ========================================================================
    // ノード型ビルダー
    // ========================================================================

    /// CanvasLayer ノードを構築する。"layer" は描画レイヤー番号
    def buildCanvasLayer(map: Map[String, Json.JsonElement]): Result[Json.JsonError, EngineNode[NodeTag]] =
        forM (
            tag       <- parseTag(map);
            drawLayer <- (Json.getAtKey(Root, "layer", map): Result[Json.JsonError, Int32])
        ) yield EngineNode.CanvasLayerWithState(CanvasLayer.make(drawLayer), tag)

    /// Sprite2D ノードを構築する。
    /// 必須: "texture" / "pos" / "scale"
    /// 任意: "zIndex"（描画順） / "visible"（表示フラグ）
    def buildSprite2D(map: Map[String, Json.JsonElement]): Result[Json.JsonError, EngineNode[NodeTag]] =
        forM (
            tag        <- parseTag(map);
            pos        <- parseVec2("pos", map);
            scale      <- parseVec2("scale", map);
            texture    <- (Json.getAtKey(Root, "texture", map): Result[Json.JsonError, String]);
            zIndexOpt  <- (Json.getAtKeyOpt(Root, "zIndex", map): Result[Json.JsonError, Option[Int32]]);
            visibleOpt <- (Json.getAtKeyOpt(Root, "visible", map): Result[Json.JsonError, Option[Bool]])
        ) yield {
            let sprite = Sprite2D.make(texture, pos, scale)
                |> applyZIndex(zIndexOpt)
                |> applyVisible(visibleOpt);
            EngineNode.Sprite2DWithState(sprite, tag)
        }

    /// TextureButton ノードを構築する。
    /// 必須: "textureNormal" / "pos" / "scale" / "size"
    /// 任意: "texturePressed" / "centered" / "visible"
    def buildTextureButton(map: Map[String, Json.JsonElement]): Result[Json.JsonError, EngineNode[NodeTag]] =
        forM (
            tag               <- parseTag(map);
            pos               <- parseVec2("pos", map);
            scale             <- parseVec2("scale", map);
            size              <- parseVec2("size", map);
            textureNormal     <- (Json.getAtKey(Root, "textureNormal", map): Result[Json.JsonError, String]);
            texturePressedOpt <- (Json.getAtKeyOpt(Root, "texturePressed", map): Result[Json.JsonError, Option[String]]);
            centeredOpt       <- (Json.getAtKeyOpt(Root, "centered", map): Result[Json.JsonError, Option[Bool]]);
            visibleOpt        <- (Json.getAtKeyOpt(Root, "visible", map): Result[Json.JsonError, Option[Bool]])
        ) yield {
            let button = TextureButton.make(textureNormal, size)
                |> Node2D.setPosition(pos)
                |> Node2D.setScale(scale)
                |> applyTexturePressed(texturePressedOpt)
                |> applyCentered(centeredOpt)
                |> applyButtonVisible(visibleOpt);
            EngineNode.TextureButtonWithState(button, tag)
        }

    /// StaticBody2D ノードを構築する。
    /// 必須: "pos" / "shape"
    def buildStaticBody2D(map: Map[String, Json.JsonElement]): Result[Json.JsonError, EngineNode[NodeTag]] =
        forM (
            tag   <- parseTag(map);
            pos   <- parseVec2("pos", map);
            shape <- parseShape(map)
        ) yield EngineNode.StaticBody2DWithState(StaticBody2D.make(pos, shape), tag)

    /// Label2D ノードを構築する。
    /// 必須: "text" / "pos" / "fontSize"
    /// 任意: "centered" / "visible" / "zIndex"
    /// fontAtlas が None の場合は Err を返す（Label2D は font が必須なため）
    def buildLabel2D(fontAtlas: Option[FontAtlas],
                     map: Map[String, Json.JsonElement]): Result[Json.JsonError, EngineNode[NodeTag]] =
        match fontAtlas {
            case None => Err(JsonError(Root, Set#{"FontAtlas (loadSceneWithFont required for Label2D)"}))
            case Some(font) =>
                forM (
                    tag         <- parseTag(map);
                    text        <- (Json.getAtKey(Root, "text", map): Result[Json.JsonError, String]);
                    pos         <- parseVec2("pos", map);
                    fontSize    <- (Json.getAtKey(Root, "fontSize", map): Result[Json.JsonError, Float64]);
                    centeredOpt <- (Json.getAtKeyOpt(Root, "centered", map): Result[Json.JsonError, Option[Bool]]);
                    visibleOpt  <- (Json.getAtKeyOpt(Root, "visible", map): Result[Json.JsonError, Option[Bool]]);
                    zIndexOpt   <- (Json.getAtKeyOpt(Root, "zIndex", map): Result[Json.JsonError, Option[Int32]])
                ) yield {
                    let label = Label2D.make(text, font, fontSize)
                        |> Node2D.setPosition(pos)
                        |> applyLabelCentered(centeredOpt)
                        |> applyLabelVisible(visibleOpt)
                        |> applyLabelZIndex(zIndexOpt);
                    EngineNode.Label2DWithState(label, tag)
                }
        }

    // ========================================================================
    // ビルダー用ヘルパー（任意フィールド適用）
    // ========================================================================

    /// 任意の zIndex を Sprite2D に適用する（None ならそのまま返す）
    def applyZIndex(opt: Option[Int32], sprite: Sprite2D): Sprite2D =
        match opt {
            case Some(zIndex) => CanvasItem.setZIndex(zIndex, sprite)
            case None         => sprite
        }

    /// 任意の visible を Sprite2D に適用する（None ならそのまま返す）
    def applyVisible(opt: Option[Bool], sprite: Sprite2D): Sprite2D =
        match opt {
            case Some(visible) => CanvasItem.setVisible(visible, sprite)
            case None          => sprite
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
            case Some(centered) => TextureButton.setCentered(centered, button)
            case None           => button
        }

    /// 任意の visible を TextureButton に適用する（None ならそのまま返す）
    def applyButtonVisible(opt: Option[Bool], button: TextureButton): TextureButton =
        match opt {
            case Some(visible) => CanvasItem.setVisible(visible, button)
            case None          => button
        }

    /// 任意の centered を Label2D に適用する（None ならそのまま返す）
    def applyLabelCentered(opt: Option[Bool], label: Label2D): Label2D =
        match opt {
            case Some(centered) => Label2D.setCentered(centered, label)
            case None           => label
        }

    /// 任意の visible を Label2D に適用する（None ならそのまま返す）
    def applyLabelVisible(opt: Option[Bool], label: Label2D): Label2D =
        match opt {
            case Some(visible) => CanvasItem.setVisible(visible, label)
            case None          => label
        }

    /// 任意の zIndex を Label2D に適用する（None ならそのまま返す）
    def applyLabelZIndex(opt: Option[Int32], label: Label2D): Label2D =
        match opt {
            case Some(zIndex) => CanvasItem.setZIndex(zIndex, label)
            case None         => label
        }
}
