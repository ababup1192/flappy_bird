// EditHistory — エディタ編集の履歴を保持し、Cmd+Z で巻き戻す仕組み
//
// algebraic effect として `Rewind` を切り出し、各編集箇所（ドラッグドロップ・矢印 nudge）が
// 直前の状態を `save` する。Cmd+Z 押下時に `rewind` で取り出して、ノードを記録された位置に
// 戻して JSON にも書き戻す。
//
// `withRewind` ハンドラは Region 上の `Ref[List[Entry], r]` で履歴を保持する。
// Flix 公式 examples の backtracking パターン（save/rewind 命名と handler-with-Ref/MutMap）
// に倣っているが、エディタ undo は「過去地点から再実行」ではなく「状態の復元」のため
// 継続キャプチャはせず、`rewind` は単に `Option[Entry]` を返すだけにしている

mod EditHistory {

    /// 1 編集の巻き戻し情報。
    /// jsonPath:     書き戻し先の scene.json
    /// nodePath:     対象ノード
    /// prevWorldPos: 編集前のワールド座標（ここに戻せば直前の状態に復元される）
    pub type alias Entry = {
        jsonPath = String,
        nodePath = NodePath,
        prevWorldPos = Vec2.Vec2
    }

    /// 編集履歴 stack を扱うエフェクト。
    ///   - save:   編集直前の状態を 1 件積む
    ///   - rewind: 直近の保存を取り出す（LIFO）。空ならば None
    pub eff Rewind {
        def save(entry: Entry): Unit
        def rewind(): Option[Entry]
    }

    /// Region 上の Ref を closure で握って Rewind を実装するハンドラ。
    /// stack は無制限（エディタセッションの編集回数 × ~80byte 程度なので実害なし）
    pub def withRewind(rc: Region[r]):
            (Unit -> a \ ef) -> a \ (ef - Rewind) + r =
        thunk -> {
            let history: Ref[List[Entry], r] = Ref.fresh(rc, Nil);
            run thunk() with handler Rewind {
                def save(entry, k) = {
                    Ref.put(entry :: Ref.get(history), history);
                    k(())
                }
                def rewind(k) = match Ref.get(history) {
                    case Nil          => k(None)
                    case top :: rest =>
                        Ref.put(rest, history);
                        k(Some(top))
                }
            }
        }
}
