extension RunnerInput {
    func excluding(_ ids: Set<String>) -> RunnerInput {
        guard !ids.isEmpty else { return self }

        let kept = mutants.filter { !ids.contains($0.id) }
        let touchedPaths = Set(mutants.filter { ids.contains($0.id) }.map(\.filePath))

        let files: [SchematizedFile] = schematizedFiles.compactMap { file in
            guard touchedPaths.contains(file.originalPath) else { return file }

            let remaining = kept.filter { $0.filePath == file.originalPath && $0.isSchematizable }

            guard !remaining.isEmpty else { return nil }

            guard
                let content = SchemaNarrower.regeneratedSchema(
                    originalPath: file.originalPath, keeping: remaining, importStyle: importStyle
                )
            else { return file }

            return SchematizedFile(originalPath: file.originalPath, schematizedContent: content)
        }

        return RunnerInput(
            projectPath: projectPath,
            projectType: projectType,
            timeout: timeout,
            concurrency: concurrency,
            noCache: noCache,
            schematizedFiles: files,
            mutants: kept,
            importStyle: importStyle
        )
    }
}
