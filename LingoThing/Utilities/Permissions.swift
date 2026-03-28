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
                break
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
                return
            case .denied:
                completion(false)
                return
            case .undetermined:
                AVAudioApplication.requestRecordPermission { granted in
                    DispatchQueue.main.async {
                        if granted {
                            completion(true)
                            return
                        }

                        // Fallback path for edge cases where AVAudioApplication
                        // returns without moving AVFoundation TCC state.
                        let captureStatus = AVCaptureDevice.authorizationStatus(for: .audio)
                        if captureStatus == .notDetermined {
                            AVCaptureDevice.requestAccess(for: .audio) { fallbackGranted in
                                DispatchQueue.main.async {
                                    completion(fallbackGranted)
                                }
                            }
                        } else {
                            completion(captureStatus == .authorized)
                        }
                    }
                }
                return
            @unknown default:
                break
            }
        }

        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async { completion(granted) }
            }
        case .denied, .restricted:
            completion(false)
        @unknown default:
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
        requestMicrophone { micGranted in
            requestSpeechRecognition { speechGranted in
                completion(micGranted && speechGranted)
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
