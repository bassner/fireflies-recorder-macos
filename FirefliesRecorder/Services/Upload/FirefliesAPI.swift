//
//  FirefliesAPI.swift
//  FirefliesRecorder
//
//  Fireflies.ai API integration for audio upload
//

import Foundation

actor FirefliesAPI {
    private let apiEndpoint = URL(string: "https://api.fireflies.ai/graphql")!

    struct UploadAudioInput: Encodable {
        let url: String
        let title: String
        let attendees: [Attendee]?

        struct Attendee: Encodable {
            let displayName: String
            let email: String
            let phoneNumber: String?
        }
    }

    struct GraphQLRequest<Variables: Encodable>: Encodable {
        let query: String
        let variables: Variables
    }

    struct UploadResponse: Decodable {
        let data: DataResponse?
        let errors: [GraphQLError]?

        struct DataResponse: Decodable {
            let uploadAudio: UploadResult?
        }

        struct UploadResult: Decodable {
            let success: Bool
            let title: String?
            let message: String?
        }

        struct GraphQLError: Decodable {
            let message: String
        }
    }

    func uploadAudio(
        fileURL: URL,
        title: String,
        apiKey: String,
        language: String? = nil,
        attendees: [UploadAudioInput.Attendee]? = nil
    ) async throws -> String {
        // Upload to 0x0.st
        let zerox = ZeroxStService()
        let publicURL: URL
        do {
            publicURL = try await zerox.upload(fileURL: fileURL)
            print("FirefliesAPI: Uploaded to 0x0.st: \(publicURL)")
        } catch {
            print("FirefliesAPI: 0x0.st upload failed: \(error.localizedDescription)")
            throw FirefliesError.uploadFailed("Failed to upload file: \(error.localizedDescription)")
        }

        // Then call Fireflies API
        return try await submitToFireflies(
            audioURL: publicURL,
            title: title,
            apiKey: apiKey,
            language: language,
            attendees: attendees
        )
    }

    func submitToFireflies(
        audioURL: URL,
        title: String,
        apiKey: String,
        language: String? = nil,
        attendees: [UploadAudioInput.Attendee]? = nil
    ) async throws -> String {
        let mutation = """
        mutation UploadAudio($input: AudioUploadInput!) {
            uploadAudio(input: $input) {
                success
                title
                message
            }
        }
        """

        struct Variables: Encodable {
            let input: Input

            struct Input: Encodable {
                let url: String
                let title: String
                let custom_language: String?

                enum CodingKeys: String, CodingKey {
                    case url, title, custom_language
                }

                func encode(to encoder: Encoder) throws {
                    var container = encoder.container(keyedBy: CodingKeys.self)
                    try container.encode(url, forKey: .url)
                    try container.encode(title, forKey: .title)
                    // Only include custom_language if it's set
                    if let lang = custom_language {
                        try container.encode(lang, forKey: .custom_language)
                    }
                }
            }
        }

        // Only pass language if it's not "auto"
        let langCode = (language != nil && language != "auto") ? language : nil
        let variables = Variables(input: Variables.Input(url: audioURL.absoluteString, title: title, custom_language: langCode))
        let requestBody = GraphQLRequest(query: mutation, variables: variables)

        var request = URLRequest(url: apiEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw FirefliesError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw FirefliesError.httpError(statusCode: httpResponse.statusCode)
        }

        let uploadResponse = try JSONDecoder().decode(UploadResponse.self, from: data)

        if let errors = uploadResponse.errors, !errors.isEmpty {
            throw FirefliesError.graphQLError(errors.map { $0.message }.joined(separator: ", "))
        }

        guard let result = uploadResponse.data?.uploadAudio else {
            throw FirefliesError.noData
        }

        guard result.success else {
            throw FirefliesError.uploadFailed(result.message ?? "Unknown error")
        }

        return result.title ?? title
    }

    enum FirefliesError: LocalizedError {
        case invalidResponse
        case httpError(statusCode: Int)
        case graphQLError(String)
        case noData
        case uploadFailed(String)

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                return "Invalid response from Fireflies API"
            case .httpError(let statusCode):
                return "Fireflies API returned status code \(statusCode)"
            case .graphQLError(let message):
                return "GraphQL error: \(message)"
            case .noData:
                return "No data in response"
            case .uploadFailed(let message):
                return "Upload failed: \(message)"
            }
        }
    }
}
