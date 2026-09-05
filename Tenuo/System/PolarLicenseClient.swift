import Foundation

enum PolarLicenseError: LocalizedError, Equatable {
    case invalidLicense
    case activationLimit
    case network
    case server
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidLicense: return "This license key is not valid for Tenuo."
        case .activationLimit:
            return
                "This license has reached its device limit. Deactivate another device in Polar and try again."
        case .network:
            return "Tenuo could not reach Polar. Check your internet connection and try again."
        case .server: return "Polar could not complete the request. Try again in a moment."
        case .invalidResponse: return "Polar returned an unexpected response."
        }
    }
}

struct PolarActivationResult {
    let activationID: String
    let displayKey: String?
}

struct PolarValidationResult {
    let displayKey: String?
}

struct PolarLicenseClient {
    let configuration: PolarConfiguration
    private let session: URLSession

    init(configuration: PolarConfiguration, session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
    }

    func activate(key: String, label: String) async throws -> PolarActivationResult {
        let body = ActivateRequest(
            key: key,
            organizationID: configuration.organizationID,
            label: label)
        let response: ActivationResponse = try await post(
            path: "/v1/customer-portal/license-keys/activate", body: body)
        guard response.licenseKey.status == "granted",
            response.licenseKey.benefitID == configuration.benefitID
        else { throw PolarLicenseError.invalidLicense }
        return PolarActivationResult(
            activationID: response.id,
            displayKey: response.licenseKey.displayKey)
    }

    func validate(record: LicenseRecord) async throws -> PolarValidationResult {
        let body = ValidateRequest(
            key: record.key,
            organizationID: configuration.organizationID,
            activationID: record.activationID,
            benefitID: configuration.benefitID)
        let response: ValidationResponse = try await post(
            path: "/v1/customer-portal/license-keys/validate", body: body)
        guard response.status == "granted",
            response.benefitID == configuration.benefitID
        else { throw PolarLicenseError.invalidLicense }
        return PolarValidationResult(displayKey: response.displayKey)
    }

    func deactivate(record: LicenseRecord) async throws {
        let body = DeactivateRequest(
            key: record.key,
            organizationID: configuration.organizationID,
            activationID: record.activationID)
        _ = try await post(
            path: "/v1/customer-portal/license-keys/deactivate", body: body,
            responseType: EmptyResponse.self)
    }

    private func post<Body: Encodable, Response: Decodable>(
        path: String,
        body: Body,
        responseType: Response.Type = Response.self
    ) async throws -> Response {
        var request = URLRequest(url: configuration.apiURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw PolarLicenseError.network
        }

        guard let http = response as? HTTPURLResponse else {
            throw PolarLicenseError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw Self.error(for: http.statusCode)
        }
        if Response.self == EmptyResponse.self {
            return EmptyResponse() as! Response
        }
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw PolarLicenseError.invalidResponse
        }
    }

    private static func error(for statusCode: Int) -> PolarLicenseError {
        if statusCode == 403 { return .activationLimit }
        if statusCode == 404 || statusCode == 422 { return .invalidLicense }
        return .server
    }
}

private struct ActivateRequest: Encodable {
    let key: String
    let organizationID: String
    let label: String

    enum CodingKeys: String, CodingKey {
        case key; case organizationID = "organization_id"; case label
    }
}

private struct ValidateRequest: Encodable {
    let key: String
    let organizationID: String
    let activationID: String
    let benefitID: String

    enum CodingKeys: String, CodingKey {
        case key
        case organizationID = "organization_id"
        case activationID = "activation_id"
        case benefitID = "benefit_id"
    }
}

private struct DeactivateRequest: Encodable {
    let key: String
    let organizationID: String
    let activationID: String

    enum CodingKeys: String, CodingKey {
        case key
        case organizationID = "organization_id"
        case activationID = "activation_id"
    }
}

private struct ActivationResponse: Decodable {
    let id: String
    let licenseKey: LicenseKeyResponse

    enum CodingKeys: String, CodingKey {
        case id
        case licenseKey = "license_key"
    }
}

private struct ValidationResponse: Decodable {
    let benefitID: String
    let status: String
    let displayKey: String?

    enum CodingKeys: String, CodingKey {
        case benefitID = "benefit_id"
        case status
        case displayKey = "display_key"
    }
}

private struct LicenseKeyResponse: Decodable {
    let benefitID: String
    let status: String
    let displayKey: String?

    enum CodingKeys: String, CodingKey {
        case benefitID = "benefit_id"
        case status
        case displayKey = "display_key"
    }
}

private struct EmptyResponse: Decodable {}
