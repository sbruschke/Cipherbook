import SwiftUI
import JournalCore

struct PageRenderSpec {
    var look: PageLook
    var style: PresetStyle
    var text: String
    var ink: Color
    var mainFont: UIFont
    var subFont: UIFont?          // nil ⇒ single-font
    var art: WordArtDrawing?      // word-art doodle, drawn under the text
    var artStrength: Double       // 0…1 multiplier on the doodle's ink opacity
    var artColor: Color           // accent for the doodle's first words
    var exclusion: PageRect?      // page-unit frame the text wraps around; nil ⇒ text runs under the doodle
    var lift: Double              // 0…1, drives shadow height
    var size: CGSize              // nominal page size before widthScale
}

struct FastenerRenderSpec {
    var kind: FastenerKind
    var look: FastenerLook
    var pageSize: CGSize
}

/// Everything a renderer must provide. A SceneKit/RealityKit renderer implements the same
/// protocol; the model, sync, editor and animation paths do not change.
protocol WallRenderer {
    func page(_ spec: PageRenderSpec) -> AnyView
    func fastener(_ spec: FastenerRenderSpec) -> AnyView
}

private struct RendererKey: EnvironmentKey { static let defaultValue: WallRenderer = Render25D() }
extension EnvironmentValues {
    var wallRenderer: WallRenderer {
        get { self[RendererKey.self] }
        set { self[RendererKey.self] = newValue }
    }
}
