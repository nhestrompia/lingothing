import AVFoundation
import Speech
import AppKit

struct Permissions {
    static var microphoneStatus: AVAuthorizationStatus {
        if #available(macOS 14.0, *) {
            switch AVAudioApplication.shared.recordPermission {
            case .granted:
                return .authorized
            case .denied:
                return .denied
            case .undetermined:
                return .notDetermined
            @unknown default:
                return .restricted
            }
        }
        return AVCaptureDevice.authorizationStatus(for: .audio)
    }

    static var speechStatus: SFSpeechRecognizerAuthorizationStatus {
        SFSpeechRecognizer.authorizationStatus()
    }

    static var hasUndeterminedPermissions: Bool {
        microphoneStatus == .notDetermined || speechStatus == .notDetermined
    }

    static func requestMicrophone(completion: @escaping (Bool) -> Void) {
        if #available(macOS 14.0, *) {
            switch AVAudioApplication.shared.recordPermission {
            case .granted:
                completion(true)
            case .undetermined:
                AVAudioApplication.requestRecordPermission { granted in
                    DispatchQueue.main.async { completion(granted) }
                }
            case .denied:
                completion(false)
            @unknown default:
                completion(false)
            }
            return
        }

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
        requestMicrophone { _ in
            requestSpeechRecognition { _ in
                completion(microphoneAuthorized && speechAuthorized)
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
        microphoneStatus == .authorized
    }

    static var speechAuthorized: Bool {
        SFSpeechRecognizer.authorizationStatus() == .authorized
    }

    static func openMicrophonePrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") else { return }
        NSWorkspace.shared.open(url)
    }

    static func openSpeechPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition") else { return }
        NSWorkspace.shared.open(url)
    }
}
