import Foundation

enum GitHubServiceError: LocalizedError, Equatable {
    case cliNotFound
    case notAuthenticated
    case network(String)
    case rateLimited
    case timedOut
    case commandFailed(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .cliNotFound:
            "GitHub CLI was not found. Choose its location in Settings."
        case .notAuthenticated:
            "GitHub CLI is not authenticated. Run `gh auth login` and try again."
        case .network(let message):
            message.isEmpty ? "GitHub could not be reached." : message
        case .rateLimited:
            "GitHub’s API rate limit has been reached. PR Dock will retry later."
        case .timedOut:
            "GitHub took too long to respond."
        case .commandFailed(let message):
            message.isEmpty ? "The GitHub command failed." : message
        case .invalidResponse:
            "GitHub returned an unexpected response."
        }
    }

    static func classify(commandOutput: String) -> GitHubServiceError {
        let lowercased = commandOutput.lowercased()
        if lowercased.contains("not logged") ||
            lowercased.contains("authentication") ||
            lowercased.contains("authenticate") {
            return .notAuthenticated
        }
        if lowercased.contains("rate limit") {
            return .rateLimited
        }
        if lowercased.contains("network") ||
            lowercased.contains("connection") ||
            lowercased.contains("could not resolve host") {
            return .network(commandOutput)
        }
        return .commandFailed(commandOutput)
    }
}

protocol GitHubServing: Sendable {
    func fetchPullRequests() async throws -> GitHubPayload
    func squashMerge(_ pullRequest: PullRequest) async throws
}

struct GitHubService: GitHubServing {
    private let executableURL: URL?
    private let timeout: Duration

    init(executableURL: URL?, timeout: Duration = .seconds(30)) {
        self.executableURL = executableURL
        self.timeout = timeout
    }

    private let graphQLQuery = """
    query($authored: String!, $reviews: String!) {
      viewer { login }
      rateLimit { remaining resetAt }
      authored: search(query: $authored, type: ISSUE, first: 50) {
        nodes {
          ...PullRequestFields
        }
      }
      reviewRequested: search(query: $reviews, type: ISSUE, first: 50) {
        nodes {
          ...PullRequestFields
        }
      }
    }

    fragment PullRequestFields on PullRequest {
      title
      url
      number
      author { login }
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
    """

    func fetchPullRequests() async throws -> GitHubPayload {
        let output = try await runGitHub([
            "api",
            "graphql",
            "-f", "query=\(graphQLQuery)",
            "-f", "authored=is:pr is:open author:@me",
            "-f", "reviews=is:pr is:open review-requested:@me",
            "--jq",
            """
            .data | {
              viewer: .viewer.login,
              rateLimit: .rateLimit,
              prs: (
                (.authored.nodes | map(. + {scope: "authored"})) +
                (.reviewRequested.nodes | map(. + {scope: "reviewRequested"}))
                | unique_by(.url)
              )
            }
            """,
        ])

        guard let data = output.data(using: .utf8) else {
            throw GitHubServiceError.invalidResponse
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            return try decoder.decode(GitHubPayload.self, from: data)
        } catch {
            throw GitHubServiceError.commandFailed(
                "Could not decode GitHub data: \(error.localizedDescription)"
            )
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
        guard let executableURL else {
            throw GitHubServiceError.cliNotFound
        }

        do {
            return try await CommandRunner.run(
                executable: executableURL,
                arguments: arguments,
                timeout: timeout
            )
        } catch let error as GitHubServiceError {
            throw error
        } catch {
            throw GitHubServiceError.commandFailed(error.localizedDescription)
        }
    }
}

private enum CommandRunner {
    static func run(
        executable: URL,
        arguments: [String],
        timeout: Duration
    ) async throws -> String {
        try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                try await execute(executable: executable, arguments: arguments)
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw GitHubServiceError.timedOut
            }

            guard let result = try await group.next() else {
                throw GitHubServiceError.invalidResponse
            }
            group.cancelAll()
            return result
        }
    }

    private static func execute(
        executable: URL,
        arguments: [String]
    ) async throws -> String {
        let processReference = ProcessReference()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    let fileManager = FileManager.default
                    let workingDirectory = fileManager.temporaryDirectory
                        .appendingPathComponent("PRDock-\(UUID().uuidString)")
                    let outputURL = workingDirectory.appendingPathComponent("stdout")
                    let errorURL = workingDirectory.appendingPathComponent("stderr")

                    do {
                        try fileManager.createDirectory(
                            at: workingDirectory,
                            withIntermediateDirectories: true
                        )
                        fileManager.createFile(atPath: outputURL.path, contents: nil)
                        fileManager.createFile(atPath: errorURL.path, contents: nil)

                        let outputHandle = try FileHandle(forWritingTo: outputURL)
                        let errorHandle = try FileHandle(forWritingTo: errorURL)
                        let process = Process()
                        process.executableURL = executable
                        process.arguments = arguments
                        process.standardOutput = outputHandle
                        process.standardError = errorHandle
                        guard processReference.install(process) else {
                            throw CancellationError()
                        }

                        try process.run()
                        processReference.terminateIfCancelled()
                        process.waitUntilExit()
                        try outputHandle.close()
                        try errorHandle.close()

                        let output = String(
                            decoding: try Data(contentsOf: outputURL),
                            as: UTF8.self
                        )
                        let errorOutput = String(
                            decoding: try Data(contentsOf: errorURL),
                            as: UTF8.self
                        ).trimmingCharacters(in: .whitespacesAndNewlines)

                        try? fileManager.removeItem(at: workingDirectory)

                        guard process.terminationStatus == 0 else {
                            continuation.resume(
                                throwing: GitHubServiceError.classify(
                                    commandOutput: errorOutput
                                )
                            )
                            return
                        }
                        continuation.resume(returning: output)
                    } catch {
                        try? fileManager.removeItem(at: workingDirectory)
                        continuation.resume(throwing: error)
                    }
                }
            }
        } onCancel: {
            processReference.terminate()
        }
    }
}

private final class ProcessReference: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var isCancelled = false

    func install(_ process: Process) -> Bool {
        lock.withLock {
            self.process = process
            return !isCancelled
        }
    }

    func terminate() {
        lock.withLock {
            isCancelled = true
            guard let process, process.isRunning else { return }
            process.terminate()
        }
    }

    func terminateIfCancelled() {
        lock.withLock {
            guard isCancelled, let process, process.isRunning else { return }
            process.terminate()
        }
    }
}
