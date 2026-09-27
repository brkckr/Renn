import SwiftUI

/// Icon roles. PLACEHOLDER: SF Symbols stand in until the custom 24 pt, 2 pt-stroke
/// vector family is produced (02 D04, 08 I02). Swap the image source here only.
enum RENNIcon {
    case home, looks, projects, settings
    case create
    case recordVideo, recordBothCameras, importVideo
    case close, favorite, favoriteFilled, crown, chevronRight, warning

    var image: Image {
        switch self {
        case .home: Image(systemName: "house")
        case .looks: Image(systemName: "recordingtape")
        case .projects: Image(systemName: "rectangle.stack")
        case .settings: Image(systemName: "gearshape")
        case .create: Image(systemName: "plus")
        case .recordVideo: Image(systemName: "video")
        case .recordBothCameras: Image(systemName: "camera.on.rectangle")
        case .importVideo: Image(systemName: "photo.on.rectangle")
        case .close: Image(systemName: "xmark")
        case .favorite: Image(systemName: "heart")
        case .favoriteFilled: Image(systemName: "heart.fill")
        case .crown: Image(systemName: "crown.fill")
        case .chevronRight: Image(systemName: "chevron.right")
        case .warning: Image(systemName: "exclamationmark.triangle")
        }
    }
}
