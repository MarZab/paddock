import A2UICore
import A2UISwiftUI
import BasicCatalog
import BasicCatalogSwiftUI
import Foundation
import SwiftUI

/// The one catalog A2UI tabs have: A2UI's v1.0 basic catalog under its own id, with every
/// component and function, formatting for the Mac's locale. Image, Video, and AudioPlayer are
/// Paddock's, so their bytes come through the sandbox (`A2UIMedia`); `openUrl` asks the tab to open
/// the page in the sandbox's browser.
@MainActor
enum PaddockCatalog {
    static func make(media: A2UIMediaStore, openURLHandler: any OpenURLHandler) -> Catalog<ComponentImplementation> {
        let replaced: [String: ComponentViewBuilder] = [
            "Image": { node in AnyView(PaddockImage(node: node, media: media)) },
            "Video": { node in AnyView(PaddockVideo(node: node, media: media)) },
            "AudioPlayer": { node in AnyView(PaddockAudio(node: node, media: media)) },
        ]
        let components = BasicCatalogImplementation.v10Components.map { component in
            replaced[component.name].map { ComponentImplementation(api: component, builder: $0) } ?? component
        }
        return Catalog(
            id: BasicCatalog.catalogURI(version: .v10),
            protocolVersion: .v10,
            components: components,
            functions: V10BasicFunctions.makeFunctions(locale: .current, openURLHandler: openURLHandler)
        )
    }
}
