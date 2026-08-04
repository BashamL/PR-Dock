import Foundation

enum GitHubServiceError: LocalizedError {
    case cliNotFound
    case commandFailed(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .cliNotFound:
            return "GitHub CLI was not found. Install it with `brew install gh`."
        case .commandFailed(let message):
            return message.isEmpty ? "The GitHub command failed." : message
        case .invalidResponse:
            return "GitHub returned an unexpected response."
        }
    }
}

struct GitHubService {
    private let graphQLQuery = """
    query($q: String!) {
      viewer { login }
      rateLimit { remaining resetAt }
      search(query: $q, type: ISSUE, first: 50) {
        nodes {
          ... on PullRequest {
            title
            url
            number
            isDraft
            createdAt
            updatedAt
            headRefName
            baseRefName
            reviewDecision
            mergeStateStatus
            additions
            deletions
            comments { totalCount }
            labels(first: 3) {
              nodes { name color }
            }
            commits(last: 1) {
              nodes {
                commit {
                  statusCheckRollup { state }
                }
              }
            }
            repository { nameWithOwner }
          }
        }
      }
    }
    """

    func fetchPullRequests() async throws -> GitHubPayload {
        let login = try await runGitHub(["api", "user", "--jq", ".login"])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !login.isEmpty else {
            throw GitHubServiceError.invalidResponse
        }

        let output = try await runGitHub([
            "api",
            "graphql",
            "-f", "query=\(graphQLQuery)",
            "-f", "q=is:pr is:open author:\(login)",
            "--jq", ".data | {viewer: .viewer.login, rateLimit: .rateLimit, prs: .search.nodes}",
        ])

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard let data = output.data(using: .utf8) else {
            throw GitHubServiceError.invalidResponse
        }

        do {
            return try decoder.decode(GitHubPayload.self, from: data)
        } catch {
            throw GitHubServiceError.commandFailed("Could not decode GitHub data: \(error.localizedDescription)")
        }
    }

    func squashMerge(_ pullRequest: PullRequest) async throws {
        _ = try await runGitHub([
            "pr",
            "merge",
            pullRequest.url.absoluteString,
            "--squash",
        ])
    }

    private func runGitHub(_ arguments: [String]) async throws -> String {
        guard let executable = githubCLIURL() else {
            throw GitHubServiceError.cliNotFound
        }

        return try await CommandRunner.run(executable: executable, arguments: arguments)
    }

    private func githubCLIURL() -> URL? {
        let candidates = [
            "/opt/homebrew/bin/gh",
            "/usr/local/bin/gh",
            "/usr/bin/gh",
        ]

        return candidates
            .first(where: FileManager.default.isExecutableFile(atPath:))
            .map(URL.init(fileURLWithPath:))
    }
}

private enum CommandRunner {
    static func run(executable: URL, arguments: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let outputPipe = Pipe()
                let errorPipe = Pipe()

                process.executableURL = executable
                process.arguments = arguments
                process.standardOutput = outputPipe
                process.standardError = errorPipe

                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                    return
                }

                let group = DispatchGroup()
                var outputData = Data()
                var errorData = Data()

                group.enter()
                DispatchQueue.global(qos: .userInitiated).async {
                    outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                    group.leave()
                }

                group.enter()
                DispatchQueue.global(qos: .userInitiated).async {
                    errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                    group.leave()
                }

                process.waitUntilExit()
                group.wait()

                let output = String(decoding: outputData, as: UTF8.self)
                let errorOutput = String(decoding: errorData, as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                guard process.terminationStatus == 0 else {
                    continuation.resume(
                        throwing: GitHubServiceError.commandFailed(errorOutput)
                    )
                    return
                }

                continuation.resume(returning: output)
            }
        }
    }
}
