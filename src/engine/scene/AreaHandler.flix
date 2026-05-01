/// 衝突応答トレイト（ノード主導のエリアイベント処理）
///
/// OnAreaEvent エフェクトの代替。外部ハンドラではなく、
/// ノード型自身が衝突応答ロジックを持つ。
///
/// ゲーム固有の状態 s を受け取り、エンジンノードへのアクセスが必要な場合は
/// Scene.getEngineNode / Scene.mapEngineNode を使う。
///
/// 関連エフェクト Aef により、インスタンスごとに必要なエフェクトを宣言できる。
/// 例: 効果音を鳴らす場合は `type Aef = { GameEngine.Audio }`、
///      純粋な場合は `type Aef = {}` とする。

pub trait AreaHandler[s] {

    /// 衝突応答で発生するエフェクト
    type Aef: Eff

    /// 自分のエリアに他ノードが侵入したとき呼ばれる。
    /// Scene を書き換えて返す。
    ///
    /// selfPath: 自分のパス
    /// selfState: 自分のゲーム状態
    /// otherPath: 相手のパス
    /// otherState: 相手のゲーム状態
    /// scene: 現在のシーン
    pub def onAreaEntered(
        selfPath: NodePath,
        selfState: s,
        otherPath: NodePath,
        otherState: s,
        scene: Scene[s]
    ): Scene[s] \ AreaHandler.Aef[s]

    /// 自分のエリアから他ノードが離脱したとき呼ばれる。
    /// デフォルトでは何もしない。
    pub def onAreaExited(
        _selfPath: NodePath,
        _selfState: s,
        _otherPath: NodePath,
        _otherState: s,
        scene: Scene[s]
    ): Scene[s] \ AreaHandler.Aef[s] = checked_ecast(scene)
}
