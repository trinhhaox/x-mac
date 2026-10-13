import Cocoa
import AudioToolbox

public class SoundEffectManager {
    public static let shared = SoundEffectManager()
    
    public enum SoundType {
        case cut
        case paste
        case undo
        case clean
        case mount
        case eject
        case error
    }
    
    private init() {}
    
    public func play(_ sound: SoundType) {
        guard UserDefaults.standard.bool(forKey: "EnableSoundEffects") else { return }
        
        DispatchQueue.global(qos: .userInitiated).async {
            switch sound {
            case .cut:
                NSSound(named: "Purr")?.play()
            case .paste:
                NSSound(named: "Pop")?.play()
            case .undo:
                NSSound(named: "Submarine")?.play()
            case .clean:
                NSSound(named: "Glass")?.play()
            case .mount:
                NSSound(named: "Blow")?.play()
            case .eject:
                NSSound(named: "Bottle")?.play()
            case .error:
                NSSound(named: "Basso")?.play()
            }
        }
    }
}
