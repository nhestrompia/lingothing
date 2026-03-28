import AVFoundation
import Speech

struct Permissions {
    static var microphoneStatus: AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .audio)
    }

    static var speechStatus: SFSpeechRecognizerAuthorizationStatus {
        SFSpeechRecognizer.authorizationStatus()
    }

    static var hasUndeterminedPermissions: Bool {
        microphoneStatus == .notDetermined || speechStatus == .notDetermined
    }

    static func requestMicrophone(completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async { completion(granted) }
            }
        default:
            completion(false)
        }
    }

    static func requestSpeechRecognition(completion: @escaping (Bool) -> Void) {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            completion(true)
        case .notDetermined:
            SFSpeechRecognizer.requestAuthorization { status in
                DispatchQueue.main.async { completion(status == .authorized) }
            }
        default:
            completion(false)
        }
    }

    static func requestAll(completion: @escaping (Bool) -> Void) {
        requestMicrophone { micGranted in
            guard micGranted else {
                completion(false)
                return
            }
            requestSpeechRecognition { speechGranted in
                completion(speechGranted)
            }
        }
    }

    static func requestForOnboarding(completion: @escaping (Bool) -> Void) {
        requestSpeechRecognition { speechGranted in
            requestMicrophone { micGranted in
                completion(speechGranted && micGranted)
            }
        }
    }

    static var microphoneAuthorized: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    static var speechAuthorized: Bool {
        SFSpeechRecognizer.authorizationStatus() == .authorized
    }
}
