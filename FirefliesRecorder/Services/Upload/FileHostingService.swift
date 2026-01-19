//
//  FileHostingService.swift
//  FirefliesRecorder
//
//  Uploads files to 0x0.st temporary hosting
//

import Foundation

// Upload to 0x0.st
actor ZeroxStService {
    private let uploadURL = URL(string: "https://0x0.st")!

    func upload(fileURL: URL) async throws -> URL {
        let boundary = UUID().uuidString

        var request = URLRequest(url: uploadURL)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("FirefliesRecorder/1.0", forHTTPHeaderField: "User-Agent")

        let fileData = try Data(contentsOf: fileURL)
        let fileName = fileURL.lastPathComponent

        var body = Data()

        // Add file field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/mp4\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n".data(using: .utf8)!)

        // Set expiration to 10 minutes from now (ms since epoch)
        let expiresAt = Int64((Date().timeIntervalSince1970 + 600) * 1000)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"expires\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(expiresAt)\r\n".data(using: .utf8)!)

        // Enable secret mode for privacy (randomized URL)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"secret\"\r\n\r\n".data(using: .utf8)!)
        body.append("\r\n".data(using: .utf8)!)

        // Close boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw UploadError.uploadFailed
        }

        guard let urlString = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              let url = URL(string: urlString) else {
            throw UploadError.invalidResponse
        }

        return url
    }

    enum UploadError: LocalizedError {
        case uploadFailed
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .uploadFailed:
                return "Failed to upload file"
            case .invalidResponse:
                return "Invalid response from server"
            }
        }
    }
}
