// SceneSerializer — scene.json の特定ノードの "pos" フィールドだけを書き戻す
//
// 全 Scene を JSON にシリアライズし直すのではなく、ファイルから JSON を再パースし、
// 指定 NodePath を辿って当該ノードの "pos" を新しい [x, y] に置き換えてから書き戻す。
// この方針なら NodeTag や状態を持つノード（Bird など）の特殊扱いを考えなくて済む。
//
// 対応するルート JSON 形:
//   - 単一オブジェクト（MenuScene 等）
//   - 配列ルート（複数ルートノード）
//
// NodePath は List[String] で、各要素はノードの "name" と一致する必要がある。
// ルート要素の name から始まり、子は "children" 配列の中から name 一致で辿る。

mod SceneSerializer {
    import java.math.BigDecimal

    use Json.JsonElement
    use Json.JsonElement.{JsonObject, JsonArray, JsonNumber}

    // ========================================================================
    // 公開 API
    // ========================================================================

    /// 指定 JSON ファイルの NodePath にあるノードの "pos" を newPos で上書きして書き戻す。
    /// 失敗時は bug! でクラッシュする（エディタ操作で起きるなら開発時に潰すべき）。
    pub def updatePos(jsonPath: String, nodePath: NodePath, newPos: Vec2.Vec2):
            Unit \ {Fs.FileRead, Fs.FileWrite} =
        let readResult = run { Fs.ReadFile.read(jsonPath) } with Fs.ReadFile.runWithFileRead;
        let textResult = readResult |> Result.mapErr(error -> "read failed: ${error}");
        let updated = forM (
            text     <- textResult;
            json     <- Json.Parse.parse(String.trim(text)) |> Option.toOk("JSON parse failed");
            replaced <- replacePosAtRoot(nodePath, newPos, json)
        ) yield replaced;
        match updated {
            case Ok(newJson) =>
                let pretty = Json.Write.toPrettyString(2, newJson);
                let writeResult = run {
                    Fs.WriteFile.write({str = pretty}, jsonPath)
                } with Fs.WriteFile.runWithFileWrite;
                match writeResult {
                    case Ok(_)    => ()
                    case Err(error) => bug!("SceneSerializer.updatePos: write failed: ${error}")
                }
            case Err(message) => bug!("SceneSerializer.updatePos: ${jsonPath}: ${message}")
        }

    // ========================================================================
    // JSON 走査と書き換え
    // ========================================================================

    /// ルート（配列 or オブジェクト）に対して NodePath の先頭名と一致するノードを探し、
    /// その先のパスで replace を続行する
    def replacePosAtRoot(nodePath: NodePath, newPos: Vec2.Vec2,
                         json: JsonElement): Result[String, JsonElement] =
        match nodePath {
            case Nil => Err("empty NodePath")
            case rootName :: rest =>
                match json {
                    case JsonObject(_) =>
                        replacePosInNode(rootName, rest, newPos, json)
                            |> Option.toOk("root node not found: ${rootName}")
                    case JsonArray(arr) =>
                        replaceInArray(rootName, rest, newPos, arr)
                            |> Option.toOk("root node not found in array: ${rootName}")
                            |> Result.map(JsonArray)
                    case _ =>
                        Err("root JSON must be object or array")
                }
        }

    /// 配列の各要素を走査し、name が一致するものを置換する。
    /// 一致するものが見つかれば置換した配列を返す。見つからなければ None
    def replaceInArray(targetName: String, restPath: NodePath, newPos: Vec2.Vec2,
                       arr: Vector[JsonElement]): Option[Vector[JsonElement]] =
        let list = Vector.toList(arr);
        let (found, replaced) = List.foldLeft((acc, element) -> {
            let (foundFlag, accList) = acc;
            if (foundFlag) (true, List.append(accList, element :: Nil))
            else match replacePosInNode(targetName, restPath, newPos, element) {
                case Some(newElement) => (true, List.append(accList, newElement :: Nil))
                case None             => (foundFlag, List.append(accList, element :: Nil))
            }
        }, (false, Nil), list);
        if (found) Some(List.toVector(replaced)) else None

    /// 単一ノード（JsonObject）の "name" を確認し、一致すれば pos を置換する。
    /// 一致しない場合は None
    def replacePosInNode(targetName: String, restPath: NodePath, newPos: Vec2.Vec2,
                         element: JsonElement): Option[JsonElement] =
        match element {
            case JsonObject(map) =>
                let nameOpt: Option[String] = match Map.get("name", map) {
                    case Some(Json.JsonElement.JsonString(s)) => Some(s)
                    case _                                    => None
                };
                match nameOpt {
                    case Some(name) if name == targetName =>
                        Some(applyPathFromHere(restPath, newPos, map))
                    case _ => None
                }
            case _ => None
        }

    /// 末端ノード（このノードが目的のノードか、子を辿る必要があるか）に応じて
    /// pos を置換 or children を辿る
    def applyPathFromHere(restPath: NodePath, newPos: Vec2.Vec2,
                          nodeMap: Map[String, JsonElement]): JsonElement =
        match restPath {
            case Nil =>
                JsonObject(Map.insert("pos", posToJson(newPos), nodeMap))
            case nextName :: deeper =>
                match Map.get("children", nodeMap) {
                    case Some(JsonArray(childArr)) =>
                        match replaceInArray(nextName, deeper, newPos, childArr) {
                            case Some(newArr) =>
                                JsonObject(Map.insert("children", JsonArray(newArr), nodeMap))
                            case None =>
                                JsonObject(nodeMap)
                        }
                    case _ => JsonObject(nodeMap)
                }
        }

    /// Vec2.Vec2 を JSON の [x, y] 配列に変換する。
    /// 整数座標は "144" のように整数として書き出すため stripTrailingZeros を通す。
    /// 端数があるときは "144.5" のように小数点付きで書き出される
    def posToJson(pos: Vec2.Vec2): JsonElement =
        JsonArray(Vector#{
            JsonNumber(floatToBd(pos#x)),
            JsonNumber(floatToBd(pos#y))
        })

    /// Float64 を BigDecimal に変換する。整数値の場合は trailing zero を取り除き
    /// "144.0" ではなく "144" として書き出されるようにする。
    /// 値ベースの Java 静的呼び出しなので副作用はないが、Flix の型検査上 IO 扱いになるため
    /// unsafe IO で包む
    def floatToBd(value: Float64): BigDecimal =
        unsafe IO { BigDecimal.valueOf(value).stripTrailingZeros() }
}
