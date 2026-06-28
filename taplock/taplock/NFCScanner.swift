import Combine
import CoreNFC
import Foundation

enum NFCScannerError: Error {
    case unavailable
    case missingTagIdentifier
    case connectionFailed(String)
    case sessionEnded(String)

    var userMessage: String {
        switch self {
        case .unavailable:
            return "NFC scanning is not available on this device. Test this on a physical iPhone."
        case .missingTagIdentifier:
            return "This NFC card could not be identified. Try a different NFC card."
        case .connectionFailed(let message):
            return "NFC card connection failed: \(message)"
        case .sessionEnded(let message):
            return "NFC scan ended: \(message)"
        }
    }
}

final class NFCScanner: NSObject, ObservableObject {
    @Published private(set) var isScanning = false

    private var session: NFCTagReaderSession?
    private var completion: ((Result<String, NFCScannerError>) -> Void)?

    func scan(completion: @escaping (Result<String, NFCScannerError>) -> Void) {
        guard NFCTagReaderSession.readingAvailable else {
            completion(.failure(.unavailable))
            return
        }

        self.completion = completion

        let configuration = NFCTagReaderSession.Configuration(
            pollingOption: [.iso14443, .iso15693]
        )
        let session = NFCTagReaderSession(
            configuration: configuration,
            delegate: self,
            queue: .main
        )

        session.alertMessage = "Hold your TapLock NFC card near the top of your iPhone."
        self.session = session
        isScanning = true
        session.begin()
    }

    private func finish(_ result: Result<String, NFCScannerError>) {
        isScanning = false
        session = nil
        completion?(result)
        completion = nil
    }

    private func identifier(for tag: NFCTag) -> String? {
        switch tag {
        case .miFare(let tag):
            return tag.identifier.hexString
        case .iso7816(let tag):
            return tag.identifier.hexString
        case .iso15693(let tag):
            return tag.identifier.hexString
        case .feliCa(let tag):
            return tag.currentIDm.hexString
        @unknown default:
            return nil
        }
    }
}

extension NFCScanner: NFCTagReaderSessionDelegate {
    func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {
        isScanning = true
    }

    func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        guard tags.count == 1, let tag = tags.first else {
            session.alertMessage = "Hold only one NFC card near the iPhone."
            session.restartPolling()
            return
        }

        session.connect(to: tag) { [weak self] error in
            guard let self else {
                return
            }

            if let error {
                session.invalidate(errorMessage: "Could not read this NFC card.")
                self.finish(.failure(.connectionFailed(error.localizedDescription)))
                return
            }

            guard let cardID = self.identifier(for: tag), !cardID.isEmpty else {
                session.invalidate(errorMessage: "Could not identify this NFC card.")
                self.finish(.failure(.missingTagIdentifier))
                return
            }

            session.alertMessage = "TapLock card scanned."
            session.invalidate()
            self.finish(.success(cardID))
        }
    }

    func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
        let nsError = error as NSError
        let userCanceledCode = NFCReaderError.readerSessionInvalidationErrorUserCanceled.rawValue
        let firstTagReadCode = NFCReaderError.readerSessionInvalidationErrorFirstNDEFTagRead.rawValue

        guard nsError.code != firstTagReadCode else {
            return
        }

        if nsError.code == userCanceledCode {
            finish(.failure(.sessionEnded("Canceled.")))
        } else {
            finish(.failure(.sessionEnded(error.localizedDescription)))
        }
    }
}

private extension Data {
    var hexString: String {
        map { String(format: "%02X", $0) }.joined()
    }
}
