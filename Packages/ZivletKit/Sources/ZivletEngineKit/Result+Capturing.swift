import ZivletCore

extension Result where Failure == JobError {
    /// The outcome of a typed-throwing async call as a value, for task groups and shared tasks.
    public static func capturing(_ body: () async throws(JobError) -> Success) async -> Result<Success, JobError> {
        do {
            return .success(try await body())
        } catch {
            return .failure(error)
        }
    }
}
