import AVFoundation
import Speech
import AppKit

struct Permissions {
    private static func recordPermissionStatus() -> AVAuthorizationStatus? {
        guard #available(macOS 14.0, *) else { return nil }
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

    static var microphoneStatus: AVAuthorizationStatus {
        let captureStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        guard let recordStatus = recordPermissionStatus() else {
            return captureStatus
        }

        // Reconcile status from both APIs. Treat as allowed if either API reports authorized.
        if captureStatus == .authorized || recordStatus == .authorized {
            return .authorized
        }
        if captureStatus == .notDetermined || recordStatus == .notDetermined {
            return .notDetermined
        }
        if captureStatus == .restricted || recordStatus == .restricted {
            return .restricted
        }
        return .denied
    }

    static var speechStatus: SFSpeechRecognizerAuthorizationStatus {
        SFSpeechRecognizer.authorizationStatus()
    }

    static var hasUndeterminedPermissions: Bool {
        microphoneStatus == .notDetermined || speechStatus == .notDetermined
    }

    static func requestMicrophone(completion: @escaping (Bool) -> Void) {
        let captureStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        if captureStatus == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { _ in
                DispatchQueue.main.async { completion(microphoneAuthorized) }
            }
            return
        }

        if #available(macOS 14.0, *), AVAudioApplication.shared.recordPermission == .undetermined {
            AVAudioApplication.requestRecordPermission { _ in
                DispatchQueue.main.async { completion(microphoneAuthorized) }
            }
            return
        }

        completion(microphoneAuthorized)
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
